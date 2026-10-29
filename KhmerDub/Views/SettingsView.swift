import AVFAudio
import AVFoundation
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var loc: Localization
    @EnvironmentObject private var store: ProjectStore

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                    .ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        engineSection
                        generalSection
                        dataSection
                        aboutSection
                        footer
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 30)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        HStack(spacing: 13) {
            AppLogoMark(size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(loc.t("settings.title"))
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(loc.t("settings.subtitle"))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer()
        }
    }

    private var engineSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionTitle(title: loc.t("settings.title.section.engine"))
            VStack(spacing: 14) {
                SettingsRow(
                    symbol: "sparkles",
                    title: loc.t("settings.ai"),
                    subtitle: settings.hasOpenAIKey
                        ? "\(settings.chatModel) · \(settings.transcriptionModel)"
                        : loc.t("common.notConfigured"),
                    tint: AppTheme.indigo
                ) {
                    AIEngineSettingsView()
                }
                DividerLine()
                SettingsRow(
                    symbol: "waveform",
                    title: loc.t("settings.voice"),
                    subtitle: settings.hasAzureKey
                        ? "\(loc.t("voice.azure")) · \(settings.azureRegion)"
                        : loc.t("settings.voice.subtitle"),
                    tint: AppTheme.gold
                ) {
                    VoiceSettingsView()
                }
            }
            .appCard()
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionTitle(title: loc.t("settings.title.section.general"))
            VStack(spacing: 14) {
                SettingsRow(
                    symbol: "slider.horizontal.3",
                    title: loc.t("settings.defaults"),
                    subtitle: loc.t(settings.defaultStyle.localizationKey),
                    tint: AppTheme.tealDeep
                ) {
                    StudioDefaultsView()
                }
                DividerLine()
                SettingsRow(
                    symbol: "circle.lefthalf.filled",
                    title: loc.t("settings.appearance"),
                    subtitle: loc.t("settings.appearance.\(settings.appearance.rawValue)"),
                    tint: AppTheme.goldDeep
                ) {
                    AppearanceSettingsView()
                }
                DividerLine()
                SettingsRow(
                    symbol: "globe",
                    title: loc.t("settings.language"),
                    subtitle: settings.appLanguage.nativeName,
                    tint: AppTheme.indigo
                ) {
                    LanguageSettingsView()
                }
                DividerLine()
                SettingsRow(
                    symbol: "character.book.closed",
                    title: loc.t("settings.glossary"),
                    subtitle: loc.f("translate.glossaryCount", settings.glossary.count),
                    tint: AppTheme.teal
                ) {
                    GlossaryView()
                }
            }
            .appCard()
        }
    }

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionTitle(title: loc.t("settings.data"))
            SettingsRow(
                symbol: "externaldrive.badge.checkmark",
                title: loc.t("settings.data"),
                subtitle: "\(store.projectCount) · \(Formatters.fileSize(store.totalStorageBytes))",
                tint: AppTheme.textSecondary
            ) {
                DataPrivacyView()
            }
            .appCard()
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionTitle(title: loc.t("settings.title.section.about"))
            SettingsRow(
                symbol: "info.circle",
                title: loc.t("settings.about"),
                subtitle: loc.t("settings.about.tagline"),
                tint: AppTheme.goldDeep
            ) {
                AboutView()
            }
            .appCard()
        }
    }

    private var footer: some View {
        VStack(spacing: 5) {
            Text("\(loc.t("app.name")) · \(loc.t("settings.about.version")) \(AppInfo.version)")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)
            Text(loc.t("app.madeFor"))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }
}

// MARK: - AI engine

