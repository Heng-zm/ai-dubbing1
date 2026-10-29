import Foundation

struct TranscriptLine: Identifiable, Hashable {
    let id: UUID = UUID()
    let start: Double
    let end: Double
    let text: String
    let speaker: String
}

enum TranscriptionPhase {
    case extracting
    case uploading
    case transcribing
}

enum AIServiceError: LocalizedError {
    case missingConfiguration
    case invalidURL
    case network(String)
    case http(status: Int, message: String)
    case decoding
    case emptyResponse
    case noSpeech
    case fileTooLarge
    case noMedia
    case cancelled
    case unsupportedResponse

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "Add your AI API key in Settings first."
        case .invalidURL:
            return "The AI base URL is invalid."
        case .network(let message):
            return "Network error: \(message)"
        case .http(let status, let message):
            if message.isEmpty {
                return "The AI provider returned HTTP \(status)."
            }
            return "The AI provider returned HTTP \(status): \(message)"
        case .decoding:
            return "The AI provider returned a response KhmerDub could not read."
        case .emptyResponse:
            return "The AI provider returned an empty response."
        case .noSpeech:
            return "No speech was detected in this media."
        case .fileTooLarge:
            return "The audio file is too large for the selected model."
        case .noMedia:
            return "Import media before running AI."
        case .cancelled:
            return "Cancelled."
        case .unsupportedResponse:
            return "The AI provider returned an unsupported response."
        }
    }
}

@MainActor
final class OpenAIService {
    private let configuration: OpenAIConfiguration
    private let session: URLSession

    init(configuration: OpenAIConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    // MARK: - Connection

    func testConnection() async throws {
        let url = configuration.normalizedBaseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": configuration.chatModel,
            "messages": [
                ["role": "user", "content": "Reply with the single word OK."]
            ],
            "max_tokens": 4,
            "temperature": 0
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await perform(request)
        let response = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard response.choices.first?.message.content?.trimmed.nonEmpty != nil else {
            throw AIServiceError.emptyResponse
        }
    }

    // MARK: - Transcription

    func transcribe(
        mediaURL: URL,
        duration: Double,
        language: SourceLanguage,
        progress: @escaping (TranscriptionPhase, Double) -> Void
    ) async throws -> [TranscriptLine] {
        guard FileManager.default.fileExists(atPath: mediaURL.path) else {
            throw AIServiceError.noMedia
        }
        try Task.checkCancellation()
        progress(.extracting, 0.04)

        let chunks: [AudioChunk]
        do {
            chunks = try await AudioExtractor.makeChunks(
                from: mediaURL,
                duration: duration,
                maxChunkDuration: 540
            )
        } catch {
            throw error
        }
        defer {
            for chunk in chunks {
                try? FileManager.default.removeItem(at: chunk.url)
            }
        }
        guard !chunks.isEmpty else { throw AIServiceError.noSpeech }

        var lines: [TranscriptLine] = []
        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            let base = 0.08 + (Double(index) / Double(max(1, chunks.count))) * 0.82
            progress(.uploading, base)
            let attributes = try? FileManager.default.attributesOfItem(atPath: chunk.url.path)
            let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            if size > 24_000_000 {
                throw AIServiceError.fileTooLarge
            }
            progress(.transcribing, min(0.94, base + 0.04))
            let chunkLines = try await transcribeChunk(
                url: chunk.url,
                duration: chunk.duration,
                language: language
            )
            for line in chunkLines {
                lines.append(
                    TranscriptLine(
                        start: line.start + chunk.start,
                        end: line.end + chunk.start,
                        text: line.text,
                        speaker: line.speaker
                    )
                )
            }
        }
        progress(.transcribing, 1.0)
        guard lines.contains(where: { !$0.text.trimmed.isEmpty }) else {
            throw AIServiceError.noSpeech
        }
        return lines.sorted { $0.start < $1.start }
    }

