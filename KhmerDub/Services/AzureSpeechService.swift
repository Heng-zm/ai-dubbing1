import Foundation

struct AzureVoiceOption: Identifiable, Hashable {
    let id: String
    let name: String
    let genderKey: String
    let descriptionKey: String

    static let all: [AzureVoiceOption] = [
        AzureVoiceOption(
            id: "km-KH-SreymomNeural",
            name: "Sreymom",
            genderKey: "voice.female",
            descriptionKey: "voice.azureNote"
        ),
        AzureVoiceOption(
            id: "km-KH-PisethNeural",
            name: "Piseth",
            genderKey: "voice.male",
            descriptionKey: "voice.azureNote"
        )
    ]
}

enum AzureSpeechError: LocalizedError {
    case missingKey
    case invalidRegion
    case emptyText
    case invalidResponse
    case http(status: Int, message: String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "Add your Azure Speech key in Settings to use Azure Khmer voices."
        case .invalidRegion:
            return "Enter a valid Azure region, for example southeastasia."
        case .emptyText:
            return "There is no Khmer text to speak."
        case .invalidResponse:
            return "Azure returned an audio response KhmerDub could not read."
        case .http(let status, let message):
            return "Azure Speech returned HTTP \(status): \(message)"
        case .network(let message):
            return "Azure Speech network error: \(message)"
        }
    }
}

struct AzureSpeechService {
    let configuration: AzureSpeechConfiguration
    private let session: URLSession

    init(configuration: AzureSpeechConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func synthesize(
        text: String,
        voice: String,
        rate: Double,
        pitch: Double,
        outputURL: URL
    ) async throws {
        let cleanText = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { throw AzureSpeechError.emptyText }
        let region = configuration.region
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard Self.isValidRegion(region) else { throw AzureSpeechError.invalidRegion }
        guard let endpoint = URL(string: "https://\(region).tts.speech.microsoft.com/cognitiveservices/v1") else {
            throw AzureSpeechError.invalidRegion
        }
        let voiceName = voice.trimmed.nonEmpty ?? configuration.voiceName
        guard !voiceName.isEmpty else { throw AzureSpeechError.invalidResponse }

        let ratePercent = Int(((rate.clamped(to: 0.5...2.0) - 1.0) * 100).rounded())
        let pitchPercent = Int(((pitch.clamped(to: 0.5...2.0) - 1.0) * 50).rounded())
        let rateString = String(format: "%+d%%", ratePercent)
        let pitchString = String(format: "%+d%%", pitchPercent)
        let ssml = "<speak version='1.0' xml:lang='km-KH'><voice name='\(Self.escapeXML(voiceName))'><prosody rate='\(rateString)' pitch='\(pitchString)'>\(Self.escapeXML(cleanText))</prosody></voice></speak>"

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue(configuration.apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("application/ssml+xml", forHTTPHeaderField: "Content-Type")
        request.setValue("audio-24khz-96kbitrate-mono-mp3", forHTTPHeaderField: "X-Microsoft-OutputFormat")
        request.setValue("KhmerDub/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.httpBody = Data(ssml.utf8)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AzureSpeechError.invalidResponse
            }
            guard (200..<300).contains(http.statusCode) else {
                let message = String(data: data, encoding: .utf8)?
                    .trimmed
                    .truncated(to: 280) ?? ""
                throw AzureSpeechError.http(status: http.statusCode, message: message)
            }
            guard !data.isEmpty else { throw AzureSpeechError.invalidResponse }
            try data.write(to: outputURL, options: [.atomic])
        } catch let error as AzureSpeechError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw AzureSpeechError.network(error.localizedDescription)
        }
    }

    static func isValidRegion(_ region: String) -> Bool {
        guard !region.isEmpty, region.count < 40 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789")
        return region.rangeOfCharacter(from: allowed.inverted) == nil
    }

    static func escapeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
