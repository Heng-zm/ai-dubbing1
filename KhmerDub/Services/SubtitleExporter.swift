import Foundation

enum SubtitleExporter {
    static func makeSRT(segments: [DubSegment]) -> String {
        let usable = segments
            .filter { $0.isIncluded && $0.isTranslated && $0.end > $0.start }
            .sorted { $0.start < $1.start }
        guard !usable.isEmpty else { return "" }
        var blocks: [String] = []
        blocks.reserveCapacity(usable.count)
        for (index, segment) in usable.enumerated() {
            let text = segment.translatedText
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .trimmed
            let block = """
            \(index + 1)
            \(timecode(segment.start)) --> \(timecode(segment.end))
            \(text)
            """
            blocks.append(block)
        }
        return blocks.joined(separator: "\n\n") + "\n"
    }

    static func write(project: DubProject, to url: URL) throws {
        let content = makeSRT(segments: project.segments)
        guard !content.isEmpty else { throw ExportError.noTranslatedText }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw ExportError.subtitleFailed
        }
    }

    static func timecode(_ seconds: Double) -> String {
        let safe = seconds.isFinite ? max(0, seconds) : 0
        let totalMilliseconds = Int((safe * 1_000).rounded())
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds % 3_600_000) / 60_000
        let secs = (totalMilliseconds % 60_000) / 1_000
        let millis = totalMilliseconds % 1_000
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, millis)
    }
}

enum SubtitleImporter {
    static func parse(
        text: String,
        defaultVoice: VoiceChoice = .sreymom,
        rate: Double = 1.0,
        pitch: Double = 1.0,
        speaker: String = "Speaker 1"
    ) -> [DubSegment] {
        var cleaned = text
        if cleaned.hasPrefix("\u{FEFF}") {
            cleaned.removeFirst()
        }
        cleaned = cleaned
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let rawBlocks = cleaned.components(separatedBy: "\n\n")
        var segments: [DubSegment] = []

        for rawBlock in rawBlocks {
            let lines = rawBlock
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !lines.isEmpty else { continue }

            var timecodeLine: String?
            var textLinesStartIndex = 0

            if lines[0].contains("-->") {
                timecodeLine = lines[0]
                textLinesStartIndex = 1
            } else if lines.count >= 2 && lines[1].contains("-->") {
                timecodeLine = lines[1]
                textLinesStartIndex = 2
            }

            guard let tcLine = timecodeLine else { continue }
            let parts = tcLine.components(separatedBy: "-->")
            guard parts.count == 2 else { continue }

            guard let start = parseTimecode(parts[0].trimmingCharacters(in: .whitespacesAndNewlines)),
                  let end = parseTimecode(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)),
                  end > start else { continue }

            let dialogueLines = lines[textLinesStartIndex...]
            let dialogueText = dialogueLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !dialogueText.isEmpty else { continue }

            let isKhmer = dialogueText.unicodeScalars.contains { $0.value >= 0x1780 && $0.value <= 0x17FF }

            let segment = DubSegment(
                start: start,
                end: end,
                speaker: speaker,
                originalText: isKhmer ? "" : dialogueText,
                translatedText: isKhmer ? dialogueText : "",
                voice: defaultVoice,
                rate: rate,
                pitch: pitch,
                isIncluded: true
            )
            segments.append(segment)
        }
        return segments.sorted { $0.start < $1.start }
    }

    static func parseTimecode(_ timecode: String) -> Double? {
        let cleaned = timecode
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = cleaned.components(separatedBy: ":")
        guard parts.count == 2 || parts.count == 3 else { return nil }

        if parts.count == 3 {
            guard let hours = Double(parts[0]),
                  let minutes = Double(parts[1]),
                  let seconds = Double(parts[2]) else { return nil }
            return hours * 3600.0 + minutes * 60.0 + seconds
        } else {
            guard let minutes = Double(parts[0]),
                  let seconds = Double(parts[1]) else { return nil }
            return minutes * 60.0 + seconds
        }
    }

    static func load(
        from url: URL,
        defaultVoice: VoiceChoice = .sreymom,
        rate: Double = 1.0,
        pitch: Double = 1.0,
        speaker: String = "Speaker 1"
    ) throws -> [DubSegment] {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }
        let data = try Data(contentsOf: url)
        let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        return parse(text: content, defaultVoice: defaultVoice, rate: rate, pitch: pitch, speaker: speaker)
    }
}