    private func transcribeChunk(
        url: URL,
        duration: Double,
        language: SourceLanguage
    ) async throws -> [TranscriptLine] {
        do {
            return try await requestTranscription(
                url: url,
                duration: duration,
                language: language,
                verbose: true
            )
        } catch let error as AIServiceError {
            if
                case .http(let status, let message) = error,
                status == 400,
                message.localizedCaseInsensitiveContains("response_format") ||
                message.localizedCaseInsensitiveContains("timestamp")
            {
                return try await requestTranscription(
                    url: url,
                    duration: duration,
                    language: language,
                    verbose: false
                )
            }
            throw error
        }
    }

    private func requestTranscription(
        url: URL,
        duration: Double,
        language: SourceLanguage,
        verbose: Bool
    ) async throws -> [TranscriptLine] {
        let endpoint = configuration.normalizedBaseURL.appendingPathComponent("audio/transcriptions")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        let boundary = "KhmerDub-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let mimeType: String
        switch url.pathExtension.lowercased() {
        case "mp3": mimeType = "audio/mpeg"
        case "wav": mimeType = "audio/wav"
        case "m4a", "mp4": mimeType = "audio/mp4"
        case "webm": mimeType = "audio/webm"
        default: mimeType = "application/octet-stream"
        }
        var body = Data()
        body.appendMultipart(boundary: boundary, name: "model", value: configuration.transcriptionModel)
        if let code = language.code {
            body.appendMultipart(boundary: boundary, name: "language", value: code)
        }
        body.appendMultipart(
            boundary: boundary,
            name: "response_format",
            value: verbose ? "verbose_json" : "json"
        )
        if verbose {
            body.appendMultipart(boundary: boundary, name: "timestamp_granularities[]", value: "segment")
        }
        body.appendFile(
            boundary: boundary,
            name: "file",
            fileName: url.lastPathComponent,
            mimeType: mimeType,
            fileData: try Data(contentsOf: url)
        )
        body.appendString("--\(boundary)--\r\n")
        request.httpBody = body

        let data = try await perform(request)
        if verbose {
            let response = try? JSONDecoder().decode(WhisperVerboseResponse.self, from: data)
            if let response {
                let segments = (response.segments ?? []).compactMap { segment -> TranscriptLine? in
                    let text = segment.text.trimmed
                    guard !text.isEmpty else { return nil }
                    let start = max(0, min(segment.start, max(0, duration - 0.01)))
                    let end = max(start + 0.1, min(segment.end, max(duration, start + 0.1)))
                    return TranscriptLine(start: start, end: end, text: text, speaker: "Speaker 1")
                }
                if !segments.isEmpty { return segments }
                if let text = response.text?.trimmed.nonEmpty {
                    return [
                        TranscriptLine(
                            start: 0,
                            end: max(0.5, duration),
                            text: text,
                            speaker: "Speaker 1"
                        )
                    ]
                }
                // The server returned a well-formed verbose response but with no
                // detectable speech — surface this as noSpeech rather than a
                // generic decoding error.
                throw AIServiceError.noSpeech
            }
        }
        let response = try? JSONDecoder().decode(WhisperJSONResponse.self, from: data)
        if let text = response?.text?.trimmed.nonEmpty {
            return [
                TranscriptLine(
                    start: 0,
                    end: max(0.5, duration),
                    text: text,
                    speaker: "Speaker 1"
                )
            ]
        }
        // If the response decoded but produced empty text, the media had no speech.
        // Otherwise, the response was in an unrecognised shape.
        if response != nil {
            throw AIServiceError.noSpeech
        }
        throw AIServiceError.decoding
    }

    // MARK: - Translation

    func translate(
        segments: [DubSegment],
        sourceLanguage: SourceLanguage,
        style: TranslationStyle,
        glossary: [GlossaryEntry],
        preserveNames: Bool
    ) async throws -> [UUID: String] {
        let eligible = segments.filter { !$0.originalText.trimmed.isEmpty }
        guard !eligible.isEmpty else { throw AIServiceError.emptyResponse }
        var result: [UUID: String] = [:]
        let batchSize = 35
        var start = 0
        while start < eligible.count {
            try Task.checkCancellation()
            let end = min(start + batchSize, eligible.count)
            let batch = Array(eligible[start..<end])
            let partial = try await translateBatch(
                segments: batch,
                sourceLanguage: sourceLanguage,
                style: style,
                glossary: glossary,
                preserveNames: preserveNames
            )
            for (key, value) in partial {
                result[key] = value
            }
            start = end
        }
        guard !result.isEmpty else { throw AIServiceError.emptyResponse }
        return result
    }

