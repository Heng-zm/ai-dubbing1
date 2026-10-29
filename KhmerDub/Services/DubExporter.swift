import AVFoundation
import Foundation

enum ExportPhase: String, CaseIterable {
    case voices
    case mix
    case render
    case subtitles
    case finish

    var localizationKey: String { "export.phase.\(rawValue)" }
}

enum ExportError: LocalizedError {
    case noSegments
    case noTranslatedText
    case noMedia
    case noVideo
    case noVoice
    case invalidTiming
    case renderFailed(String)
    case subtitleFailed

    var errorDescription: String? {
        switch self {
        case .noSegments:
            return "Add at least one line before exporting."
        case .noTranslatedText:
            return "Add Khmer text to at least one included line."
        case .noMedia:
            return "The source media file could not be found."
        case .noVideo:
            return "This project has no video track. Export audio instead."
        case .noVoice:
            return "No Khmer voice is configured for the selected lines."
        case .invalidTiming:
            return "One or more lines have invalid timing."
        case .renderFailed(let message):
            return "The export could not be rendered: \(message)"
        case .subtitleFailed:
            return "The subtitle file could not be written."
        }
    }
}

struct DubExportResult {
    let url: URL
    let kind: ExportKind
    let duration: Double
    let fileSize: Int64
    let subtitleURL: URL?
}

@MainActor
final class DubExporter {
    static let shared = DubExporter()

    private init() {}

    func export(
        project: DubProject,
        settings: AppSettings,
        format: ExportFormat,
        includeSubtitles: Bool,
        progress: @escaping (ExportPhase, Double) -> Void
    ) async throws -> DubExportResult {
        try Task.checkCancellation()
        let usable = project.segments
            .filter { $0.isIncluded && $0.isTranslated }
            .sorted { $0.start < $1.start }
        guard !usable.isEmpty else { throw ExportError.noTranslatedText }
        guard usable.allSatisfy({ $0.end > $0.start && $0.start >= 0 }) else {
            throw ExportError.invalidTiming
        }

        let mediaURL = AppFiles.mediaURL(for: project)
        if format == .video {
            guard project.hasVideo else { throw ExportError.noVideo }
            guard mediaURL != nil else { throw ExportError.noMedia }
        }

        let usesAzure = usable.contains { $0.voice.isAzure }
        let usesApple = usable.contains { !$0.voice.isAzure }
        if usesAzure {
            guard settings.hasAzureKey, settings.azureConfiguration != nil else {
                throw ExportError.noVoice
            }
        }
        if usesApple, AppleTTSService.khmerVoices().isEmpty {
            throw ExportError.noVoice
        }

        AppFiles.createProjectDirectories(project.id)
        let outputURL = uniqueOutputURL(
            project: project,
            extension: format.fileExtension,
            label: "km-dub"
        )
        var temporaryVoices: [URL] = []
        defer {
            for url in temporaryVoices {
                try? FileManager.default.removeItem(at: url)
            }
        }

        progress(.voices, 0.02)
        var rendered: [RenderedVoice] = []
        rendered.reserveCapacity(usable.count)
        for (index, segment) in usable.enumerated() {
            try Task.checkCancellation()
            let fraction = 0.04 + (Double(index) / Double(max(1, usable.count))) * 0.64
            progress(.voices, fraction)
            let url = try await TTSService.shared.renderToTemporaryFile(
                text: segment.translatedText,
                voice: segment.voice,
                rate: segment.rate,
                pitch: segment.pitch,
                settings: settings
            )
            temporaryVoices.append(url)
            rendered.append(RenderedVoice(segment: segment, url: url))
            progress(
                .voices,
                0.04 + (Double(index + 1) / Double(max(1, usable.count))) * 0.64
            )
        }

        try Task.checkCancellation()
        progress(.mix, 0.7)
        let composition = try await makeComposition(
            project: project,
            mediaURL: mediaURL,
            includeVideo: format == .video,
            voices: rendered
        )
        guard composition.composition.duration.seconds > 0.01 else {
            throw ExportError.renderFailed("The timeline is empty.")
        }

        try? FileManager.default.removeItem(at: outputURL)
        let preset = format == .video ? AVAssetExportPresetHighestQuality : AVAssetExportPresetAppleM4A
        guard let session = AVAssetExportSession(
            asset: composition.composition,
            presetName: preset
        ) else {
            throw ExportError.renderFailed("The selected export preset is unavailable.")
        }
        session.outputURL = outputURL
        session.outputFileType = format == .video ? .mp4 : .m4a
        session.shouldOptimizeForNetworkUse = true
        if let audioMix = composition.audioMix {
            session.audioMix = audioMix
        }
        let compositionDuration = composition.composition.duration
        if compositionDuration.seconds.isFinite, compositionDuration.seconds > 0 {
            session.timeRange = CMTimeRange(start: .zero, duration: compositionDuration)
        }

        progress(.render, 0.76)
        let progressTask = Task { @MainActor in
            while !Task.isCancelled {
                let value = 0.76 + min(0.14, max(0, Double(session.progress)) * 0.14)
                progress(.render, value)
                try? await Task.sleep(nanoseconds: 280_000_000)
            }
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously {
                continuation.resume()
            }
        }
        progressTask.cancel()

        switch session.status {
        case .completed:
            break
        case .cancelled:
            try? FileManager.default.removeItem(at: outputURL)
            throw CancellationError()
        default:
            try? FileManager.default.removeItem(at: outputURL)
            throw ExportError.renderFailed(session.error?.localizedDescription ?? "Unknown error.")
        }

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw ExportError.renderFailed("The output file was not created.")
        }
        let size = fileSize(at: outputURL)

