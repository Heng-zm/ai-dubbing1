import Foundation

enum SourceLanguage: String, CaseIterable, Identifiable, Codable {
    case auto
    case khmer
    case english
    case thai
    case vietnamese
    case chinese
    case japanese
    case korean
    case french
    case spanish

    var id: String { rawValue }

    var code: String? {
        switch self {
        case .auto: return nil
        case .khmer: return "km"
        case .english: return "en"
        case .thai: return "th"
        case .vietnamese: return "vi"
        case .chinese: return "zh"
        case .japanese: return "ja"
        case .korean: return "ko"
        case .french: return "fr"
        case .spanish: return "es"
        }
    }

    var localizationKey: String { "source.\(rawValue)" }
}

enum VoiceChoice: String, CaseIterable, Identifiable, Codable {
    case sreymom
    case piseth
    case system

    var id: String { rawValue }

    var azureName: String? {
        switch self {
        case .sreymom: return "km-KH-SreymomNeural"
        case .piseth: return "km-KH-PisethNeural"
        case .system: return nil
        }
    }

    var isAzure: Bool { azureName != nil }

    var displayName: String {
        switch self {
        case .sreymom: return "Sreymom"
        case .piseth: return "Piseth"
        case .system: return "Apple"
        }
    }

    var genderKey: String {
        switch self {
        case .sreymom: return "voice.female"
        case .piseth: return "voice.male"
        case .system: return "voice.system"
        }
    }

    var symbol: String {
        switch self {
        case .sreymom: return "person.crop.circle.badge.checkmark"
        case .piseth: return "person.crop.circle"
        case .system: return "apple.logo"
        }
    }
}

struct GlossaryEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var term: String
    var translation: String
    var note: String = ""
    var createdAt: Date = Date()
}

struct DubSegment: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var start: Double
    var end: Double
    var speaker: String
    var originalText: String
    var translatedText: String
    var voice: VoiceChoice
    var rate: Double
    var pitch: Double
    var isIncluded: Bool = true

    var duration: Double {
        max(0, end - start)
    }

    var isTranslated: Bool {
        !translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isEmpty: Bool {
        originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var khmerCharacterCount: Int {
        translatedText.count
    }

    static func blank(
        start: Double,
        end: Double,
        speaker: String,
        voice: VoiceChoice,
        rate: Double,
        pitch: Double
    ) -> DubSegment {
        DubSegment(
            start: max(0, start),
            end: max(start + 0.5, end),
            speaker: speaker,
            originalText: "",
            translatedText: "",
            voice: voice,
            rate: rate,
            pitch: pitch
        )
    }
}

struct ExportRecord: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var fileName: String
    var kind: ExportKind
    var createdAt: Date
    var duration: Double
    var fileSize: Int64

    var displayName: String { fileName }
}

enum ProjectStage: String, CaseIterable, Identifiable, Codable {
    case draft
    case transcribed
    case translated
    case exported

    var id: String { rawValue }
    var localizationKey: String { "stage.\(rawValue)" }

    var order: Int {
        switch self {
        case .draft: return 0
        case .transcribed: return 1
        case .translated: return 2
        case .exported: return 3
        }
    }

    var symbol: String {
        switch self {
        case .draft: return "square.and.pencil"
        case .transcribed: return "text.bubble"
        case .translated: return "character.book.closed"
        case .exported: return "checkmark.seal.fill"
        }
    }
}

