import AVFAudio
import AVFoundation
import Foundation
import SwiftUI
import UIKit

struct VoiceLabView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var loc: Localization
    @EnvironmentObject private var toasts: ToastCenter

    @Binding var selectedTab: AppTab

    @State private var text = ""
    @State private var voice: VoiceChoice = .sreymom
    @State private var rate = 1.0
    @State private var pitch = 1.0
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var generatedURL: URL?
    @State private var generatedSize: Int64 = 0
    @State private var appleVoices: [AVSpeechSynthesisVoice] = []
    @State private var showVoiceSettings = false
    @StateObject private var player = AudioFilePlayer()

    private var readiness: VoiceReadiness {
        TTSService.shared.readiness(settings: settings)
    }

    private var characterCount: Int {
        text.count
    }

    private var canGenerate: Bool {
        !isGenerating && !text.trimmed.isEmpty && characterCount <= 2_000
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                    .ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        readinessCard
                        composerCard
                        voiceCard
                        if let generatedURL {
                            generatedCard(generatedURL)
                        }
                        diagnosticsCard
                        Text(loc.t("lab.note"))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(AppTheme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 2)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 30)
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            appleVoices = AppleTTSService.khmerVoices()
            if !settings.hasAzureKey, !appleVoices.isEmpty, voice == .sreymom {
                voice = .system
            }
        }
        .onDisappear {
            player.stop()
        }
        .sheet(isPresented: $showVoiceSettings) {
            NavigationStack {
                VoiceSettingsView()
                    .environmentObject(settings)
                    .environmentObject(loc)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(loc.t("lab.title"))
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(loc.t("lab.subtitle"))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                showVoiceSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(AppTheme.surface))
                    .overlay(Circle().stroke(AppTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(loc.t("voice.settings")))
        }
    }

    private var readinessCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardIconTitle(
                symbol: readiness.isReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                title: loc.t("lab.readiness"),
                subtitle: readiness.isReady ? loc.t("home.voiceCard.ready") : loc.t("home.voiceCard.needsSetup"),
                tint: readiness.isReady ? AppTheme.success : AppTheme.warning
            )
            HStack(spacing: 9) {
                statusPill(
                    title: loc.t("voice.azure"),
                    ready: readiness.azureReady,
                    symbol: "cloud.fill"
                )
                statusPill(
                    title: loc.t("voice.system"),
                    ready: readiness.appleReady,
                    symbol: "apple.logo"
                )
            }
            Button {
                showVoiceSettings = true
            } label: {
                Text(loc.t("lab.azureSetup"))
            }
            .buttonStyle(SecondaryButtonStyle())
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

    private var composerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardIconTitle(
                symbol: "text.alignleft",
                title: loc.t("studio.khmer"),
                subtitle: loc.t("lab.subtitle"),
                tint: AppTheme.goldDeep
            )
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(loc.t("lab.textPlaceholder"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.textTertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 130)
            }
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(AppTheme.surfaceMuted)
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(AppTheme.border, lineWidth: 1)
                    )
            )

            HStack {
                Text(loc.f("lab.characters", characterCount))
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(characterCount > 2_000 ? AppTheme.danger : AppTheme.textTertiary)
                Spacer()
                Button {
                    UIPasteboard.general.string = text
                    toasts.show(loc.t("lab.copied"))
                    Haptics.tap()
                } label: {
                    Label(loc.t("lab.copy"), systemImage: "doc.on.doc")
                }
                .buttonStyle(CompactButtonStyle(tint: AppTheme.textSecondary))
                .disabled(text.isEmpty)

                Button {
                    text = ""
                    Haptics.tap()
                } label: {
                    Label(loc.t("common.clear"), systemImage: "xmark")
                }
                .buttonStyle(CompactButtonStyle(tint: AppTheme.textSecondary))
                .disabled(text.isEmpty)
            }

            if characterCount > 2_000 {
                InlineBanner(kind: .warning, text: loc.t("lab.limit"))
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(loc.t("lab.quickPhrases"))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(AppTheme.textTertiary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(1...3, id: \.self) { index in
                            Button {
                                text = loc.t("lab.phrase\(index)")
                                Haptics.selection()
                            } label: {
                                Text(loc.t("lab.phrase\(index)"))
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(Capsule().fill(AppTheme.surfaceMuted))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .appCard()
    }

    private var voiceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardIconTitle(
                symbol: "waveform",
                title: loc.t("lab.voice"),
                tint: AppTheme.goldDeep
            )
            VoiceChoiceGrid(selection: $voice)
            VoiceSliderRow(
                title: loc.t("lab.rate"),
                hint: loc.t("segment.rateHint"),
                value: $rate,
                range: 0.5...2.0
            )
            VoiceSliderRow(
                title: loc.t("lab.pitch"),
                hint: loc.t("segment.pitchHint"),
                value: $pitch,
                range: 0.5...2.0
            )
            Button {
                generate()
            } label: {
                HStack(spacing: 8) {
                    if isGenerating {
                        ProgressView()
                            .tint(Color(hex: 0x1A160D))
                    } else {
                        Image(systemName: "waveform.badge.plus")
                    }
                    Text(loc.t(isGenerating ? "lab.generating" : "lab.generate"))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canGenerate)
            .opacity(canGenerate ? 1 : 0.55)

            if let errorMessage {
                InlineBanner(kind: .error, text: errorMessage)
            }
        }
        .appCard()
    }

    private func generatedCard(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CardIconTitle(
                symbol: "waveform.circle.fill",
                title: loc.t("lab.audioReady"),
                subtitle: url.lastPathComponent,
                tint: AppTheme.teal
            )
            HStack(spacing: 10) {
                Button {
                    player.toggle()
                    Haptics.tap()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(hex: 0x20180A))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(AppTheme.gold))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 5) {
                    WaveformView(
                        values: WaveformFallback.stable(seed: url.lastPathComponent, count: 42),
                        progress: player.duration > 0 ? player.currentTime / player.duration : 0,
                        tint: AppTheme.gold,
                        idleTint: AppTheme.textTertiary.opacity(0.35)
                    )
                    .frame(height: 36)
                    HStack {
                        Text(Formatters.preciseTimecode(player.currentTime))
                        Spacer()
                        Text(Formatters.timecode(max(player.duration, 0.01)))
                    }
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.textTertiary)
                }
            }
            HStack(spacing: 9) {
                ShareLink(item: url) {
                    Label(loc.t("lab.shareAudio"), systemImage: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.goldDeep)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(AppTheme.gold.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    saveAudio(url)
                } label: {
                    Label(loc.t("lab.saveAudio"), systemImage: "folder.badge.plus")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.tealDeep)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(AppTheme.teal.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)
            }
            Text(Formatters.fileSize(generatedSize))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .appCard(elevated: true)
    }

    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                SectionTitle(title: loc.t("voice.diagnostics"))
                Button {
                    appleVoices = AppleTTSService.khmerVoices()
                    Haptics.tap()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(AppTheme.surfaceMuted))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(loc.t("voice.refresh")))
            }

            if appleVoices.isEmpty {
                InlineBanner(kind: .info, text: loc.t("voice.appleMissing"))
                Text(loc.t("voice.installHint"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(AppTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(appleVoices.enumerated()), id: \.element.identifier) { index, appleVoice in
                        HStack(spacing: 9) {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppTheme.textSecondary)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(appleVoice.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(AppTheme.textPrimary)
                                Text(appleVoice.language)
                                    .font(.system(size: 9.5, weight: .medium))
                                    .foregroundStyle(AppTheme.textTertiary)
                            }
                            Spacer()
                            if settings.appleVoiceIdentifier == appleVoice.identifier {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(AppTheme.teal)
                            }
                        }
                        .padding(.vertical, 8)
                        if index < appleVoices.count - 1 {
                            DividerLine()
                        }
                    }
                }
            }
        }
        .appCard()
    }

    private func generate() {
        guard canGenerate else { return }
        let cleanText = text.trimmed
        errorMessage = nil
        player.stop()
        isGenerating = true
        Task { @MainActor in
            do {
                let url = try await TTSService.shared.renderToTemporaryFile(
                    text: cleanText,
                    voice: voice,
                    rate: rate,
                    pitch: pitch,
                    settings: settings
                )
                if let old = generatedURL, old != url {
                    try? FileManager.default.removeItem(at: old)
                }
                generatedURL = url
                generatedSize = fileSize(at: url)
                player.play(url: url)
                Haptics.success()
            } catch {
                errorMessage = ErrorPresenter.message(for: error, localization: loc)
                Haptics.error()
            }
            isGenerating = false
        }
    }

    private func saveAudio(_ url: URL) {
        let ext = url.pathExtension.isEmpty ? "mp3" : url.pathExtension
        let fileName = "KhmerDub-voice-\(Formatters.fileTimestamp()).\(ext)"
        let destination = AppFiles.voiceLabRoot.appendingPathComponent(fileName)
        do {
            try FileManager.default.createDirectory(
                at: AppFiles.voiceLabRoot,
                withIntermediateDirectories: true
            )
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: url, to: destination)
            toasts.show(loc.t("toast.voiceSaved"))
            Haptics.success()
        } catch {
            errorMessage = ErrorPresenter.message(for: error, localization: loc)
            Haptics.error()
        }
    }

    private func fileSize(at url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }
}
