import Foundation

@MainActor
enum DemoProjectFactory {
    static func make(localization: Localization) -> DubProject {
        let now = Date()
        let content: [(start: Double, end: Double, original: String, khmer: String)] = [
            (0.0, 4.6, localization.t("demo.original1"), localization.t("demo.khmer1")),
            (4.8, 10.0, localization.t("demo.original2"), localization.t("demo.khmer2")),
            (10.2, 14.8, localization.t("demo.original3"), localization.t("demo.khmer3")),
            (15.0, 19.6, localization.t("demo.original4"), localization.t("demo.khmer4")),
            (19.8, 24.0, localization.t("demo.original5"), localization.t("demo.khmer5"))
        ]
        let segments = content.enumerated().map { index, line in
            DubSegment(
                start: line.start,
                end: line.end,
                speaker: index == content.count - 1 ? "Narrator" : "Presenter",
                originalText: line.original,
                translatedText: line.khmer,
                voice: index == content.count - 1 ? .piseth : .sreymom,
                rate: 1.0,
                pitch: 1.0
            )
        }
        return DubProject(
            title: localization.t("demo.title"),
            createdAt: now,
            updatedAt: now,
            sourceLanguage: .english,
            duration: 24,
            hasVideo: false,
            hasAudio: false,
            waveform: WaveformFallback.demo(count: 96),
            segments: segments,
            stage: .translated,
            mode: .replace,
            defaultVoice: .sreymom,
            isDemo: true,
            notes: localization.t("demo.notes")
        )
    }
}