    private func translateBatch(
        segments: [DubSegment],
        sourceLanguage: SourceLanguage,
        style: TranslationStyle,
        glossary: [GlossaryEntry],
        preserveNames: Bool
    ) async throws -> [UUID: String] {
        let payload = segments.map { segment in
            TranslationInput(
                id: segment.id.uuidString,
                start: segment.start,
                end: segment.end,
                speaker: segment.speaker,
                text: segment.originalText
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let inputData = try encoder.encode(payload)
        guard let inputJSON = String(data: inputData, encoding: .utf8) else {
            throw AIServiceError.decoding
        }

        let glossaryText: String
        if glossary.isEmpty {
            glossaryText = "No glossary provided."
        } else {
            glossaryText = glossary.map { entry in
                let translated = entry.translation.trimmed
                return "- \(entry.term) => \(translated.isEmpty ? "(keep original spelling)" : translated)"
            }.joined(separator: "\n")
        }

        let sourceName = sourceLanguage == .auto ? "the source language" : sourceLanguage.rawValue
        let systemPrompt = """
        You are a professional audiovisual translator localizing into Cambodian Khmer (km-KH) for dubbing.
        Translate each line into natural spoken Khmer using Khmer script. The result must sound like a native Khmer voice actor, not a literal machine translation.

        Rules:
        - Keep the meaning, tone, emotion, and intent of the original.
        - Use natural spoken Khmer grammar and appropriate pronouns. Do not translate word by word.
        - Keep proper names, brands, and numbers accurate. \(preserveNames ? "Preserve names unless the glossary gives a Khmer spelling." : "")
        - Keep each line concise enough to fit its original speaking duration.
        - Never add new facts, explanations, or subtitles.
        - Do not use Latin script unless a name or brand is normally written that way.
        - Follow the glossary exactly when a term appears.
        - Style: \(style.promptDescription)
        - Source language: \(sourceName).

        Glossary:
        \(glossaryText)

        Return JSON only, with this exact shape:
        {"segments":[{"id":"<the same id>","text":"<Khmer translation>"}]}
        Do not use markdown fences or add commentary.
        """
        let userPrompt = """
        Translate these time-coded lines into Khmer. Keep every id unchanged.
        \(inputJSON)
        """
        let content = try await chat(
            messages: [
                ChatMessage(role: "system", content: systemPrompt),
                ChatMessage(role: "user", content: userPrompt)
            ],
            temperature: 0.2
        )
        let parsed = try parseTranslation(content)
        var result: [UUID: String] = [:]
        for (idString, text) in parsed {
            guard let id = UUID(uuidString: idString) else { continue }
            let cleaned = text.trimmed
            guard !cleaned.isEmpty else { continue }
            result[id] = cleaned
        }
        return result
    }

    func polishKhmer(_ text: String, style: TranslationStyle) async throws -> String {
        let prompt = """
        You are a Khmer dubbing editor. Rewrite the following Khmer line so it sounds natural, clear, and broadcast-ready when spoken aloud.
        Keep the meaning exactly. Keep names and numbers. Return only the improved Khmer text, with no quotes or explanation.
        Style: \(style.promptDescription)

        Khmer text:
        \(text)
        """
        let content = try await chat(
            messages: [ChatMessage(role: "user", content: prompt)],
            temperature: 0.15
        )
        let cleaned = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))
        guard !cleaned.isEmpty else { throw AIServiceError.emptyResponse }
        return cleaned
    }

    // MARK: - Networking

