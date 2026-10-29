import SwiftUI

struct StudioVoicePanel: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var loc: Localization

    @ObservedObject var model: StudioModel

    @StateObject private var preview = SpeechPreviewPlayer()
    @State private var showVoiceSettings = false

    private var readiness: VoiceReadiness {
        TTSService.shared.readiness(settings: settings)
    }

    private var defaultVoice: Binding<VoiceChoice> {
        Binding(
            get: { model.project.defaultVoice },
            set: { model.project.defaultVoice = $0 }
        )
    }

    private var defaultRate: Binding<Double> {
        Binding(
            get: { model.project.voiceRate },
            set: { model.project.voiceRate = $0.clamped(to: 0.5...2.0) }
        )
    }

    private var defaultPitch: Binding<Double> {
        Binding(
            get: { model.project.voicePitch },
            set: { model.project.voicePitch = $0.clamped(to: 0.5...2.0) }
        )
    }

    private var mode: Binding<DubMode> {
        Binding(
            get: { model.project.mode },
            set: { model.project.mode = $0 }
        )
    }

    private var originalVolume: Binding<Double> {
        Binding(
            get: { model.project.originalVolume },
            set: { model.project.originalVolume = $0.clamped(to: 0...1) }
        )
    }

    private var dubVolume: Binding<Double> {
        Binding(
            get: { model.project.dubVolume },
            set: { model.project.dubVolume = $0.clamped(to: 0...1) }
        )
    }

    private var fitSpeech: Binding<Bool> {
        Binding(
            get: { model.project.fitSpeech },
            set: { model.project.fitSpeech = $0 }
        )
    }

    private var normalize: Binding<Bool> {
        Binding(
            get: { model.project.normalizeVolume },
            set: { model.project.normalizeVolume = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            readinessCard
            defaultVoiceCard
            if !model.speakerNames.isEmpty {
                speakerCastCard
            }
            mixCard
            Text(loc.t("voice.notePlaceholder"))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
        }
        .onDisappear {
            preview.stop()
        }
        .sheet(isPresented: $showVoiceSettings) {
            NavigationStack {
                VoiceSettingsView()
                    .environmentObject(settings)
                    .environmentObject(loc)
            }
        }
    }

    private var readinessCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardIconTitle(
                    symbol: readiness.isReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                    title: loc.t("voice.readiness"),
                    subtitle: readiness.isReady ? loc.t("home.voiceCard.ready") : loc.t("home.voiceCard.needsSetup"),
                    tint: readiness.isReady ? AppTheme.success : AppTheme.warning
                )
                Spacer(minLength: 4)
                Button {
                    showVoiceSettings = true
                } label: {
                    Text(loc.t("common.setup"))
                }
                .buttonStyle(CompactButtonStyle(tint: AppTheme.goldDeep))
            }

            VStack(spacing: 8) {
                readinessRow(
                    symbol: "cloud.fill",
                    title: loc.t("voice.azure"),
                    ready: readiness.azureReady,
                    readyText: loc.t("voice.azureReady"),
                    missingText: loc.t("voice.azureMissing")
                )
                readinessRow(
                    symbol: "apple.logo",
                    title: loc.t("voice.system"),
                    ready: readiness.appleReady,
                    readyText: loc.t("voice.appleReady"),
                    missingText: loc.t("voice.appleMissing")
                )
            }

            VoicePreviewControl(
                isPlaying: preview.isPlaying,
                isBusy: false,
                titleKey: "voice.test"
            ) {
                previewDefaultVoice()
            }

            if let error = preview.errorMessage {
                InlineBanner(kind: .warning, text: error)
            }
        }
        .appCard()
    }

    private func readinessRow(
        symbol: String,
        title: String,
        ready: Bool,
        readyText: String,
        missingText: String
    ) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ready ? AppTheme.teal : AppTheme.textTertiary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(ready ? readyText : missingText)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Image(systemName: ready ? "checkmark.circle.fill" : "minus.circle")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(ready ? AppTheme.success : AppTheme.textTertiary)
        }
    }

    private var defaultVoiceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardIconTitle(
                symbol: "waveform",
                title: loc.t("voice.default"),
                subtitle: loc.t("voice.subtitle"),
                tint: AppTheme.goldDeep
            )
            VoiceChoiceGrid(selection: defaultVoice)
            VoiceSliderRow(
                title: loc.t("voice.rate"),
                hint: loc.t("segment.rateHint"),
                value: defaultRate,
                range: 0.5...2.0
            )
            VoiceSliderRow(
                title: loc.t("voice.pitch"),
                hint: loc.t("segment.pitchHint"),
                value: defaultPitch,
                range: 0.5...2.0
            )
            Button {
                model.applyVoiceToAll(
                    voice: model.project.defaultVoice,
                    rate: model.project.voiceRate,
                    pitch: model.project.voicePitch
                )
                Haptics.success()
            } label: {
                Label(loc.t("voice.applyAll"), systemImage: "checkmark.circle")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(model.project.segments.isEmpty)
        }
        .appCard()
    }

    private var speakerCastCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            CardIconTitle(
                symbol: "person.wave.2.fill",
                title: loc.t("voice.cast"),
                subtitle: loc.t("voice.speakerVoices"),
                tint: AppTheme.tealDeep
            )
            ForEach(model.speakerNames, id: \.self) { speaker in
                HStack(spacing: 10) {
                    Text(speaker)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Menu {
                        ForEach(VoiceChoice.allCases) { voice in
                            Button {
                                model.applyVoice(voice: voice, toSpeaker: speaker)
                                Haptics.selection()
                            } label: {
                                if voiceForSpeaker(speaker) == voice {
                                    Label(voice.displayName, systemImage: "checkmark")
                                } else {
                                    Text(voice.displayName)
                                }
                            }
                        }
                    } label: {
                        VoiceBadge(voice: voiceForSpeaker(speaker))
                    }
                }
                .padding(.vertical, 2)
                if speaker != model.speakerNames.last {
                    DividerLine()
                }
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
                tint: AppTheme.indigo
            )
            Picker("", selection: mode) {
                ForEach(DubMode.allCases) { item in
                    Text(loc.t(item.localizationKey)).tag(item)
                }
            }
            .labelsHidden()
            .tint(AppTheme.goldDeep)
            Text(loc.t("mode.\(model.project.mode.rawValue).hint"))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if model.project.mode != .replace {
                volumeRow(
                    title: loc.t("voice.originalVolume"),
                    value: originalVolume,
                    tint: AppTheme.textSecondary
                )
            }
            volumeRow(
                title: loc.t("voice.dubVolume"),
                value: dubVolume,
                tint: AppTheme.goldDeep
            )

            Toggle(isOn: fitSpeech) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc.t("voice.fit"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(loc.t("voice.fitHint"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
            .tint(AppTheme.teal)

            Toggle(isOn: normalize) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc.t("export.normalize"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(loc.t("export.normalizeHint"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
            .tint(AppTheme.teal)
        }
        .appCard()
    }

    private func volumeRow(
        title: String,
        value: Binding<Double>,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text("\(Int((value.wrappedValue * 100).rounded()))%")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .monospacedDigit()
            }
            Slider(value: value, in: 0...1)
                .tint(tint)
        }
    }

    private func voiceForSpeaker(_ speaker: String) -> VoiceChoice {
        model.project.segments.first(where: { $0.speaker == speaker })?.voice ?? model.project.defaultVoice
    }

    private func previewDefaultVoice() {
        if preview.isPlaying {
            preview.stop()
            return
        }
        Task {
            await preview.preview(
                text: loc.t("voice.testPhrase"),
                voice: model.project.defaultVoice,
                rate: model.project.voiceRate,
                pitch: model.project.voicePitch,
                settings: settings
            )
        }
    }
}