struct DubProject: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var sourceLanguage: SourceLanguage = .auto
    var targetLanguage: String = "km-KH"
    var mediaFileName: String?
    var thumbnailFileName: String?
    var duration: Double = 0
    var hasVideo: Bool = false
    var hasAudio: Bool = false
    var waveform: [Double] = []
    var segments: [DubSegment] = []
    var stage: ProjectStage = .draft
    var mode: DubMode = .replace
    var originalVolume: Double = 0.18
    var dubVolume: Double = 1.0
    var style: TranslationStyle = .natural
    var defaultVoice: VoiceChoice = .sreymom
    var voiceRate: Double = 1.0
    var voicePitch: Double = 1.0
    var fitSpeech: Bool = true
    var normalizeVolume: Bool = false
    var includeSubtitles: Bool = true
    var export60FPS: Bool? = true
    var isDemo: Bool = false
    var notes: String = ""
    var exports: [ExportRecord] = []

    var is60FPS: Bool {
        get { export60FPS ?? true }
        set { export60FPS = newValue }
    }

    var hasMedia: Bool { mediaFileName != nil }
    var translatedCount: Int { segments.filter(\.isTranslated).count }
    var includedCount: Int { segments.filter(\.isIncluded).count }
    var hasTranslatedLines: Bool { segments.contains { $0.isIncluded && $0.isTranslated } }
    var hasSegments: Bool { !segments.isEmpty }

    var speechDuration: Double {
        segments.filter(\.isIncluded).reduce(0) { $0 + $1.duration }
    }

    var translatedCharacterCount: Int {
        segments.reduce(0) { $0 + $1.khmerCharacterCount }
    }

    var progress: Double {
        var value = 0.0
        if hasMedia { value += 0.1 }
        if !segments.isEmpty { value += 0.2 }
        if translatedCount > 0 {
            value += 0.25 * (Double(translatedCount) / Double(max(1, segments.count)))
        }
        if !exports.isEmpty { value += 0.2 }
        if stage == .exported { value += 0.05 }
        return min(1, value)
    }

    var latestExport: ExportRecord? {
        exports.sorted { $0.createdAt > $1.createdAt }.first
    }

    var safeTitle: String {
        Formatters.safeFileComponent(title)
    }

    mutating func touch() {
        updatedAt = Date()
    }

    mutating func recalculateStage() {
        if !exports.isEmpty {
            stage = .exported
        } else if translatedCount > 0 {
            stage = .translated
        } else if !segments.isEmpty {
            stage = .transcribed
        } else {
            stage = .draft
        }
    }

    /// A plain-English fallback used by tests and previews. The app itself builds
    /// localized demos through `DemoProjectFactory`.
    static func demo() -> DubProject {
        let now = Date()
        let texts: [(Double, Double, String, String)] = [
            (0.0, 4.6, "Welcome to KhmerDub, your AI dubbing studio for Khmer.", "សូមស្វាគមន៍មកកាន់ KhmerDub ដែលជាស្ទូឌីយោឌឹប AI សម្រាប់ភាសាខ្មែរ។"),
            (4.8, 10.0, "Import a video, transcribe it with AI, and translate it into natural Khmer.", "នាំចូលវីដេអូ ចម្លងសំឡេងជាអក្សរដោយ AI ហើយបកប្រែជាភាសាខ្មែរធម្មជាតិ។"),
            (10.2, 14.8, "Choose a Khmer voice and export a video that is ready to share.", "ជ្រើសរើសសំឡេងខ្មែរ ហើយនាំចេញវីដេអូដែលអាចចែករំលែកបាន។"),
            (15.0, 19.6, "Every line is editable, so you stay in control of the Khmer script.", "រាល់បន្ទាត់អាចកែបាន ដូច្នេះអ្នកនៅតែគ្រប់គ្រងអត្ថបទខ្មែរបាន។"),
            (19.8, 24.0, "Review, preview, and export. Your Khmer voice is ready.", "ពិនិត្យ ស្តាប់ជាមុន និងនាំចេញ។ សំឡេងខ្មែររបស់អ្នករួចរាល់ហើយ។")
        ]
        let segments = texts.enumerated().map { index, item in
            DubSegment(
                start: item.0,
                end: item.1,
                speaker: index == texts.count - 1 ? "Narrator" : "Presenter",
                originalText: item.2,
                translatedText: item.3,
                voice: index == texts.count - 1 ? .piseth : .sreymom,
                rate: 1.0,
                pitch: 1.0
            )
        }
        return DubProject(
            title: "Welcome to KhmerDub",
            createdAt: now,
            updatedAt: now,
            sourceLanguage: .english,
            duration: 24,
            hasVideo: false,
            hasAudio: false,
            waveform: WaveformFallback.demo(count: 84),
            segments: segments,
            stage: .translated,
            mode: .replace,
            defaultVoice: .sreymom,
            isDemo: true,
            notes: "A short demo script. Import your own media to make a full dub."
        )
    }
}

enum WaveformFallback {
    static func demo(count: Int) -> [Double] {
        (0..<count).map { index in
            let wave = sin(Double(index) * 0.42) * 0.22
            let wave2 = sin(Double(index) * 0.17 + 1.3) * 0.18
            let envelope = 0.45 + 0.4 * sin(Double(index) / Double(max(1, count)) * .pi)
            return max(0.12, min(1, envelope + wave + wave2))
        }
    }

    static func stable(seed: String, count: Int) -> [Double] {
        var value: UInt64 = 1469598103934665603
        for scalar in seed.unicodeScalars {
            value ^= UInt64(scalar.value)
            value = value &* 1099511628211
        }
        return (0..<max(0, count)).map { index in
            value = value &* 6364136223846793005 &+ 1442695040888963407
            let unit = Double((value >> 33) & 0xFFFF) / Double(0xFFFF)
            let wave = 0.22 + unit * 0.62
            let pulse = sin(Double(index) * 0.35) * 0.08
            return max(0.1, min(1, wave + pulse))
        }
    }
}