        var subtitleURL: URL?
        if includeSubtitles {
            try Task.checkCancellation()
            progress(.subtitles, 0.94)
            let srtURL = uniqueOutputURL(
                project: project,
                extension: "srt",
                label: "km-subtitles"
            )
            try SubtitleExporter.write(project: project, to: srtURL)
            subtitleURL = srtURL
        }

        progress(.finish, 1.0)
        let duration = composition.composition.duration.seconds
        return DubExportResult(
            url: outputURL,
            kind: format == .video ? .video : .audio,
            duration: duration.isFinite && duration > 0 ? duration : project.duration,
            fileSize: size,
            subtitleURL: subtitleURL
        )
    }

    // MARK: - Composition

    private struct RenderedVoice {
        let segment: DubSegment
        let url: URL
    }

    private struct BuiltComposition {
        let composition: AVMutableComposition
        let audioMix: AVMutableAudioMix?
    }

    private func makeComposition(
        project: DubProject,
        mediaURL: URL?,
        includeVideo: Bool,
        voices: [RenderedVoice]
    ) async throws -> BuiltComposition {
        let composition = AVMutableComposition()
        var mixParameters: [AVMutableAudioMixInputParameters] = []

        if let mediaURL {
            let asset = AVURLAsset(url: mediaURL)
            let sourceDuration = try await asset.load(.duration)

            if includeVideo {
                let videoTracks = try await asset.loadTracks(withMediaType: .video)
                guard let sourceVideo = videoTracks.first else { throw ExportError.noVideo }
                guard let videoTrack = composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else {
                    throw ExportError.renderFailed("The video track could not be created.")
                }
                let videoRange = try await sourceVideo.load(.timeRange)
                try videoTrack.insertTimeRange(videoRange, of: sourceVideo, at: .zero)
                videoTrack.preferredTransform = try await sourceVideo.load(.preferredTransform)
            }

            if project.mode != .replace {
                let audioTracks = try await asset.loadTracks(withMediaType: .audio)
                if let sourceAudio = audioTracks.first,
                   let audioTrack = composition.addMutableTrack(
                       withMediaType: .audio,
                       preferredTrackID: kCMPersistentTrackID_Invalid
                   ) {
                    let audioRange = try await sourceAudio.load(.timeRange)
                    try audioTrack.insertTimeRange(audioRange, of: sourceAudio, at: .zero)
                    let parameters = AVMutableAudioMixInputParameters(track: audioTrack)
                    let volume = project.mode == .background
                        ? min(project.originalVolume, 0.28)
                        : project.originalVolume
                    parameters.setVolume(Float(volume.clamped(to: 0...1)), at: .zero)
                    mixParameters.append(parameters)
                }
            }

            if sourceDuration.seconds <= 0.01, voices.isEmpty {
                throw ExportError.noMedia
            }
        }

        for voice in voices {
            let asset = AVURLAsset(url: voice.url)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            guard let sourceAudio = audioTracks.first else {
                throw ExportError.renderFailed("A generated voice clip had no audio.")
            }
            guard let track = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw ExportError.renderFailed("A voice track could not be created.")
            }
            let range = try await sourceAudio.load(.timeRange)
            guard range.duration.seconds > 0.01 else { continue }
            let insertTime = CMTime(
                seconds: max(0, voice.segment.start),
                preferredTimescale: 600
            )
            try track.insertTimeRange(range, of: sourceAudio, at: insertTime)

            if project.fitSpeech, range.duration.seconds > voice.segment.duration {
                let target = CMTime(
                    seconds: max(0.2, voice.segment.duration),
                    preferredTimescale: 600
                )
                track.scaleTimeRange(
                    CMTimeRange(start: insertTime, duration: range.duration),
                    toDuration: target
                )
            }

            let parameters = AVMutableAudioMixInputParameters(track: track)
            var volume = project.dubVolume.clamped(to: 0...1)
            if project.normalizeVolume, let peak = await AudioPeakAnalyzer.peak(for: voice.url) {
                if peak > 0.02 {
                    let gain = min(1.8, 0.88 / peak)
                    volume = min(1, volume * Double(gain))
                }
            }
            parameters.setVolume(Float(volume), at: .zero)
            mixParameters.append(parameters)
        }

        let mix: AVMutableAudioMix?
        if mixParameters.isEmpty {
            mix = nil
        } else {
            let audioMix = AVMutableAudioMix()
            audioMix.inputParameters = mixParameters.map { $0 as AVAudioMixInputParameters }
            mix = audioMix
        }
        return BuiltComposition(composition: composition, audioMix: mix)
    }

    // MARK: - Helpers

    private func uniqueOutputURL(project: DubProject, extension ext: String, label: String) -> URL {
        let directory = AppFiles.projectExportDirectory(project.id)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let base = "\(project.safeTitle)-\(label)-\(Formatters.fileTimestamp())"
        var candidate = directory.appendingPathComponent("\(base).\(ext)")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)-\(counter).\(ext)")
            counter += 1
        }
        return candidate
    }

    private func fileSize(at url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }
}

