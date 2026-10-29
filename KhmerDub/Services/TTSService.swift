import AVFAudio
import AVFoundation
import Foundation

enum TTSError: LocalizedError {
    case noKhmerVoice
    case missingAzureKey
    case invalidRegion
    case emptyText
    case renderFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .noKhmerVoice:
            return "No Khmer voice is available. Configure Azure or install an Apple Khmer voice."
        case .missingAzureKey:
            return "Add your Azure Speech key in Settings to use Azure Khmer voices."
        case .invalidRegion:
            return "Enter a valid Azure region, for example southeastasia."
        case .emptyText:
            return "There is no Khmer text to speak."
        case .renderFailed(let message):
            return "The voice could not be rendered: \(message)"
        case .timeout:
            return "The voice took too long to render."
        }
    }
}

@MainActor
enum AppleTTSService {
    static func khmerVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.lowercased().hasPrefix("km") }
            .sorted { lhs, rhs in
                if lhs.quality.rawValue != rhs.quality.rawValue {
                    return lhs.quality.rawValue > rhs.quality.rawValue
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    static func resolvedVoice(identifier: String) -> AVSpeechSynthesisVoice? {
        if !identifier.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            if voice.language.lowercased().hasPrefix("km") {
                return voice
            }
        }
        return khmerVoices().first
    }

    static func render(
        text: String,
        voiceIdentifier: String,
        rate: Double,
        pitch: Double,
        outputURL: URL
    ) async throws -> URL {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { throw TTSError.emptyText }
        guard let voice = resolvedVoice(identifier: voiceIdentifier) else {
            throw TTSError.noKhmerVoice
        }
        let operation = SpeechRenderOperation()
        return try await operation.render(
            text: cleanText,
            voice: voice,
            rate: rate,
            pitch: pitch,
            outputURL: outputURL
        )
    }
}

@MainActor
private final class SpeechRenderOperation {
    private let synthesizer = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<URL, Error>?
    private var file: AVAudioFile?
    private var outputURL: URL?
    private var writeError: Error?
    private var hasWrittenAudio = false
    private var finished = false
    private var timeoutTask: Task<Void, Never>?

    func render(
        text: String,
        voice: AVSpeechSynthesisVoice,
        rate: Double,
        pitch: Double,
        outputURL: URL
    ) async throws -> URL {
        try? FileManager.default.removeItem(at: outputURL)
        self.outputURL = outputURL
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = voice
            let base = Double(AVSpeechUtteranceDefaultSpeechRate)
            utterance.rate = Float((base * rate.clamped(to: 0.5...2.0)).clamped(to: 0.1...1.0))
            utterance.pitchMultiplier = Float(pitch.clamped(to: 0.5...2.0))
            utterance.postUtteranceDelay = 0
            let estimated = max(20, min(180, Double(text.count) * 0.35 + 15))
            timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(estimated * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.finish(error: TTSError.timeout)
            }
            synthesizer.write(utterance) { [weak self] buffer in
                guard let self else { return }
                Task { @MainActor in
                    self.handle(buffer)
                }
            }
        }
    }

    private func handle(_ buffer: AVAudioBuffer) {
        guard !finished else { return }
        guard let pcm = buffer as? AVAudioPCMBuffer else { return }
        if pcm.frameLength == 0 {
            if hasWrittenAudio {
                finish(error: nil)
            } else {
                finish(error: TTSError.renderFailed("No audio was produced."))
            }
            return
        }
        do {
            if file == nil {
                let settings = pcm.format.settings
                file = try AVAudioFile(
                    forWriting: outputURL ?? AppFiles.makeTempURL(extension: "caf"),
                    settings: settings,
                    commonFormat: pcm.format.commonFormat,
                    interleaved: pcm.format.isInterleaved
                )
            }
            try file?.write(from: pcm)
            hasWrittenAudio = true
        } catch {
            writeError = error
            finish(error: error)
        }
    }

    private func finish(error: Error?) {
        guard !finished else { return }
        finished = true
        timeoutTask?.cancel()
        timeoutTask = nil
        // AVAudioFile has no public close() on iOS 17. Releasing the last
        // reference finalizes the file before the caller starts reading it.
        file = nil
        synthesizer.stopSpeaking(at: .immediate)
        guard let continuation else { return }
        self.continuation = nil
        if let error {
            if let outputURL { try? FileManager.default.removeItem(at: outputURL) }
            continuation.resume(throwing: TTSError.renderFailed(error.localizedDescription))
        } else if let outputURL, hasWrittenAudio, writeError == nil {
            continuation.resume(returning: outputURL)
        } else {
            continuation.resume(throwing: TTSError.renderFailed("No audio was produced."))
        }
    }
}

