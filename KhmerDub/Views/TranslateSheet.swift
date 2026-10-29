import SwiftUI

struct TranslateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var loc: Localization
    @EnvironmentObject private var toasts: ToastCenter

    @ObservedObject var model: StudioModel

    @State private var onlyEmpty = true
    @State private var showAllConfirm = false
    @State private var showAISettings = false
    @State private var showGlossary = false
    @State private var didStart = false

    private var hasConfiguration: Bool {
        settings.aiConfiguration != nil
    }

    private var eligibleSegments: [DubSegment] {
        model.project.segments.filter { segment in
            guard !segment.originalText.trimmed.isEmpty else { return false }
            return onlyEmpty ? !segment.isTranslated : true
        }
    }

    private var canStart: Bool {
        hasConfiguration && !eligibleSegments.isEmpty && !model.isTranslating
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                    .ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        SheetHeader(
                            title: loc.t("translate.title"),
                            subtitle: loc.t("translate.subtitle"),
                            onClose: { dismiss() }
                        )

                        if !hasConfiguration {
                            setupCard
                        } else {
                            styleCard
                            scopeCard
                            glossaryCard
                            if model.isTranslating {
                                progressCard
                            }
                            if let error = model.translationError {
                                InlineBanner(kind: .error, text: error)
                            }
                            startButton
                            Text(loc.t("translate.hint"))
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
            model.clearTranslationError()
            onlyEmpty = true
        }
        .onChange(of: model.isTranslating) { _, active in
            guard didStart, !active else { return }
            didStart = false
            if model.translationError == nil {
                dismiss()
            }
        }
        .sheet(isPresented: $showAISettings) {
            NavigationStack {
                AIEngineSettingsView()
                    .environmentObject(settings)
                    .environmentObject(loc)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(loc.t("common.done")) {
                                showAISettings = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showGlossary) {
            NavigationStack {
                GlossaryView()
                    .environmentObject(settings)
                    .environmentObject(loc)
                    .environmentObject(toasts)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(loc.t("common.done")) {
                                showGlossary = false
                            }
                        }
                    }
            }
        }
        .alert(
            Text(loc.t("translate.overwriteTitle")),
            isPresented: $showAllConfirm
        ) {
            Button(role: .cancel) {
                showAllConfirm = false
            } label: {
                Text(loc.t("common.cancel"))
            }
            Button {
                begin()
            } label: {
                Text(loc.t("translate.allLines"))
            }
        } message: {
            Text(loc.t("translate.overwrite"))
        }
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardIconTitle(
                symbol: "character.book.closed",
                title: loc.t("translate.noKey.title"),
                subtitle: loc.t("translate.noKey.body"),
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

    private var styleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardIconTitle(
                symbol: "wand.and.stars",
                title: loc.t("translate.style"),
                subtitle: loc.t(model.project.style.localizationKey),
                tint: AppTheme.goldDeep
            )
            ForEach(TranslationStyle.allCases) { style in
                Button {
                    model.project.style = style
                    Haptics.selection()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: model.project.style == style ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(model.project.style == style ? AppTheme.goldDeep : AppTheme.textTertiary)
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

    private var scopeCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            CardIconTitle(
                symbol: "text.badge.checkmark",
                title: loc.t("translate.review"),
                subtitle: loc.f("translate.count", eligibleSegments.count),
                tint: AppTheme.indigo
            )
            Picker("", selection: $onlyEmpty) {
                Text(loc.t("translate.keepExisting")).tag(true)
                Text(loc.t("translate.allLines")).tag(false)
            }
            .pickerStyle(.segmented)
            HStack(spacing: 7) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppTheme.success)
                Text(loc.t("translate.preserveNames"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .appCard()
    }

    private var glossaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 11) {
                IconCircle(systemName: "character.book.closed.fill", tint: AppTheme.tealDeep, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc.t("translate.glossary"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(loc.f("translate.glossaryCount", settings.glossary.count))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer()
                Button {
                    showGlossary = true
                } label: {
                    Text(loc.t("common.edit"))
                }
                .buttonStyle(CompactButtonStyle(tint: AppTheme.tealDeep))
            }
            Text(loc.t("glossary.hint"))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .appCard()
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                ProgressView()
                    .tint(AppTheme.gold)
                Text(loc.t("translate.translating"))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text("\(Int((model.translationProgress * 100).rounded()))%")
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppTheme.goldDeep)
            }
            ProgressView(value: model.translationProgress)
                .tint(AppTheme.gold)
            Button {
                model.cancelTranslation()
                didStart = false
            } label: {
                Label(loc.t("common.cancel"), systemImage: "stop.circle")
            }
            .buttonStyle(CompactButtonStyle(tint: AppTheme.danger))
        }
        .appCard()
    }

    private var startButton: some View {
        Button {
            if !onlyEmpty, model.project.translatedCount > 0 {
                showAllConfirm = true
            } else {
                begin()
            }
        } label: {
            Label(loc.t("translate.translateAll"), systemImage: "character.book.closed.fill")
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!canStart)
        .opacity(canStart ? 1 : 0.55)
    }

    private func begin() {
        guard canStart else { return }
        didStart = true
        model.startTranslation(mode: onlyEmpty ? .emptyOnly : .all)
        Haptics.tap()
    }
}
