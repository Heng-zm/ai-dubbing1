import AVFoundation
import CoreTransferable
import Foundation
import PhotosUI
import UIKit
import UniformTypeIdentifiers

struct MovieTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let copy = AppFiles.makeTempURL(extension: ext)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return MovieTransferable(url: copy)
        }
    }
}

struct MediaInfo {
    let duration: Double
    let hasVideo: Bool
    let hasAudio: Bool
    let fileSize: Int64
    let fileExtension: String
    let thumbnail: UIImage?
}

enum MediaError: LocalizedError {
    case noAudio
    case noVideo
    case invalidFile
    case copyFailed
    case metadataFailed
    case audioExportFailed
    case unsupportedType

    var errorDescription: String? {
        switch self {
        case .noAudio: return "No audio track was found in this file."
        case .noVideo: return "No video track was found in this file."
        case .invalidFile: return "This file could not be read."
        case .copyFailed: return "The file could not be copied into the app."
        case .metadataFailed: return "The media metadata could not be read."
        case .audioExportFailed: return "The audio track could not be prepared."
        case .unsupportedType: return "This file type is not supported."
        }
    }
}

enum MediaImporter {
    static let supportedExtensions: Set<String> = [
        "mp4", "mov", "m4v", "m4a", "mp3", "wav", "aiff", "aif", "caf", "mpg", "mpeg", "webm"
    ]

    static func stageImport(from url: URL) throws -> URL {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw MediaError.invalidFile
        }
        let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else {
            throw MediaError.unsupportedType
        }
        let destination = AppFiles.makeTempURL(extension: ext)
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.copyItem(at: url, to: destination)
        } catch {
            throw MediaError.copyFailed
        }
        return destination
    }

    static func stageMovie(_ movie: MovieTransferable) throws -> URL {
        let ext = movie.url.pathExtension.isEmpty ? "mov" : movie.url.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else { throw MediaError.unsupportedType }
        let destination = AppFiles.makeTempURL(extension: ext)
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.copyItem(at: movie.url, to: destination)
        } catch {
            throw MediaError.copyFailed
        }
        return destination
    }

    static func inspect(url: URL) async throws -> MediaInfo {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let durationTime = try await asset.load(.duration)
        let duration = durationTime.seconds
        guard duration.isFinite, duration > 0 else { throw MediaError.metadataFailed }

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else { throw MediaError.noAudio }

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        var thumbnail: UIImage?
        if videoTracks.first != nil {
            thumbnail = await makeThumbnail(asset: asset, duration: duration)
        }

        return MediaInfo(
            duration: duration,
            hasVideo: !videoTracks.isEmpty,
            hasAudio: !audioTracks.isEmpty,
            fileSize: fileSize,
            fileExtension: url.pathExtension.lowercased(),
            thumbnail: thumbnail
        )
    }

    static func install(
        stagedURL: URL,
        projectID: UUID,
        preferredExtension: String
    ) throws -> String {
        let directory = AppFiles.projectMediaDirectory(projectID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ext = preferredExtension.isEmpty ? stagedURL.pathExtension : preferredExtension
        let safeExtension = ext.isEmpty ? "mov" : ext.lowercased()
        let fileName = "source.\(safeExtension)"
        let destination = directory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: stagedURL, to: destination)
        } catch {
            do {
                try FileManager.default.copyItem(at: stagedURL, to: destination)
                try? FileManager.default.removeItem(at: stagedURL)
            } catch {
                throw MediaError.copyFailed
            }
        }
        return fileName
    }

    static func saveThumbnail(_ image: UIImage?, projectID: UUID) -> String? {
        guard let image, let data = image.jpegData(compressionQuality: 0.82) else { return nil }
        let directory = AppFiles.projectMediaDirectory(projectID)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileName = "thumbnail.jpg"
        let url = directory.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: [.atomic])
            return fileName
        } catch {
            return nil
        }
    }

    static func addMedia(
        stagedURL: URL,
        info: MediaInfo,
        to project: inout DubProject
    ) throws {
        let fileName = try install(
            stagedURL: stagedURL,
            projectID: project.id,
            preferredExtension: info.fileExtension
        )
        project.mediaFileName = fileName
        project.thumbnailFileName = saveThumbnail(info.thumbnail, projectID: project.id)
        project.duration = info.duration
        project.hasVideo = info.hasVideo
        project.hasAudio = info.hasAudio
        project.isDemo = false
        project.touch()
    }

    static func makeThumbnail(
        asset: AVAsset,
        duration: Double
    ) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1200, height: 1200)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.2, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.2, preferredTimescale: 600)
        let seconds = min(max(0.15, duration * 0.12), max(0.15, duration - 0.15))
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        do {
            let (cgImage, _) = try await generator.image(at: time)
            return UIImage(cgImage: cgImage)
        } catch {
            do {
                let (cgImage, _) = try await generator.image(at: .zero)
                return UIImage(cgImage: cgImage)
            } catch {
                return nil
            }
        }
    }
}

struct AudioChunk {
    let url: URL
    let start: Double
    let duration: Double
}

enum AudioExtractor {
    static func makeChunks(
        from mediaURL: URL,
        duration: Double,
        maxChunkDuration: Double = 540
    ) async throws -> [AudioChunk] {
        let asset = AVURLAsset(url: mediaURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let sourceTrack = audioTracks.first else { throw MediaError.noAudio }

        let composition = AVMutableComposition()
        guard
            let compositionTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else {
            throw MediaError.audioExportFailed
        }
        let durationTime = try await asset.load(.duration)
        let trackTimeRange = try await sourceTrack.load(.timeRange)
        let totalDuration = min(
            max(0.01, duration),
            min(durationTime.seconds, trackTimeRange.duration.seconds)
        )
        try compositionTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: CMTime(seconds: totalDuration, preferredTimescale: 600)),
            of: sourceTrack,
            at: .zero
        )

        let chunkLength = max(30, maxChunkDuration)
        var ranges: [(Double, Double)] = []
        var cursor = 0.0
        while cursor < totalDuration {
            let length = min(chunkLength, totalDuration - cursor)
            if length > 0.05 {
                ranges.append((cursor, length))
            }
            cursor += chunkLength
        }
        if ranges.isEmpty { ranges = [(0, totalDuration)] }

        var chunks: [AudioChunk] = []
        for (start, length) in ranges {
            let output = AppFiles.makeTempURL(extension: "m4a")
            try? FileManager.default.removeItem(at: output)
            try await export(
                composition: composition,
                timeRange: CMTimeRange(
                    start: CMTime(seconds: start, preferredTimescale: 600),
                    duration: CMTime(seconds: length, preferredTimescale: 600)
                ),
                outputURL: output
            )
            chunks.append(AudioChunk(url: output, start: start, duration: length))
        }
        return chunks
    }

    static func export(
        composition: AVComposition,
        timeRange: CMTimeRange,
        outputURL: URL
    ) async throws {
        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw MediaError.audioExportFailed
        }
        session.outputURL = outputURL
        session.outputFileType = .m4a
        session.timeRange = timeRange
        session.shouldOptimizeForNetworkUse = false
        await withCheckedContinuation { continuation in
            session.exportAsynchronously {
                continuation.resume()
            }
        }
        switch session.status {
        case .completed:
            return
        case .cancelled:
            throw CancellationError()
        default:
            throw session.error ?? MediaError.audioExportFailed
        }
    }
}