struct VoiceReadiness {
    let hasAzureKey: Bool
    let appleVoices: [AVSpeechSynthesisVoice]

    var isReady: Bool {
        hasAzureKey || !appleVoices.isEmpty
    }

    var azureReady: Bool { hasAzureKey }
    var appleReady: Bool { !appleVoices.isEmpty }
}

@MainActor
final class TTSService {
    static let shared = TTSService()

    private init() {}

    func readiness(settings: AppSettings) -> VoiceReadiness {
        VoiceReadiness(
            hasAzureKey: settings.hasAzureKey,
            appleVoices: AppleTTSService.khmerVoices()
        )
    }

    func hasAnyVoice(settings: AppSettings) -> Bool {
        readiness(settings: settings).isReady
    }

    func renderToTemporaryFile(
        text: String,
        voice: VoiceChoice,
        rate: Double,
        pitch: Double,
        settings: AppSettings
    ) async throws -> URL {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { throw TTSError.emptyText }
        if voice.isAzure {
            guard let configuration = settings.azureConfiguration else {
                throw TTSError.missingAzureKey
            }
            guard AzureSpeechService.isValidRegion(configuration.region) else {
                throw TTSError.invalidRegion
            }
            let output = AppFiles.makeTempURL(extension: "mp3")
            let service = AzureSpeechService(configuration: configuration)
            try await service.synthesize(
                text: cleanText,
                voice: voice.azureName ?? configuration.voiceName,
                rate: rate,
                pitch: pitch,
                outputURL: output
            )
            return output
        }

        let output = AppFiles.makeTempURL(extension: "caf")
        return try await AppleTTSService.render(
            text: cleanText,
            voiceIdentifier: settings.appleVoiceIdentifier,
            rate: rate,
            pitch: pitch,
            outputURL: output
        )
    }
}

@MainActor
final class SpeechPreviewPlayer: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var errorMessage: String?

    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var tempURL: URL?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func preview(
        text: String,
        voice: VoiceChoice,
        rate: Double,
        pitch: Double,
        settings: AppSettings
    ) async {
        stop()
        errorMessage = nil
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else {
            errorMessage = TTSError.emptyText.localizedDescription
            return
        }
        AudioSession.configureForPlayback()
        if voice.isAzure {
            guard let configuration = settings.azureConfiguration else {
                errorMessage = TTSError.missingAzureKey.localizedDescription
                return
            }
            do {
                let url = AppFiles.makeTempURL(extension: "mp3")
                let service = AzureSpeechService(configuration: configuration)
                try await service.synthesize(
                    text: cleanText,
                    voice: voice.azureName ?? configuration.voiceName,
                    rate: rate,
                    pitch: pitch,
                    outputURL: url
                )
                tempURL = url
                let item = AVPlayerItem(url: url)
                let avPlayer = AVPlayer(playerItem: item)
                player = avPlayer
                endObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: item,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.isPlaying = false
                    }
                }
                isPlaying = true
                avPlayer.play()
            } catch {
                errorMessage = error.localizedDescription
                isPlaying = false
            }
            return
        }

        guard let resolved = AppleTTSService.resolvedVoice(identifier: settings.appleVoiceIdentifier) else {
            errorMessage = TTSError.noKhmerVoice.localizedDescription
            return
        }
        let utterance = AVSpeechUtterance(string: cleanText)
        utterance.voice = resolved
        let base = Double(AVSpeechUtteranceDefaultSpeechRate)
        utterance.rate = Float((base * rate.clamped(to: 0.5...2.0)).clamped(to: 0.1...1.0))
        utterance.pitchMultiplier = Float(pitch.clamped(to: 0.5...2.0))
        isPlaying = true
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        player?.pause()
        player = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        if let tempURL {
            try? FileManager.default.removeItem(at: tempURL)
            self.tempURL = nil
        }
        isPlaying = false
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isPlaying = false
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isPlaying = false
        }
    }
}
