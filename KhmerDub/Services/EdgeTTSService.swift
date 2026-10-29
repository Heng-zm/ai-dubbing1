import Foundation

enum EdgeTTSError: LocalizedError {
    case invalidURL
    case connectionFailed
    case emptyResponse
    case timeout
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Edge-TTS URL."
        case .connectionFailed:
            return "Could not connect to Edge-TTS service."
        case .emptyResponse:
            return "No audio received from Edge-TTS."
        case .timeout:
            return "Edge-TTS request timed out."
        case .serverError(let message):
            return "Edge-TTS error: \(message)"
        }
    }
}

actor EdgeTTSService {
    static let shared = EdgeTTSService()

    private let endpointBase = "wss://speech.platform.bing.com/consumer/speech/synthesize/readahead/edge/v1"
    private let trustedToken = "6A5AA1D4EA654941A3E44A6856F4E60F"

    func synthesize(
        text: String,
        voiceName: String,
        rate: Double = 1.0,
        pitch: Double = 1.0,
        outputURL: URL
    ) async throws -> URL {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { throw TTSError.emptyText }

        let connectionID = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        guard let url = URL(string: "\(endpointBase)?TrustedClientToken=\(trustedToken)&ConnectionId=\(connectionID)") else {
            throw EdgeTTSError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 Edg/130.0.0.0", forHTTPHeaderField: "User-Agent")
        request.setValue("chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold", forHTTPHeaderField: "Origin")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = 25

        let session = URLSession(configuration: .default)
        let webSocketTask = session.webSocketTask(with: request)
        webSocketTask.resume()

        let ratePercent = Int(round((rate - 1.0) * 100))
        let rateStr = ratePercent >= 0 ? "+\(ratePercent)%" : "\(ratePercent)%"

        let pitchPercent = Int(round((pitch - 1.0) * 50))
        let pitchStr = pitchPercent >= 0 ? "+\(pitchPercent)Hz" : "\(pitchPercent)Hz"

        let escaped = cleanText
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")

        // 1. Send speech.config message
        let configMessage = "Content-Type:application/json; charset=utf-8\r\nPath:speech.config\r\n\r\n{\"context\":{\"synthesis\":{\"audio\":{\"metadataoptions\":{\"sentenceBoundaryEnabled\":\"false\",\"wordBoundaryEnabled\":\"false\"},\"outputFormat\":\"audio-24khz-48kbitrate-mono-mp3\"}}}}"
        try await webSocketTask.send(.string(configMessage))

        // 2. Send SSML request
        let requestID = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let ssml = "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='km-KH'><voice name='\(voiceName)'><prosody pitch='\(pitchStr)' rate='\(rateStr)'>\(escaped)</prosody></voice></speak>"
        let ssmlMessage = "X-RequestId:\(requestID)\r\nContent-Type:application/ssml+xml\r\nPath:ssml\r\n\r\n\(ssml)"
        try await webSocketTask.send(.string(ssmlMessage))

        // 3. Receive binary audio data until Path:turn.end
        var audioBuffer = Data()
        var completed = false
        let maxDuration: UInt64 = 25_000_000_000 // 25 seconds
        let startTime = DispatchTime.now().uptimeNanoseconds

        while !completed {
            if DispatchTime.now().uptimeNanoseconds - startTime > maxDuration {
                webSocketTask.cancel(with: .goingAway, reason: nil)
                throw EdgeTTSError.timeout
            }

            let message: URLSessionWebSocketTask.Message
            do {
                message = try await webSocketTask.receive()
            } catch {
                if !audioBuffer.isEmpty {
                    break
                }
                throw EdgeTTSError.connectionFailed
            }

            switch message {
            case .string(let text):
                if text.contains("Path:turn.end") {
                    completed = true
                }
            case .data(let data):
                guard data.count > 2 else { continue }
                let headerLength = Int(data[0]) << 8 | Int(data[1])
                let headerEndIndex = 2 + headerLength
                guard data.count >= headerEndIndex else { continue }

                let headerData = data.subdata(in: 2..<headerEndIndex)
                let headerText = String(data: headerData, encoding: .utf8) ?? ""

                if headerText.contains("Path:audio") {
                    let audioPayload = data.subdata(in: headerEndIndex..<data.count)
                    audioBuffer.append(audioPayload)
                }
                if headerText.contains("Path:turn.end") {
                    completed = true
                }
            @unknown default:
                break
            }
        }

        webSocketTask.cancel(with: .normalClosure, reason: nil)

        guard !audioBuffer.isEmpty else {
            throw EdgeTTSError.emptyResponse
        }

        try? FileManager.default.removeItem(at: outputURL)
        try audioBuffer.write(to: outputURL, options: .atomic)
        return outputURL
    }
}
