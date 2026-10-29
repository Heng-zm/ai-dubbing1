import SwiftUI

struct TranscribeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var loc: Localization

    @ObservedObject var model: StudioModel

    @State private var language: SourceLanguage = .auto
    @State private var replaceExisting = false
    @State private var showReplaceConfirm = false
    @State private var showAISettings = false
    @State private var didStart = false

    private var hasConfiguration: Bool {
        settings.aiConfiguration != nil
    }

    private var canStart: Bool {
        hasConfiguration && model.hasMedia && !model.isTranscribing
    }

    private var phaseText: String {
        guard let phase = model.transcriptionPhase else {
            return loc.t("transcribe.start")
        }
        switch phase {
        case .extracting: return loc.t("transcribe.extracting")
        case .uploading: return loc.t("transcribe.uploading")
        case .transcribing: return loc.t("transcribe.transcribing")
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                    .ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        SheetHeader(
                            title: loc.t("transcribe.title"),
                            subtitle: loc.t("transcribe.subtitle"),
                            onClose: { dismiss() }
                        )

                        if !hasConfiguration {
                            setupCard
                        } else {
                            engineCard
                            if !model.hasMedia {
                                InlineBanner(kind: .warning, text: loc.t("transcribe.demoNoMedia"))
                            }
                            languageCard
                            if model.project.segments.isEmpty == false {
                                replaceCard
                            }
                            if model.isTranscribing {
                                progressCard
                            }
                            if let error = model.transcriptionError {
                                InlineBanner(kind: .error, text: error)
                            }
                            startButton
                            Text(loc.t("transcribe.hint"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AppTheme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 32)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            language = model.project.sourceLanguage
            replaceExisting = false
            model.clearTranscriptionError()
        }
        .onChange(of: model.isTranscribing) { _, active in
            guard didStart, !active else { return }
            didStart = false
            if model.transcriptionError == nil {
                dismiss()
            }
        }
        .sheet(isPresented: $showAISettings) {
            NavigationStack {
                AIEngineSettingsView()
                    .environmentObject(settings)
                    .environmentObject(loc)
            }
        }
        .alert(
            Text(loc.t("transcribe.replace.title")),
            isPresented: $showReplaceConfirm
        ) {
            Button(role: .cancel) {
                showReplaceConfirm = false
            } label: {
                Text(loc.t("common.cancel"))
            }
            Button(role: .destructive) {
                begin(replace: true)
            } label: {
                Text(loc.t("transcribe.replace"))
            }
        } message: {
            Text(loc.t("transcribe.replace.message"))
        }
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardIconTitle(
                symbol: "key.horizontal.fill",
                title: loc.t("transcribe.noKey.title"),
                subtitle: loc.t("transcribe.noKey.body"),
                tint: AppTheme.warning
            )
            Button {
                showAISettings = true
            } label: {
                Label(loc.t("transcribe.setupAI"), systemImage: "slider.horizontal.3")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .appCard(elevated: true)
    }

    private var engineCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardIconTitle(
                symbol: "sparkles",
                title: loc.t("transcribe.engine"),
                subtitle: "\(settings.chatModel) · \(settings.transcriptionModel)",
                tint: AppTheme.indigo
            )
            InfoRow(
                label: loc.t("transcribe.model"),
                value: settings.transcriptionModel,
                symbol: "waveform"
            )
            InfoRow(
                label: loc.t("translate.provider"),
                value: settings.aiBaseURL,
                symbol: "network"
            )
        }
        .appCard()
    }

    private var languageCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardIconTitle(
                symbol: "globe",
                title: loc.t("transcribe.language"),
                tint: AppTheme.tealDeep
            )
            Picker("", selection: $language) {
                ForEach(SourceLanguage.allCases) { item in
                    Text(loc.t(item.localizationKey)).tag(item)
                }
            }
            .labelsHidden()
            .tint(AppTheme.goldDeep)
            Text(loc.t("transcribe.hint"))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .appCard()
    }

    private var replaceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardIconTitle(
                symbol: "text.badge.checkmark",
                title: loc.t("transcribe.replace.title"),
                subtitle: loc.f("studio.lineCount", model.project.segments.count),
                tint: AppTheme.gold
            )
            Picker("", selection: $replaceExisting) {
                Text(loc.t("transcribe.append")).tag(false)
                Text(loc.t("transcribe.replace")).tag(true)
            }
            .pickerStyle(.segmented)
        }
        .appCard()
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                ProgressView()
                    .tint(AppTheme.gold)
                Text(phaseText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text("\(Int((model.transcriptionProgress * 100).rounded()))%")
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppTheme.goldDeep)
            }
            ProgressView(value: model.transcriptionProgress)
                .tint(AppTheme.gold)
            Button {
                model.cancelTranscription()
                didStart = false
            } label: {
                Label(loc.t("transcribe.cancelTask"), systemImage: "stop.circle")
            }
            .buttonStyle(CompactButtonStyle(tint: AppTheme.danger))
        }
        .appCard()
    }

    private var startButton: some View {
        Button {
            if replaceExisting, !model.project.segments.isEmpty {
                showReplaceConfirm = true
            } else {
                begin(replace: false)
            }
        } label: {
            Label(loc.t("transcribe.start"), systemImage: "text.bubble.fill")
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!canStart)
        .opacity(canStart ? 1 : 0.55)
    }

    private func begin(replace: Bool) {
        guard canStart else { return }
        model.project.sourceLanguage = language
        didStart = true
        model.startTranscription(replace: replace)
        Haptics.tap()
    }
}