    private func chat(messages: [ChatMessage], temperature: Double) async throws -> String {
        let endpoint = configuration.normalizedBaseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        let payload = ChatRequest(
            model: configuration.chatModel,
            messages: messages,
            temperature: temperature
        )
        request.httpBody = try JSONEncoder().encode(payload)
        let data = try await perform(request)
        let response = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = response.choices.first?.message.content?.trimmed.nonEmpty else {
            throw AIServiceError.emptyResponse
        }
        return content
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AIServiceError.network("Invalid response")
            }
            guard (200..<300).contains(http.statusCode) else {
                let message = Self.errorMessage(from: data)
                throw AIServiceError.http(status: http.statusCode, message: message)
            }
            return data
        } catch let error as AIServiceError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw AIServiceError.cancelled
        } catch {
            throw AIServiceError.network(error.localizedDescription)
        }
    }

    private static func errorMessage(from data: Data) -> String {
        if
            let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data),
            let message = envelope.error?.message
        {
            return message.truncated(to: 280)
        }
        if let text = String(data: data, encoding: .utf8) {
            return text.truncated(to: 280)
        }
        return ""
    }

    private func parseTranslation(_ content: String) throws -> [String: String] {
        let cleaned = Self.stripMarkdownFences(content)

        // 1. Check if the model returned a top-level array of segments: [{"id": "...", "text": "..."}]
        if let arrayStart = cleaned.firstIndex(of: "["),
           let arrayEnd = cleaned.lastIndex(of: "]"),
           arrayStart < arrayEnd {
            let objStart = cleaned.firstIndex(of: "{")
            if objStart == nil || arrayStart < objStart! {
                let arrayJSON = String(cleaned[arrayStart...arrayEnd])
                if let arrayData = arrayJSON.data(using: .utf8),
                   let items = try? JSONDecoder().decode([TranslationEnvelope.Item].self, from: arrayData) {
                    var output: [String: String] = [:]
                    for item in items {
                        output[item.id] = item.text
                    }
                    if !output.isEmpty { return output }
                }
            }
        }

        // 2. Object envelope: {"segments": [...]} or dictionary {"id": "text"}
        guard
            let start = cleaned.firstIndex(of: "{"),
            let end = cleaned.lastIndex(of: "}"),
            start <= end
        else {
            throw AIServiceError.unsupportedResponse
        }
        let json = String(cleaned[start...end])
        guard let data = json.data(using: .utf8) else {
            throw AIServiceError.decoding
        }
        if let envelope = try? JSONDecoder().decode(TranslationEnvelope.self, from: data) {
            var output: [String: String] = [:]
            for item in envelope.segments {
                output[item.id] = item.text
            }
            return output
        }
        if let dictionary = try? JSONDecoder().decode([String: String].self, from: data) {
            return dictionary
        }
        if let items = try? JSONDecoder().decode([TranslationEnvelope.Item].self, from: data) {
            var output: [String: String] = [:]
            for item in items {
                output[item.id] = item.text
            }
            return output
        }
        throw AIServiceError.decoding
    }

    static func stripMarkdownFences(_ content: String) -> String {
        var value = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("```") {
            if let firstNewline = value.firstIndex(of: "\n") {
                value = String(value[value.index(after: firstNewline)...])
            }
            if let fence = value.range(of: "```", options: .backwards) {
                value = String(value[..<fence.lowerBound])
            }
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Payloads

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ChatRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
}

private struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }
        let message: Message
    }
    let choices: [Choice]
}

private struct WhisperVerboseResponse: Decodable {
    struct Segment: Decodable {
        let start: Double
        let end: Double
        let text: String
    }
    let text: String?
    let segments: [Segment]?
}

private struct WhisperJSONResponse: Decodable {
    let text: String?
}

private struct APIErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String?
    }
    let error: APIError?
}

private struct TranslationInput: Encodable {
    let id: String
    let start: Double
    let end: Double
    let speaker: String
    let text: String
}

private struct TranslationEnvelope: Decodable {
    struct Item: Decodable {
        let id: String
        let text: String
    }
    let segments: [Item]
}

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }

    mutating func appendMultipart(boundary: String, name: String, value: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        appendString("\(value)\r\n")
    }

    mutating func appendFile(
        boundary: String,
        name: String,
        fileName: String,
        mimeType: String,
        fileData: Data
    ) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n")
        appendString("Content-Type: \(mimeType)\r\n\r\n")
        append(fileData)
        appendString("\r\n")
    }
}
