import SwiftUI

struct ProjectSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var loc: Localization
    @EnvironmentObject private var toasts: ToastCenter

    @ObservedObject var model: StudioModel

    @State private var title = ""
    @State private var notes = ""
    @State private var sourceLanguage: SourceLanguage = .auto
    @State private var style: TranslationStyle = .natural
    @State private var mode: DubMode = .replace
    @State private var fitSpeech = true
    @State private var normalize = false
    @State private var includeSubtitles = true
    @State private var originalVolume = 0.18
    @State private var dubVolume = 1.0
    @State private var rate = 1.0
    @State private var pitch = 1.0
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                    .ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        SheetHeader(
                            title: loc.t("studio.settings"),
                            subtitle: loc.t("settings.subtitle"),
                            onClose: { dismiss() }
                        )
                        detailsCard
                        languageCard
                        mixCard
                        timingCard
                        if let errorMessage {
                            InlineBanner(kind: .error, text: errorMessage)
                        }
                        Button {
                            save()
                        } label: {
                            Label(loc.t("common.saveChanges"), systemImage: "checkmark.circle.fill")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 32)
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear(perform: load)
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardIconTitle(
                symbol: "text.alignleft",
                title: loc.t("studio.projectTitle"),
                tint: AppTheme.goldDeep
            )
            TextField(loc.t("import.titlePlaceholder"), text: $title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .textInputAutocapitalization(.sentences)
                .cardFieldStyle()

            Text(loc.t("studio.notes"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
            ZStack(alignment: .topLeading) {
                if notes.isEmpty {
                    Text(loc.t("studio.notesPlaceholder"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.textTertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 13)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $notes)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 88)
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.surfaceMuted)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AppTheme.border, lineWidth: 1)
                    )
            )
        }
        .appCard()
    }

    private var languageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardIconTitle(
                symbol: "globe",
                title: loc.t("studio.languagePair"),
                tint: AppTheme.indigo
            )
            HStack {
                Text(loc.t("studio.source"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Picker("", selection: $sourceLanguage) {
                    ForEach(SourceLanguage.allCases) { item in
                        Text(loc.t(item.localizationKey)).tag(item)
                    }
                }
                .labelsHidden()
                .tint(AppTheme.goldDeep)
            }
            HStack {
                Text(loc.t("translate.style"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Picker("", selection: $style) {
                    ForEach(TranslationStyle.allCases) { item in
                        Text(loc.t(item.localizationKey)).tag(item)
                    }
                }
                .labelsHidden()
                .tint(AppTheme.goldDeep)
            }
        }
        .appCard()
    }

    private var mixCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            CardIconTitle(
                symbol: "slider.horizontal.3",
                title: loc.t("voice.mix"),
                subtitle: loc.t("voice.mode"),
                tint: AppTheme.tealDeep
            )
            Picker("", selection: $mode) {
                ForEach(DubMode.allCases) { item in
                    Text(loc.t(item.localizationKey)).tag(item)
                }
            }
            .labelsHidden()
            .tint(AppTheme.goldDeep)
            Text(loc.t("mode.\(mode.rawValue).hint"))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if mode != .replace {
                volumeRow(title: loc.t("voice.originalVolume"), value: $originalVolume)
            }
            volumeRow(title: loc.t("voice.dubVolume"), value: $dubVolume)

            Toggle(isOn: $fitSpeech) {
                Text(loc.t("voice.fit"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .tint(AppTheme.teal)

            Toggle(isOn: $normalize) {
                Text(loc.t("export.normalize"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .tint(AppTheme.teal)

            Toggle(isOn: $includeSubtitles) {
                Text(loc.t("export.subtitles"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .tint(AppTheme.teal)
        }
        .appCard()
    }

    private var timingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardIconTitle(
                symbol: "timer",
                title: loc.t("voice.settings"),
                tint: AppTheme.gold
            )
            VoiceSliderRow(
                title: loc.t("voice.rate"),
                hint: loc.t("segment.rateHint"),
                value: $rate,
                range: 0.5...2.0
            )
            VoiceSliderRow(
                title: loc.t("voice.pitch"),
                hint: loc.t("segment.pitchHint"),
                value: $pitch,
                range: 0.5...2.0
            )
        }
        .appCard()
    }

    private func volumeRow(title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text("\(Int((value.wrappedValue * 100).rounded()))%")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.goldDeep)
                    .monospacedDigit()
            }
            Slider(value: value, in: 0...1)
                .tint(AppTheme.gold)
        }
    }

    private func load() {
        let project = model.project
        title = project.title
        notes = project.notes
        sourceLanguage = project.sourceLanguage
        style = project.style
        mode = project.mode
        fitSpeech = project.fitSpeech
        normalize = project.normalizeVolume
        includeSubtitles = project.includeSubtitles
        originalVolume = project.originalVolume
        dubVolume = project.dubVolume
        rate = project.voiceRate
        pitch = project.voicePitch
    }

    private func save() {
        let cleanTitle = title.trimmed
        guard !cleanTitle.isEmpty else {
            errorMessage = loc.t("import.titleRequired")
            Haptics.warning()
            return
        }
        model.project.title = cleanTitle
        model.project.notes = notes
        model.project.sourceLanguage = sourceLanguage
        model.project.style = style
        model.project.mode = mode
        model.project.fitSpeech = fitSpeech
        model.project.normalizeVolume = normalize
        model.project.includeSubtitles = includeSubtitles
        model.project.originalVolume = originalVolume.clamped(to: 0...1)
        model.project.dubVolume = dubVolume.clamped(to: 0...1)
        model.project.voiceRate = rate.clamped(to: 0.5...2.0)
        model.project.voicePitch = pitch.clamped(to: 0.5...2.0)
        model.project.touch()
        model.flush()
        toasts.show(loc.t("toast.saved"))
        Haptics.success()
        dismiss()
    }
}
