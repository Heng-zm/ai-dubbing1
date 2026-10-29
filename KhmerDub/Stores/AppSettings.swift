import Foundation

@MainActor
final class AppSettings: ObservableObject {
    private enum Keys {
        static let language = "settings.language"
        static let appearance = "settings.appearance"
        static let aiBaseURL = "settings.ai.baseURL"
        static let chatModel = "settings.ai.chatModel"
        static let transcriptionModel = "settings.ai.transcriptionModel"
        static let azureRegion = "settings.azure.region"
        static let azureVoice = "settings.azure.voice"
        static let appleVoice = "settings.apple.voice"
        static let defaultStyle = "settings.default.style"
        static let defaultMode = "settings.default.mode"
        static let defaultFit = "settings.default.fit"
        static let glossary = "settings.glossary"
        static let onboarding = "settings.onboarding.completed"
    }

    private let defaults: UserDefaults

    @Published var appLanguage: AppLanguage {
        didSet { defaults.set(appLanguage.rawValue, forKey: Keys.language) }
    }

    @Published var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    @Published var aiBaseURL: String {
        didSet { defaults.set(aiBaseURL, forKey: Keys.aiBaseURL) }
    }

    @Published var chatModel: String {
        didSet { defaults.set(chatModel, forKey: Keys.chatModel) }
    }

    @Published var transcriptionModel: String {
        didSet { defaults.set(transcriptionModel, forKey: Keys.transcriptionModel) }
    }

    @Published var azureRegion: String {
        didSet { defaults.set(azureRegion, forKey: Keys.azureRegion) }
    }

    @Published var azureVoice: String {
        didSet { defaults.set(azureVoice, forKey: Keys.azureVoice) }
    }

    @Published var appleVoiceIdentifier: String {
        didSet { defaults.set(appleVoiceIdentifier, forKey: Keys.appleVoice) }
    }

    @Published var defaultStyle: TranslationStyle {
        didSet { defaults.set(defaultStyle.rawValue, forKey: Keys.defaultStyle) }
    }

    @Published var defaultMode: DubMode {
        didSet { defaults.set(defaultMode.rawValue, forKey: Keys.defaultMode) }
    }

    @Published var defaultFitSpeech: Bool {
        didSet { defaults.set(defaultFitSpeech, forKey: Keys.defaultFit) }
    }

