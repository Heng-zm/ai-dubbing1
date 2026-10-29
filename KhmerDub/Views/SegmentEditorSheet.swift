import SwiftUI

struct SegmentEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var loc: Localization
    @ObservedObject var model: StudioModel
    @ObservedObject var playback: PlaybackController
    let segmentID: UUID

    @StateObject private var preview = SpeechPreviewPlayer()
    @State private var currentID: UUID
    @State private var showDelete = false

    init(model: StudioModel, segmentID: UUID, playback: PlaybackController) {
        self.model = model
        self.playback = playback
        self.segmentID = segmentID
        _currentID = State(initialValue: segmentID)
    }

    private var segment: DubSegment? {
        model.project.segments.first { $0.id == currentID }
    }

    private var timingValid: Bool {
        guard let segment else { return false }
        return segment.end > segment.start + 0.05
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                    .ignoresSafeArea()
                ScrollView {
                    if let segment {
                        VStack(alignment: .leading, spacing: 14) {
                            topSummary(segment)
                            originalCard
                            khmerCard(segment)
                            timingCard(segment)
                            speakerCard(segment)
                            voiceCard(segment)
                            actionsCard(segment)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 32)
                    } else {
                        EmptyStateView(
                            symbol: "text.badge.xmark",
                            title: loc.t("error.noSegments"),
                            body: loc.t("studio.noSegments.body"),
                            actionTitle: loc.t("common.done"),
                            action: { dismiss() }
                        )
                        .appCard()
                        .padding(20)
                    }
                }
                if model.isTranslating {
                    LoadingOverlay(text: loc.t("translate.translating"))
                }
            }
            .navigationTitle(loc.t("segment.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(loc.t("common.close")) {
                        finish()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(loc.t("common.done")) {
                        finish()
                    }
                    .fontWeight(.bold)
                    .disabled(!timingValid)
                }
            }
            .alert(
                Text(loc.t("segment.deleteConfirm")),
                isPresented: $showDelete
            ) {
                Button(role: .cancel) {
                    showDelete = false
                } label: {
                    Text(loc.t("common.cancel"))
                }
                Button(role: .destructive) {
                    preview.stop()
                    model.deleteSegment(id: currentID)
                    dismiss()
                } label: {
                    Text(loc.t("common.delete"))
                }
            }
        }
        .onAppear {
            model.clearTranslationError()
        }
        .onDisappear {
            preview.stop()
            model.refreshStage()
        }
    }

    private func topSummary(_ segment: DubSegment) -> some View {
        HStack(spacing: 8) {
            StageBadge(stage: model.project.stage)
            VoiceBadge(voice: segment.voice)
            Spacer()
            Text(Formatters.preciseTimecode(segment.duration) + " " + loc.t("common.seconds"))
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.textTertiary)
        }
    }

    private var originalCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            CardIconTitle(
                symbol: "text.alignleft",
                title: loc.t("segment.original"),
                tint: AppTheme.indigo
            )
            textEditor(
                text: textBinding(\.originalText),
                placeholder: loc.t("import.tip")
            )
        }
        .appCard()
    }

    private func khmerCard(_ segment: DubSegment) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            CardIconTitle(
                symbol: "character.book.closed",
                title: loc.t("segment.khmer"),
                tint: AppTheme.goldDeep
            )
            textEditor(
                text: textBinding(\.translatedText),
                placeholder: loc.t("lab.textPlaceholder")
            )
            HStack(spacing: 8) {
                Button {
                    model.startTranslateSegment(id: currentID)
                    Haptics.tap()
                } label: {
                    Label(loc.t("segment.translate"), systemImage: "character.book.closed")
                }
                .buttonStyle(CompactButtonStyle(tint: AppTheme.goldDeep))
                .disabled(model.isTranslating || segment.originalText.trimmed.isEmpty)

                Button {
                    model.startPolish(id: currentID)
                    Haptics.tap()
                } label: {
                    Label(loc.t("segment.polish"), systemImage: "wand.and.stars")
                }
                .buttonStyle(CompactButtonStyle(tint: AppTheme.indigo))
                .disabled(model.isTranslating || !segment.isTranslated)
            }
            VoicePreviewControl(
                isPlaying: preview.isPlaying,
                isBusy: false,
                titleKey: "segment.preview"
            ) {
                previewVoice(segment)
            }
            if let error = model.translationError {
                InlineBanner(kind: .error, text: error)
            }
            if let error = preview.errorMessage {
                InlineBanner(kind: .warning, text: error)
            }
        }
        .appCard()
    }

    private func timingCard(_ segment: DubSegment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CardIconTitle(
                symbol: "timer",
                title: loc.t("segment.timing"),
                tint: AppTheme.tealDeep
            )
            HStack(spacing: 10) {
                timingField(
                    title: loc.t("segment.start"),
                    value: Binding(
                        get: { segment.start },
                        set: { model.setStart($0, for: currentID) }
                    )
                )
                timingField(
                    title: loc.t("segment.end"),
                    value: Binding(
                        get: { segment.end },
                        set: { model.setEnd($0, for: currentID) }
                    )
                )
            }
            HStack {
                Text(loc.t("common.duration"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                Text(String(format: "%.1f %@", segment.duration, loc.t("common.seconds")))
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
            }
            if !timingValid {
                InlineBanner(kind: .error, text: loc.t("segment.invalidTiming"))
            }
        }
        .appCard()
    }

    private func timingField(title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
            TextField(
                "0.0",
                value: value,
                format: .number.precision(.fractionLength(1))
            )
            .keyboardType(.decimalPad)
            .font(.system(size: 15, weight: .bold, design: .monospaced))
            .multilineTextAlignment(.center)
            .cardFieldStyle()
        }
        .frame(maxWidth: .infinity)
    }

    private func speakerCard(_ segment: DubSegment) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            CardIconTitle(
                symbol: "person.wave.2",
                title: loc.t("segment.speaker"),
                tint: AppTheme.gold
            )
            TextField(
                loc.t("segment.speakerPlaceholder"),
                text: textBinding(\.speaker)
            )
            .font(.system(size: 14, weight: .semibold))
            .cardFieldStyle()
        }
        .appCard()
    }

    private func voiceCard(_ segment: DubSegment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CardIconTitle(
                symbol: "waveform",
                title: loc.t("segment.voice"),
                tint: AppTheme.goldDeep
            )
            VoiceChoiceGrid(
                selection: Binding(
                    get: { segment.voice },
                    set: { newValue in update { $0.voice = newValue } }
                )
            )
            Text(loc.t("segment.voiceHint"))
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)
            VoiceSliderRow(
                title: loc.t("segment.rate"),
                hint: loc.t("segment.rateHint"),
                value: Binding(
                    get: { segment.rate },
                    set: { newValue in update { $0.rate = newValue.clamped(to: 0.5...2.0) } }
                ),
                range: 0.5...2.0
            )
            VoiceSliderRow(
                title: loc.t("segment.pitch"),
                hint: loc.t("segment.pitchHint"),
                value: Binding(
                    get: { segment.pitch },
                    set: { newValue in update { $0.pitch = newValue.clamped(to: 0.5...2.0) } }
                ),
                range: 0.5...2.0
            )
            Button {
                model.resetVoice(for: currentID)
                Haptics.selection()
            } label: {
                Label(loc.t("segment.reset"), systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(CompactButtonStyle(tint: AppTheme.textSecondary))
        }
        .appCard()
    }

    private func actionsCard(_ segment: DubSegment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(
                isOn: Binding(
                    get: { segment.isIncluded },
                    set: { newValue in update { $0.isIncluded = newValue } }
                )
            ) {
                Text(loc.t("segment.include"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .tint(AppTheme.teal)

            DividerLine()

            HStack(spacing: 8) {
                Button {
                    if let newID = model.splitSegment(id: currentID) {
                        currentID = newID
                        Haptics.success()
                    }
                } label: {
                    Label(loc.t("segment.split"), systemImage: "scissors")
                }
                .buttonStyle(CompactButtonStyle(tint: AppTheme.textSecondary))
                .disabled(segment.duration < 0.8)

                Button {
                    if let newID = model.duplicateSegment(id: currentID) {
                        currentID = newID
                        Haptics.success()
                    }
                } label: {
                    Label(loc.t("segment.duplicate"), systemImage: "plus.square.on.square")
                }
                .buttonStyle(CompactButtonStyle(tint: AppTheme.textSecondary))
            }

            Text(loc.t("segment.splitHelp"))
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)

            Button(role: .destructive) {
                showDelete = true
            } label: {
                Label(loc.t("segment.delete"), systemImage: "trash")
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.danger)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(AppTheme.danger.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
        }
        .appCard()
    }

    private func textEditor(text: Binding<String>, placeholder: String) -> some View {
        ZStack(alignment: .topLeading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.textTertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
            }
            TextEditor(text: text)
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(AppTheme.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 96)
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

    private func textBinding(_ keyPath: WritableKeyPath<DubSegment, String>) -> Binding<String> {
        Binding(
            get: {
                model.project.segments.first(where: { $0.id == currentID })?[keyPath: keyPath] ?? ""
            },
            set: { newValue in
                update { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private func update(_ action: (inout DubSegment) -> Void) {
        guard let index = model.project.segments.firstIndex(where: { $0.id == currentID }) else { return }
        action(&model.project.segments[index])
    }

    private func previewVoice(_ segment: DubSegment) {
        if preview.isPlaying {
            preview.stop()
            return
        }
        Task {
            await preview.preview(
                text: segment.translatedText,
                voice: segment.voice,
                rate: segment.rate,
                pitch: segment.pitch,
                settings: settings
            )
        }
    }

    private func finish() {
        model.refreshStage()
        dismiss()
    }
}