/// Reads the peak amplitude of a short voice clip so the exporter can balance
/// dialogue levels without changing the original media.
private enum AudioPeakAnalyzer {
    static func peak(for url: URL) async -> Float? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else {
            return nil
        }
        return await Task.detached(priority: .utility) {
            readPeak(asset: asset, track: track)
        }.value
    }

    private static func readPeak(asset: AVAsset, track: AVAssetTrack) -> Float? {
        guard let reader = try? AVAssetReader(asset: asset) else { return nil }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 8_000,
            AVNumberOfChannelsKey: 1
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }

        var peak = 0
        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            var length = 0
            var pointer: UnsafeMutablePointer<Int8>?
            let status = CMBlockBufferGetDataPointer(
                blockBuffer,
                atOffset: 0,
                lengthAtOffsetOut: nil,
                totalLengthOut: &length,
                dataPointerOut: &pointer
            )
            guard status == kCMBlockBufferNoErr, let pointer, length >= 2 else { continue }
            let sampleCount = length / MemoryLayout<Int16>.size
            pointer.withMemoryRebound(to: Int16.self, capacity: sampleCount) { samples in
                for index in 0..<sampleCount {
                    let value = abs(Int(samples[index]))
                    if value > peak { peak = value }
                }
            }
        }
        guard peak > 0 else { return nil }
        return Float(Double(peak) / Double(Int16.max))
    }
}