    @Published var glossary: [GlossaryEntry] {
        didSet {
            if let data = try? JSONEncoder().encode(glossary) {
                defaults.set(data, forKey: Keys.glossary)
            }
        }
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.onboarding) }
    }

    @Published private(set) var hasOpenAIKey: Bool
    @Published private(set) var hasAzureKey: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedLanguage = defaults.string(forKey: Keys.language).flatMap(AppLanguage.init(rawValue:))
        self.appLanguage = savedLanguage ?? .deviceDefault
        self.appearance = defaults.string(forKey: Keys.appearance)
            .flatMap(AppAppearance.init(rawValue:)) ?? .system
        self.aiBaseURL = defaults.string(forKey: Keys.aiBaseURL) ?? "https://api.openai.com/v1"
        self.chatModel = defaults.string(forKey: Keys.chatModel) ?? "gpt-4o-mini"
        self.transcriptionModel = defaults.string(forKey: Keys.transcriptionModel) ?? "whisper-1"
        self.azureRegion = defaults.string(forKey: Keys.azureRegion) ?? "southeastasia"
        self.azureVoice = defaults.string(forKey: Keys.azureVoice) ?? "km-KH-SreymomNeural"
        self.appleVoiceIdentifier = defaults.string(forKey: Keys.appleVoice) ?? ""
        self.defaultStyle = defaults.string(forKey: Keys.defaultStyle)
            .flatMap(TranslationStyle.init(rawValue:)) ?? .natural
        self.defaultMode = defaults.string(forKey: Keys.defaultMode)
            .flatMap(DubMode.init(rawValue:)) ?? .replace
        self.defaultFitSpeech = defaults.object(forKey: Keys.defaultFit) as? Bool ?? true
        if
            let data = defaults.data(forKey: Keys.glossary),
            let entries = try? JSONDecoder().decode([GlossaryEntry].self, from: data)
        {
            self.glossary = entries
        } else {
            self.glossary = []
        }
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarding)
        self.hasOpenAIKey = KeychainStore.hasValue(.openAIAPIKey)
        self.hasAzureKey = KeychainStore.hasValue(.azureSpeechKey)
    }

    var openAIKey: String? {
        KeychainStore.read(.openAIAPIKey)?.nonEmpty
    }

    var azureKey: String? {
        KeychainStore.read(.azureSpeechKey)?.nonEmpty
    }

    var aiConfiguration: OpenAIConfiguration? {
        let base = aiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let chat = chatModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let transcription = transcriptionModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let key = openAIKey,
            let url = URL(string: base),
            let scheme = url.scheme?.lowercased(),
            scheme == "https" || scheme == "http",
            url.host?.isEmpty == false,
            !chat.isEmpty,
            !transcription.isEmpty
        else { return nil }
        return OpenAIConfiguration(
            baseURL: url,
            apiKey: key,
            chatModel: chat,
            transcriptionModel: transcription
        )
    }

    var azureConfiguration: AzureSpeechConfiguration? {
        guard let key = azureKey else { return nil }
        let region = azureRegion.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let voice = azureVoice.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !region.isEmpty, !voice.isEmpty, AzureSpeechService.isValidRegion(region) else {
            return nil
        }
        return AzureSpeechConfiguration(
            apiKey: key,
            region: region,
            voiceName: voice
        )
    }

    func saveOpenAIKey(_ value: String) throws {
        try KeychainStore.save(value, for: .openAIAPIKey)
        hasOpenAIKey = KeychainStore.hasValue(.openAIAPIKey)
    }

    func removeOpenAIKey() {
        KeychainStore.delete(.openAIAPIKey)
        hasOpenAIKey = false
    }

    func saveAzureKey(_ value: String) throws {
        try KeychainStore.save(value, for: .azureSpeechKey)
        hasAzureKey = KeychainStore.hasValue(.azureSpeechKey)
    }

    func removeAzureKey() {
        KeychainStore.delete(.azureSpeechKey)
        hasAzureKey = false
    }

    func refreshKeyStatus() {
        hasOpenAIKey = KeychainStore.hasValue(.openAIAPIKey)
        hasAzureKey = KeychainStore.hasValue(.azureSpeechKey)
    }

    func applyOpenAIPreset() {
        aiBaseURL = "https://api.openai.com/v1"
        chatModel = "gpt-4o-mini"
        transcriptionModel = "whisper-1"
    }

    func applyGroqPreset() {
        aiBaseURL = "https://api.groq.com/openai/v1"
        chatModel = "llama-3.3-70b-versatile"
        transcriptionModel = "whisper-large-v3"
    }

    func addGlossaryEntry(_ entry: GlossaryEntry) {
        glossary.append(entry)
    }

    func updateGlossaryEntry(_ entry: GlossaryEntry) {
        guard let index = glossary.firstIndex(where: { $0.id == entry.id }) else { return }
        glossary[index] = entry
    }

    func deleteGlossaryEntry(id: UUID) {
        glossary.removeAll { $0.id == id }
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    /// Returns `true` when `value` is a syntactically valid HTTP/HTTPS URL
    /// with a non-empty host. Used by the UI to validate the AI base URL field.
    static func isValidBaseURL(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = url.host, !host.isEmpty
        else { return false }
        return true
    }
}

struct OpenAIConfiguration {
    let baseURL: URL
    let apiKey: String
    let chatModel: String
    let transcriptionModel: String

    var normalizedBaseURL: URL {
        var value = baseURL.absoluteString
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return URL(string: value) ?? baseURL
    }
}

struct AzureSpeechConfiguration {
    let apiKey: String
    let region: String
    let voiceName: String

    var endpoint: URL? {
        URL(string: "https://\(region).tts.speech.microsoft.com/cognitiveservices/v1")
    }
}