struct AIEngineSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var loc: Localization

    @State private var keyInput = ""
    @State private var isTesting = false
    @State private var testMessage: String?
    @State private var testSucceeded = false
    @State private var keyMessage: String?

    private var validationMessage: String? {
        if !AppSettings.isValidBaseURL(settings.aiBaseURL) {
            return loc.t("error.invalidURL")
        }
        if settings.chatModel.trimmed.isEmpty || settings.transcriptionModel.trimmed.isEmpty {
            return loc.t("error.provider")
        }
        return nil
    }

    var body: some View {
        ZStack {
            ScreenBackground()
                .ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    keyCard
                    endpointCard
                    presetCard
                    testCard
                    Text(loc.t("settings.ai.security"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(AppTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 2)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle(loc.t("settings.ai"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var keyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardIconTitle(
                symbol: "key.horizontal.fill",
                title: loc.t("settings.ai.key"),
                subtitle: settings.hasOpenAIKey ? loc.t("settings.ai.connected") : loc.t("common.notConfigured"),
                tint: settings.hasOpenAIKey ? AppTheme.success : AppTheme.warning
            )
            SecureField(loc.t("settings.ai.keyPlaceholder"), text: $keyInput)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.password)
                .cardFieldStyle()
            HStack(spacing: 9) {
                Button {
                    saveKey()
                } label: {
                    Label(loc.t("settings.ai.saveKey"), systemImage: "lock.fill")
                }
                .buttonStyle(CompactButtonStyle(tint: AppTheme.goldDeep))
                .disabled(keyInput.trimmed.isEmpty)

                if settings.hasOpenAIKey {
                    Button(role: .destructive) {
                        settings.removeOpenAIKey()
                        keyInput = ""
                        keyMessage = loc.t("toast.keyRemoved")
                        testMessage = nil
                        Haptics.warning()
                    } label: {
                        Label(loc.t("settings.ai.removeKey"), systemImage: "trash")
                    }
                    .buttonStyle(CompactButtonStyle(tint: AppTheme.danger))
                }
            }
            if let keyMessage {
                InlineBanner(kind: .success, text: keyMessage)
            }
            Text(loc.t("settings.ai.keyNote"))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .appCard()
    }

    private var endpointCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardIconTitle(
                symbol: "network",
                title: loc.t("settings.ai.custom"),
                tint: AppTheme.indigo
            )
            field(title: loc.t("settings.ai.baseURL")) {
                TextField("https://api.openai.com/v1", text: $settings.aiBaseURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 13.5, weight: .medium, design: .monospaced))
                    .cardFieldStyle()
            }
            field(title: loc.t("settings.ai.chatModel")) {
                TextField("gpt-4o-mini", text: $settings.chatModel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 13.5, weight: .medium, design: .monospaced))
                    .cardFieldStyle()
            }
            field(title: loc.t("settings.ai.transcribeModel")) {
                TextField("whisper-1", text: $settings.transcriptionModel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 13.5, weight: .medium, design: .monospaced))
                    .cardFieldStyle()
            }
            if let validationMessage {
                InlineBanner(kind: .warning, text: validationMessage)
            }
        }
        .appCard()
    }

    private var presetCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            CardIconTitle(
                symbol: "bolt.fill",
                title: loc.t("settings.ai.preset"),
                tint: AppTheme.goldDeep
            )
            HStack(spacing: 9) {
                Button {
                    settings.applyOpenAIPreset()
                    keyMessage = nil
                    testMessage = nil
                    Haptics.selection()
                } label: {
                    Label(loc.t("settings.ai.openai"), systemImage: "circle.grid.2x2.fill")
                }
                .buttonStyle(CompactButtonStyle(tint: AppTheme.goldDeep))

                Button {
                    settings.applyGroqPreset()
                    keyMessage = nil
                    testMessage = nil
                    Haptics.selection()
                } label: {
                    Label(loc.t("settings.ai.groq"), systemImage: "bolt.fill")
                }
                .buttonStyle(CompactButtonStyle(tint: AppTheme.tealDeep))

                Spacer()
            }
        }
        .appCard()
    }

    private var testCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Button {
                testConnection()
            } label: {
                HStack(spacing: 8) {
                    if isTesting {
                        ProgressView()
                            .tint(Color(hex: 0x1A160D))
                    }
                    Text(loc.t(isTesting ? "settings.ai.testing" : "settings.ai.test"))
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(isTesting || validationMessage != nil || !settings.hasOpenAIKey)

            if let testMessage {
                InlineBanner(kind: testSucceeded ? .success : .error, text: testMessage)
            }
        }
        .appCard()
    }

    private func field<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
            content()
        }
    }

    private func saveKey() {
        let value = keyInput.trimmed
        guard !value.isEmpty else { return }
        do {
            try settings.saveOpenAIKey(value)
            keyInput = ""
            keyMessage = loc.t("settings.ai.keySaved")
            testMessage = nil
            Haptics.success()
        } catch {
            keyMessage = ErrorPresenter.message(for: error, localization: loc)
            Haptics.error()
        }
    }

    private func testConnection() {
        guard let configuration = settings.aiConfiguration else {
            testSucceeded = false
            testMessage = loc.t(settings.hasOpenAIKey ? "error.invalidURL" : "error.missingKey")
            return
        }
        isTesting = true
        testMessage = nil
        Task {
            do {
                try await OpenAIService(configuration: configuration).testConnection()
                testSucceeded = true
                testMessage = loc.t("settings.ai.connected")
                Haptics.success()
            } catch {
                testSucceeded = false
                testMessage = ErrorPresenter.message(for: error, localization: loc)
                Haptics.error()
            }
            isTesting = false
        }
    }
}

