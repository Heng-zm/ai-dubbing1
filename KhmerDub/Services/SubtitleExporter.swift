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
