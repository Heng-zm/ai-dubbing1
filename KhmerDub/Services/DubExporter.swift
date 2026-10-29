import AVFoundation
import Foundation
import QuartzCore
import UIKit

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
        session.audioTimePitchAlgorithm = .timeDomain
        if let audioMix = composition.audioMix {
            session.audioMix = audioMix
        }

        // Hardware GPU Accelerated 60 FPS Video Composition with Aspect Ratio & Subtitle Burn-In
        if format == .video {
            let videoComposition = buildVideoComposition(
                for: composition.composition,
                project: project,
                duration: composition.composition.duration.seconds
            )
            session.videoComposition = videoComposition
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
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                session.exportAsynchronously {
                    continuation.resume()
                }
            }
        } onCancel: {
            session.cancelExport()
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

                    if project.isSmartDuckingEnabled && !voices.isEmpty {
                        // Smart Audio Ducking: smooth volume ramps during dialogue
                        let rawIntervals = voices
                            .map { (start: $0.segment.start, end: max($0.segment.start + 0.3, $0.segment.end)) }
                            .sorted { $0.start < $1.start }

                        var mergedIntervals: [(start: Double, end: Double)] = []
                        for interval in rawIntervals {
                            if let last = mergedIntervals.last, interval.start <= last.end + 0.45 {
                                mergedIntervals[mergedIntervals.count - 1].end = max(last.end, interval.end)
                            } else {
                                mergedIntervals.append(interval)
                            }
                        }

                        let normalVol = Float(project.originalVolume.clamped(to: 0.1...1.0))
                        let duckedVol = Float(max(0.04, min(Double(normalVol) * 0.16, 0.14)))

                        parameters.setVolume(normalVol, at: .zero)
                        for interval in mergedIntervals {
                            let rampInStart = max(0, interval.start - 0.25)
                            let rampInDuration = max(0.05, interval.start - rampInStart)
                            parameters.setVolumeRamp(
                                fromStartVolume: normalVol,
                                toEndVolume: duckedVol,
                                timeRange: CMTimeRange(
                                    start: CMTime(seconds: rampInStart, preferredTimescale: 600),
                                    duration: CMTime(seconds: rampInDuration, preferredTimescale: 600)
                                )
                            )
                            parameters.setVolume(
                                duckedVol,
                                at: CMTime(seconds: interval.start, preferredTimescale: 600)
                            )
                            parameters.setVolumeRamp(
                                fromStartVolume: duckedVol,
                                toEndVolume: normalVol,
                                timeRange: CMTimeRange(
                                    start: CMTime(seconds: interval.end, preferredTimescale: 600),
                                    duration: CMTime(seconds: 0.35, preferredTimescale: 600)
                                )
                            )
                        }
                    } else {
                        let volume = project.mode == .background
                            ? min(project.originalVolume, 0.28)
                            : project.originalVolume
                        parameters.setVolume(Float(volume.clamped(to: 0...1)), at: .zero)
                    }
                    mixParameters.append(parameters)
                }
            }

            if sourceDuration.seconds <= 0.01, voices.isEmpty {
                throw ExportError.noMedia
            }
        }

        // Dialogue track pool: reuse up to 4 alternating tracks to prevent
        // AVFoundation track limit exhaustion (-11820 / -11838) on projects with many lines.
        final class TrackSlot {
            let track: AVMutableCompositionTrack
            var lastEndTime: CMTime
            let parameters: AVMutableAudioMixInputParameters

            init(track: AVMutableCompositionTrack, parameters: AVMutableAudioMixInputParameters) {
                self.track = track
                self.lastEndTime = .zero
                self.parameters = parameters
            }
        }

        var trackPool: [TrackSlot] = []
        let maxTracks = 4

        for voice in voices {
            let asset = AVURLAsset(url: voice.url)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            guard let sourceAudio = audioTracks.first else {
                throw ExportError.renderFailed("A generated voice clip had no audio.")
            }
            let range = try await sourceAudio.load(.timeRange)
            guard range.duration.seconds > 0.01 else { continue }
            let insertTime = CMTime(
                seconds: max(0, voice.segment.start),
                preferredTimescale: 600
            )

            // Select an existing non-overlapping track or allocate a new one if below max limit
            var selectedSlot: TrackSlot? = trackPool.first(where: { $0.lastEndTime <= insertTime })
            if selectedSlot == nil && trackPool.count < maxTracks {
                guard let newTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else {
                    throw ExportError.renderFailed("A voice track could not be created.")
                }
                let params = AVMutableAudioMixInputParameters(track: newTrack)
                let newSlot = TrackSlot(track: newTrack, parameters: params)
                trackPool.append(newSlot)
                mixParameters.append(params)
                selectedSlot = newSlot
            }
            if selectedSlot == nil {
                selectedSlot = trackPool.min(by: { $0.lastEndTime < $1.lastEndTime })
            }
            guard let slot = selectedSlot else {
                throw ExportError.renderFailed("A voice track could not be created.")
            }

            try slot.track.insertTimeRange(range, of: sourceAudio, at: insertTime)
            var finalDuration = range.duration
            if project.fitSpeech, range.duration.seconds > voice.segment.duration {
                let target = CMTime(
                    seconds: max(0.2, voice.segment.duration),
                    preferredTimescale: 600
                )
                slot.track.scaleTimeRange(
                    CMTimeRange(start: insertTime, duration: range.duration),
                    toDuration: target
                )
                finalDuration = target
            }
            slot.lastEndTime = insertTime + finalDuration

            var volume = project.dubVolume.clamped(to: 0...1)
            if project.normalizeVolume, let peak = await AudioPeakAnalyzer.peak(for: voice.url) {
                if peak > 0.02 {
                    let gain = min(1.8, 0.88 / peak)
                    volume = min(1, volume * Double(gain))
                }
            }
            slot.parameters.setVolume(Float(volume), at: insertTime)
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

    private func buildVideoComposition(
        for composition: AVMutableComposition,
        project: DubProject,
        duration: Double
    ) -> AVMutableVideoComposition {
        guard let sourceTrack = composition.tracks(withMediaType: .video).first else {
            let fallback = AVMutableVideoComposition(propertiesOf: composition)
            fallback.frameDuration = CMTime(value: 1, timescale: project.is60FPS ? 60 : 30)
            return fallback
        }

        let naturalSize = sourceTrack.naturalSize
        let transform = sourceTrack.preferredTransform
        let isRotated = transform.b != 0 || transform.c != 0
        let realSourceSize = isRotated
            ? CGSize(width: abs(naturalSize.height), height: abs(naturalSize.width))
            : CGSize(width: abs(naturalSize.width), height: abs(naturalSize.height))

        let targetAspectRatio = project.currentAspectRatio
        let renderSize: CGSize
        switch targetAspectRatio {
        case .original:
            renderSize = realSourceSize.width > 0 && realSourceSize.height > 0
                ? realSourceSize
                : CGSize(width: 1920, height: 1080)
        case .nineSixteen:
            renderSize = CGSize(width: 1080, height: 1920)
        case .sixteenNine:
            renderSize = CGSize(width: 1920, height: 1080)
        case .oneOne:
            renderSize = CGSize(width: 1080, height: 1080)
        }

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: sourceTrack)
        if targetAspectRatio == .original {
            layerInstruction.setTransform(transform, at: .zero)
        } else {
            let scaleX = renderSize.width / max(1, realSourceSize.width)
            let scaleY = renderSize.height / max(1, realSourceSize.height)
            let fitScale = min(scaleX, scaleY)

            let scaledW = realSourceSize.width * fitScale
            let scaledH = realSourceSize.height * fitScale
            let posX = (renderSize.width - scaledW) / 2.0
            let posY = (renderSize.height - scaledH) / 2.0

            var finalTransform = transform
            finalTransform = finalTransform.concatenating(CGAffineTransform(scaleX: fitScale, y: fitScale))
            finalTransform = finalTransform.concatenating(CGAffineTransform(translationX: posX, y: posY))
            layerInstruction.setTransform(finalTransform, at: .zero)
        }

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        instruction.layerInstructions = [layerInstruction]
        instruction.backgroundColor = CGColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 1.0)

        let videoComposition = AVMutableVideoComposition()
        let fps: Int32 = project.is60FPS ? 60 : 30
        videoComposition.frameDuration = CMTime(value: 1, timescale: fps)
        videoComposition.renderSize = renderSize
        videoComposition.instructions = [instruction]
        videoComposition.renderScale = 1.0

        // Burn-In Open Captions (CapCut Style)
        if project.shouldBurnInSubtitles {
            let usableSegments = project.segments.filter {
                $0.isIncluded && $0.end > $0.start && !$0.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if !usableSegments.isEmpty {
                let videoLayer = CALayer()
                videoLayer.frame = CGRect(origin: .zero, size: renderSize)

                let rootLayer = CALayer()
                rootLayer.frame = CGRect(origin: .zero, size: renderSize)
                rootLayer.addSublayer(videoLayer)

                let overlayLayer = CALayer()
                overlayLayer.frame = CGRect(origin: .zero, size: renderSize)
                rootLayer.addSublayer(overlayLayer)

                let totalDuration = max(0.1, duration > 0 ? duration : composition.duration.seconds)
                let scaleFactor = renderSize.width / 1080.0
                let subWidth = min(renderSize.width * 0.90, 940.0 * scaleFactor)
                let subHeight = max(60.0 * scaleFactor, 90.0 * scaleFactor)
                let subY = renderSize.height * 0.12

                for segment in usableSegments {
                    let cleanText = segment.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cleanText.isEmpty else { continue }

                    let pillLayer = CALayer()
                    pillLayer.frame = CGRect(
                        x: (renderSize.width - subWidth) / 2.0,
                        y: subY,
                        width: subWidth,
                        height: subHeight
                    )

                    switch project.currentSubtitleStyle {
                    case .pill:
                        pillLayer.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0.72)
                        pillLayer.cornerRadius = 16 * scaleFactor
                        pillLayer.borderWidth = 1.5 * scaleFactor
                        pillLayer.borderColor = CGColor(red: 1, green: 1, blue: 1, alpha: 0.18)
                        pillLayer.shadowColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0.5)
                        pillLayer.shadowRadius = 8 * scaleFactor
                    case .neon:
                        pillLayer.backgroundColor = CGColor(red: 0.05, green: 0.07, blue: 0.12, alpha: 0.85)
                        pillLayer.cornerRadius = 16 * scaleFactor
                        pillLayer.borderWidth = 2.0 * scaleFactor
                        pillLayer.borderColor = CGColor(red: 0.0, green: 0.85, blue: 0.85, alpha: 0.9)
                        pillLayer.shadowColor = CGColor(red: 0.0, green: 0.85, blue: 0.85, alpha: 0.7)
                        pillLayer.shadowRadius = 10 * scaleFactor
                    case .classic:
                        pillLayer.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0.0)
                        pillLayer.shadowColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0.9)
                        pillLayer.shadowRadius = 6 * scaleFactor
                        pillLayer.shadowOffset = CGSize(width: 0, height: -2)
                        pillLayer.shadowOpacity = 1.0
                    }

                    let textLayer = CATextLayer()
                    textLayer.frame = pillLayer.bounds.insetBy(dx: 14 * scaleFactor, dy: 8 * scaleFactor)
                    textLayer.string = cleanText
                    textLayer.font = "KhmerSangamMN" as CFTypeRef
                    textLayer.fontSize = max(20.0, 32.0 * scaleFactor)
                    textLayer.foregroundColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
                    textLayer.alignmentMode = .center
                    textLayer.isWrapped = true
                    textLayer.contentsScale = 2.0
                    pillLayer.addSublayer(textLayer)

                    let anim = CAKeyframeAnimation(keyPath: "opacity")
                    anim.duration = totalDuration
                    let sTime = (segment.start / totalDuration).clamped(to: 0...1)
                    let eTime = (segment.end / totalDuration).clamped(to: 0...1)
                    anim.keyTimes = [
                        0.0,
                        NSNumber(value: max(0, sTime - 0.0001)),
                        NSNumber(value: sTime),
                        NSNumber(value: eTime),
                        NSNumber(value: min(1.0, eTime + 0.0001)),
                        1.0
                    ]
                    anim.values = [0.0, 0.0, 1.0, 1.0, 0.0, 0.0]
                    anim.isRemovedOnCompletion = false
                    anim.fillMode = .forwards
                    anim.beginTime = AVCoreAnimationBeginTimeAtZero
                    pillLayer.add(anim, forKey: "visibility")

                    overlayLayer.addSublayer(pillLayer)
                }

                videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
                    postProcessingAsVideoLayer: videoLayer,
                    in: rootLayer
                )
            }
        }

        return videoComposition
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