// MARK: - Voice

struct VoiceSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var loc: Localization

    @StateObject private var preview = SpeechPreviewPlayer()
    @State private var appleVoices: [AVSpeechSynthesisVoice] = []
    @State private var azureKeyInput = ""
    @State private var keyMessage: String?
    @State private var testMessage: String?

    private var regionValid: Bool {
        AzureSpeechService.isValidRegion(settings.azureRegion.trimmed.lowercased())
    }

    private var selectedAzureVoice: VoiceChoice {
        settings.azureVoice == "km-KH-PisethNeural" ? .piseth : .sreymom
    }

    var body: some View {
        ZStack {
            ScreenBackground()
                .ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    readinessCard
                    azureCard
                    appleCard
                    if let error = preview.errorMessage {
                        InlineBanner(kind: .warning, text: error)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle(loc.t("settings.voice"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            appleVoices = AppleTTSService.khmerVoices()
        }
        .onDisappear {
            preview.stop()
        }
    }

    private var readinessCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardIconTitle(
                symbol: "waveform.circle.fill",
                title: loc.t("voice.readiness"),
                subtitle: loc.t("voice.subtitle"),
                tint: AppTheme.goldDeep
            )
            HStack(spacing: 9) {
                statusPill(
                    title: loc.t("voice.azure"),
                    ready: settings.hasAzureKey && regionValid,
                    symbol: "cloud.fill"
                )
                statusPill(
                    title: loc.t("voice.system"),
                    ready: !appleVoices.isEmpty,
                    symbol: "apple.logo"
                )
            }
        }
        .appCard()
    }

    private func statusPill(title: String, ready: Bool, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
            Image(systemName: ready ? "checkmark.circle.fill" : "minus.circle")
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(ready ? AppTheme.tealDeep : AppTheme.textTertiary)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(
            Capsule(style: .continuous)
                .fill((ready ? AppTheme.teal : AppTheme.textTertiary).opacity(0.09))
        )
    }

    private var azureCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardIconTitle(
                symbol: "cloud.fill",
                title: loc.t("voice.azure"),
                subtitle: loc.t("voice.azureHint"),
                tint: AppTheme.goldDeep
            )
            SecureField(loc.t("settings.voice.azureKey"), text: $azureKeyInput)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.password)
                .cardFieldStyle()

            HStack(spacing: 9) {
                Button {
                    saveAzureKey()
                } label: {
                    Label(loc.t("settings.ai.saveKey"), systemImage: "lock.fill")
                }
                .buttonStyle(CompactButtonStyle(tint: AppTheme.goldDeep))
                .disabled(azureKeyInput.trimmed.isEmpty)

                if settings.hasAzureKey {
                    Button(role: .destructive) {
                        settings.removeAzureKey()
                        azureKeyInput = ""
                        keyMessage = loc.t("toast.keyRemoved")
                        testMessage = nil
                        Haptics.warning()
                    } label: {
                        Label(loc.t("settings.ai.removeKey"), systemImage: "trash")
                    }
                    .buttonStyle(CompactButtonStyle(tint: AppTheme.danger))
                }
            }

            if let keyMessage {
                InlineBanner(kind: .success, text: keyMessage)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(loc.t("settings.voice.region"))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                TextField("southeastasia", text: $settings.azureRegion)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 13.5, weight: .medium, design: .monospaced))
                    .cardFieldStyle()
            }

            if !regionValid {
                InlineBanner(kind: .warning, text: loc.t("error.azureRegion"))
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(loc.t("settings.voice.azureVoice"))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                Picker("", selection: $settings.azureVoice) {
                    ForEach(AzureVoiceOption.all) { option in
                        Text("\(option.name) · \(loc.t(option.genderKey))").tag(option.id)
                    }
                }
                .labelsHidden()
                .tint(AppTheme.goldDeep)
            }

            Button {
                testAzureVoice()
            } label: {
                Label(loc.t("settings.voice.test"), systemImage: "play.circle.fill")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(!settings.hasAzureKey || !regionValid)

            if let testMessage {
                InlineBanner(kind: .info, text: testMessage)
            }

            Text(loc.t("settings.voice.privacy"))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .appCard()
    }

    private var appleCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            CardIconTitle(
                symbol: "apple.logo",
                title: loc.t("settings.voice.appleVoices"),
                subtitle: loc.t("voice.appleNote"),
                tint: AppTheme.textSecondary
            )
            if appleVoices.isEmpty {
                InlineBanner(kind: .info, text: loc.t("settings.voice.noApple"))
                Text(loc.t("voice.installHint"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(AppTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(appleVoices.enumerated()), id: \.element.identifier) { index, voice in
                        Button {
                            settings.appleVoiceIdentifier = voice.identifier
                            Haptics.selection()
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: "apple.logo")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(voice.name)
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .foregroundStyle(AppTheme.textPrimary)
                                    Text(voice.language)
                                        .font(.system(size: 9.5, weight: .medium))
                                        .foregroundStyle(AppTheme.textTertiary)
                                }
                                Spacer()
                                Image(systemName: isSelectedAppleVoice(voice) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(isSelectedAppleVoice(voice) ? AppTheme.teal : AppTheme.textTertiary)
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        if index < appleVoices.count - 1 {
                            DividerLine()
                        }
                    }
                }
                Button {
                    testAppleVoice()
                } label: {
                    Label(loc.t("voice.test"), systemImage: "play.circle.fill")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .appCard()
    }

    private func isSelectedAppleVoice(_ voice: AVSpeechSynthesisVoice) -> Bool {
        if settings.appleVoiceIdentifier.isEmpty {
            return voice.identifier == appleVoices.first?.identifier
        }
        return settings.appleVoiceIdentifier == voice.identifier
    }

    private func saveAzureKey() {
        let value = azureKeyInput.trimmed
        guard !value.isEmpty else { return }
        do {
            try settings.saveAzureKey(value)
            azureKeyInput = ""
            keyMessage = loc.t("settings.ai.keySaved")
            testMessage = nil
            Haptics.success()
        } catch {
            keyMessage = ErrorPresenter.message(for: error, localization: loc)
            Haptics.error()
        }
    }

    private func testAzureVoice() {
        testMessage = loc.t("voice.playing")
        Task {
            await preview.preview(
                text: loc.t("voice.testPhrase"),
                voice: selectedAzureVoice,
                rate: 1,
                pitch: 1,
                settings: settings
            )
            if let error = preview.errorMessage {
                testMessage = error
            } else {
                testMessage = nil
            }
        }
    }

    private func testAppleVoice() {
        testMessage = loc.t("voice.playing")
        Task {
            await preview.preview(
                text: loc.t("voice.testPhrase"),
                voice: .system,
                rate: 1,
                pitch: 1,
                settings: settings
            )
            if let error = preview.errorMessage {
                testMessage = error
            } else {
                testMessage = nil
            }
        }
    }
}

// MARK: - Studio defaults

struct StudioDefaultsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var loc: Localization

    var body: some View {
        ZStack {
            ScreenBackground()
                .ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    styleCard
                    modeCard
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle(loc.t("settings.defaults"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var styleCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            CardIconTitle(
                symbol: "wand.and.stars",
                title: loc.t("settings.defaults.style"),
                tint: AppTheme.goldDeep
            )
            ForEach(TranslationStyle.allCases) { style in
                Button {
                    settings.defaultStyle = style
                    Haptics.selection()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: settings.defaultStyle == style ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(settings.defaultStyle == style ? AppTheme.goldDeep : AppTheme.textTertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc.t(style.localizationKey))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                            Text(style.promptDescription)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(AppTheme.textTertiary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
                if style != TranslationStyle.allCases.last {
                    DividerLine()
                }
            }
        }
        .appCard()
    }

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            CardIconTitle(
                symbol: "waveform.badge.plus",
                title: loc.t("settings.defaults.mode"),
                tint: AppTheme.tealDeep
            )
            ForEach(DubMode.allCases) { mode in
                Button {
                    settings.defaultMode = mode
                    Haptics.selection()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: mode.symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(settings.defaultMode == mode ? AppTheme.tealDeep : AppTheme.textTertiary)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc.t(mode.localizationKey))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                            Text(loc.t("mode.\(mode.rawValue).hint"))
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(AppTheme.textTertiary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: settings.defaultMode == mode ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(settings.defaultMode == mode ? AppTheme.teal : AppTheme.textTertiary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                if mode != DubMode.allCases.last {
                    DividerLine()
                }
            }
            Toggle(isOn: $settings.defaultFitSpeech) {
                Text(loc.t("settings.defaults.fit"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .tint(AppTheme.teal)
        }
        .appCard()
    }
}

// MARK: - Appearance

struct AppearanceSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var loc: Localization

    var body: some View {
        ZStack {
            ScreenBackground()
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(AppAppearance.allCases) { option in
                        Button {
                            settings.appearance = option
                            Haptics.selection()
                        } label: {
                            HStack(spacing: 12) {
                                IconCircle(
                                    systemName: symbol(for: option),
                                    tint: tint(for: option),
                                    size: 40
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(loc.t("settings.appearance.\(option.rawValue)"))
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(AppTheme.textPrimary)
                                    Text(loc.t("settings.appearance"))
                                        .font(.system(size: 10.5, weight: .medium))
                                        .foregroundStyle(AppTheme.textTertiary)
                                }
                                Spacer()
                                Image(systemName: settings.appearance == option ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(settings.appearance == option ? AppTheme.goldDeep : AppTheme.textTertiary)
                            }
                            .appCard(padding: 14)
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle(loc.t("settings.appearance"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func symbol(for appearance: AppAppearance) -> String {
        switch appearance {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    private func tint(for appearance: AppAppearance) -> Color {
        switch appearance {
        case .system: return AppTheme.indigo
        case .light: return AppTheme.goldDeep
        case .dark: return AppTheme.teal
        }
    }
}

// MARK: - Language

struct LanguageSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var loc: Localization

    var body: some View {
        ZStack {
            ScreenBackground()
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(AppLanguage.allCases) { language in
                        Button {
                            settings.appLanguage = language
                            loc.setLanguage(language)
                            Haptics.selection()
                        } label: {
                            HStack(spacing: 12) {
                                Text(language.flag)
                                    .font(.system(size: 26))
                                    .frame(width: 44, height: 44)
                                    .background(Circle().fill(AppTheme.surfaceMuted))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(language.nativeName)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(AppTheme.textPrimary)
                                    Text(loc.t(language == .english ? "settings.language.english" : "settings.language.khmer"))
                                        .font(.system(size: 10.5, weight: .medium))
                                        .foregroundStyle(AppTheme.textTertiary)
                                }
                                Spacer()
                                Image(systemName: settings.appLanguage == language ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(settings.appLanguage == language ? AppTheme.goldDeep : AppTheme.textTertiary)
                            }
                            .appCard(padding: 14)
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle(loc.t("settings.language"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Data & privacy

struct DataPrivacyView: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var loc: Localization
    @EnvironmentObject private var toasts: ToastCenter

    @State private var showClearExports = false
    @State private var showDeleteAll = false

    var body: some View {
        ZStack {
            ScreenBackground()
                .ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    storageCard
                    privacyCard
                    actionsCard
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle(loc.t("settings.data"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            Text(loc.t("settings.data.clearExports")),
            isPresented: $showClearExports
        ) {
            Button(role: .cancel) {} label: {
                Text(loc.t("common.cancel"))
            }
            Button(role: .destructive) {
                store.clearExports()
                toasts.show(loc.t("settings.data.cleared"))
                Haptics.success()
            } label: {
                Text(loc.t("common.clear"))
            }
        } message: {
            Text(loc.t("settings.data.confirm"))
        }
        .alert(
            Text(loc.t("settings.data.deleteAll")),
            isPresented: $showDeleteAll
        ) {
            Button(role: .cancel) {} label: {
                Text(loc.t("common.cancel"))
            }
            Button(role: .destructive) {
                store.clearAllProjects()
                AppFiles.cleanTemporaryFiles()
                toasts.show(loc.t("settings.data.deleted"))
                Haptics.success()
            } label: {
                Text(loc.t("common.delete"))
            }
        } message: {
            Text(loc.t("settings.data.confirm"))
        }
    }

    private var storageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardIconTitle(
                symbol: "externaldrive.fill",
                title: loc.t("settings.data.storage"),
                subtitle: Formatters.fileSize(store.totalStorageBytes),
                tint: AppTheme.tealDeep
            )
            HStack(spacing: 10) {
                StatTile(
                    value: "\(store.projectCount)",
                    label: loc.t("settings.data.projects"),
                    symbol: "rectangle.stack",
                    tint: AppTheme.gold
                )
                StatTile(
                    value: "\(store.exportCount)",
                    label: loc.t("settings.data.exports"),
                    symbol: "square.and.arrow.up",
                    tint: AppTheme.indigo
                )
            }
        }
        .appCard()
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardIconTitle(
                symbol: "lock.shield.fill",
                title: loc.t("privacy.title"),
                subtitle: loc.t("privacy.body"),
                tint: AppTheme.goldDeep
            )
            ForEach(privacyPoints, id: \.self) { point in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.teal)
                        .padding(.top, 2)
                    Text(point)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .appCard()
    }

    private var actionsCard: some View {
        VStack(spacing: 10) {
            Button {
                showClearExports = true
            } label: {
                Label(loc.t("settings.data.clearExports"), systemImage: "trash.slash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AppTheme.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(AppTheme.border, lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .disabled(store.exportCount == 0)
            .opacity(store.exportCount == 0 ? 0.5 : 1)

            Button {
                showDeleteAll = true
            } label: {
                Label(loc.t("settings.data.deleteAll"), systemImage: "trash")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppTheme.danger)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AppTheme.danger.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .disabled(store.projects.isEmpty)
            .opacity(store.projects.isEmpty ? 0.5 : 1)
        }
        .appCard()
    }

    private var privacyPoints: [String] {
        [
            loc.t("privacy.keychain"),
            loc.t("privacy.media"),
            loc.t("privacy.cloud"),
            loc.t("privacy.delete"),
            loc.t("privacy.noTracking")
        ]
    }
}

// MARK: - Brand

struct AppLogoMark: View {
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(AppTheme.goldGradient)
            Image(systemName: "character.book.closed.fill")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(Color(hex: 0x20180A))
            Circle()
                .fill(AppTheme.teal)
                .frame(width: size * 0.17, height: size * 0.17)
                .overlay(Circle().stroke(Color(hex: 0x20180A), lineWidth: size * 0.02))
                .offset(x: size * 0.3, y: -size * 0.3)
        }
        .frame(width: size, height: size)
        .shadow(color: AppTheme.gold.opacity(0.22), radius: size * 0.16, x: 0, y: size * 0.08)
    }
}

// MARK: - Glossary

struct GlossaryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var loc: Localization
    @EnvironmentObject private var toasts: ToastCenter

    @State private var showingAddSheet = false
    @State private var editingEntry: GlossaryEntry?
    @State private var searchText = ""

    private var filteredEntries: [GlossaryEntry] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty {
            return settings.glossary
        }
        return settings.glossary.filter { entry in
            entry.term.lowercased().contains(trimmed) ||
            entry.translation.lowercased().contains(trimmed) ||
            entry.note.lowercased().contains(trimmed)
        }
    }

    var body: some View {
        ZStack {
            ScreenBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard

                    if settings.glossary.isEmpty {
                        EmptyStateView(
                            symbol: "character.book.closed",
                            title: loc.t("glossary.empty.title"),
                            message: loc.t("glossary.empty.body"),
                            actionTitle: loc.t("glossary.add"),
                            action: { showingAddSheet = true }
                        )
                        .appCard()
                    } else {
                        searchBar
                        termsList
                    }

                    hintCard
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle(loc.t("glossary.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AppTheme.goldDeep)
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            GlossaryEditorSheet(entry: nil) { newEntry in
                settings.addGlossaryEntry(newEntry)
                toasts.show(loc.t("common.saved"))
                Haptics.success()
            }
            .environmentObject(loc)
        }
        .sheet(item: $editingEntry) { entry in
            GlossaryEditorSheet(entry: entry) { updatedEntry in
                settings.updateGlossaryEntry(updatedEntry)
                toasts.show(loc.t("common.saved"))
                Haptics.success()
            }
            .environmentObject(loc)
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.teal.opacity(0.15))
                        .frame(width: 38, height: 38)
                    Image(systemName: "character.book.closed")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppTheme.teal)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc.t("glossary.title"))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(loc.f("translate.glossaryCount", settings.glossary.count))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer()
                Button {
                    showingAddSheet = true
                } label: {
                    Label(loc.t("glossary.add"), systemImage: "plus")
                        .font(.system(size: 12, weight: .bold))
                }
                .buttonStyle(CompactButtonStyle(tint: AppTheme.teal))
            }

            Text(loc.t("glossary.subtitle"))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
                .lineSpacing(2)
        }
        .appCard()
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)
            TextField(loc.t("common.search"), text: $searchText)
                .font(.system(size: 13.5))
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
        )
    }

    private var termsList: some View {
        VStack(spacing: 10) {
            ForEach(filteredEntries) { entry in
                termRow(entry)
            }
        }
    }

    private func termRow(_ entry: GlossaryEntry) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.term)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(entry.translation)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.goldDeep)
                if !entry.note.isEmpty {
                    Text(entry.note)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            Spacer()
            Button {
                editingEntry = entry
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(8)
            }
            .buttonStyle(.plain)

            Button {
                withAnimation {
                    settings.deleteGlossaryEntry(id: entry.id)
                    toasts.show(loc.t("glossary.delete"))
                    Haptics.selection()
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.danger)
                    .padding(8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
        )
    }

    private var hintCard: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "info.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.teal)
            Text(loc.t("glossary.hint"))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
                .lineSpacing(2)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.teal.opacity(0.08))
        )
    }
}

// MARK: - Glossary Editor Sheet

struct GlossaryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var loc: Localization

    let initialEntry: GlossaryEntry?
    let onSave: (GlossaryEntry) -> Void

    @State private var term: String
    @State private var translation: String
    @State private var note: String
    @State private var errorMessage: String?

    init(entry: GlossaryEntry?, onSave: @escaping (GlossaryEntry) -> Void) {
        self.initialEntry = entry
        self.onSave = onSave
        _term = State(initialValue: entry?.term ?? "")
        _translation = State(initialValue: entry?.translation ?? "")
        _note = State(initialValue: entry?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let errorMessage {
                            InlineBanner(kind: .warning, text: errorMessage)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            fieldBlock(
                                title: loc.t("glossary.term"),
                                placeholder: loc.t("glossary.placeholderTerm"),
                                text: $term
                            )

                            DividerLine()

                            fieldBlock(
                                title: loc.t("glossary.translation"),
                                placeholder: loc.t("glossary.placeholderTranslation"),
                                text: $translation
                            )

                            DividerLine()

                            fieldBlock(
                                title: loc.t("glossary.note"),
                                placeholder: loc.t("glossary.note"),
                                text: $note
                            )
                        }
                        .appCard()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle(initialEntry == nil ? loc.t("glossary.add") : loc.t("glossary.save"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc.t("common.cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc.t("common.save")) {
                        save()
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppTheme.goldDeep)
                }
            }
        }
    }

    private func fieldBlock(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppTheme.textSecondary)
            TextField(placeholder, text: text)
                .font(.system(size: 14))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.surfaceElevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(AppTheme.border, lineWidth: 1)
                        )
                )
        }
    }

    private func save() {
        let cleanTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTerm.isEmpty else {
            errorMessage = loc.t("glossary.termRequired")
            Haptics.warning()
            return
        }
        let cleanTranslation = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        var entry = initialEntry ?? GlossaryEntry(term: cleanTerm, translation: cleanTranslation)
        entry.term = cleanTerm
        entry.translation = cleanTranslation
        entry.note = cleanNote

        onSave(entry)
        dismiss()
    }
}

// MARK: - About View

struct AboutView: View {
    @EnvironmentObject private var loc: Localization

    var body: some View {
        ZStack {
            ScreenBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    heroSection

                    VStack(alignment: .leading, spacing: 14) {
                        aboutCard
                        creditsCard
                        privacyCard
                        disclaimerCard
                        linksCard
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle(loc.t("settings.about"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var heroSection: some View {
        VStack(spacing: 12) {
            AppLogoMark(size: 84)
                .padding(.top, 8)

            VStack(spacing: 4) {
                Text(loc.t("app.name"))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("\(loc.t("settings.about.version")) \(AppInfo.version)")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.goldDeep)

                Text(loc.t("settings.about.tagline"))
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(loc.t("settings.about.made"), systemImage: "heart.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppTheme.goldDeep)
            Text(loc.t("app.tagline"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
                .lineSpacing(3)
        }
        .appCard()
    }

    private var creditsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Credits", systemImage: "sparkles")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppTheme.teal)
            Text(loc.t("settings.about.credits"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
                .lineSpacing(3)
        }
        .appCard()
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(loc.t("settings.about.privacy"), systemImage: "lock.shield.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppTheme.indigo)
            Text(loc.t("settings.about.noTracking"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
                .lineSpacing(3)
        }
        .appCard()
    }

    private var disclaimerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Disclaimer", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppTheme.warning)
            Text(loc.t("settings.about.disclaimer"))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
                .lineSpacing(3)
        }
        .appCard()
    }

    private var linksCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let repoURL = URL(string: "https://github.com/Heng-zm/ai-dubbing1") {
                Link(destination: repoURL) {
                    HStack {
                        Label(loc.t("settings.about.licenses"), systemImage: "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                }
            }

            DividerLine()

            if let repoURL = URL(string: "https://github.com/Heng-zm/ai-dubbing1") {
                Link(destination: repoURL) {
                    HStack {
                        Label(loc.t("settings.about.website"), systemImage: "questionmark.circle")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                }
            }
        }
        .appCard()
    }
}
