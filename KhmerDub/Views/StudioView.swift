import AVKit
import SwiftUI

struct StudioView: View {
    @EnvironmentObject private var store: ProjectStore
    let projectID: UUID

    var body: some View {
        if let project = store.project(id: projectID) {
            StudioScreen(projectID: projectID, initialProject: project)
        } else {
            StudioMissingView()
        }
    }
}

private struct StudioMissingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var loc: Localization

    var body: some View {
        ZStack {
            ScreenBackground()
                .ignoresSafeArea()
            EmptyStateView(
                symbol: "questionmark.folder",
                title: loc.t("error.projectMissing"),
                body: loc.t("projects.empty.body"),
                actionTitle: loc.t("common.back"),
                action: { dismiss() }
            )
            .appCard()
            .padding(20)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

private enum StudioSheet: Identifiable {
    case transcribe
    case translate
    case media
    case settings
    case segment(UUID)

    var id: String {
        switch self {
        case .transcribe: return "transcribe"
        case .translate: return "translate"
        case .media: return "media"
        case .settings: return "settings"
        case .segment(let id): return "segment-\(id.uuidString)"
        }
    }
}

private enum StudioTab: String, CaseIterable, Identifiable {
    case script
    case voice
    case export

    var id: String { rawValue }
    var localizationKey: String { "studio.\(rawValue)" }
    var symbol: String {
        switch self {
        case .script: return "text.alignleft"
        case .voice: return "waveform"
        case .export: return "square.and.arrow.up"
        }
    }
}

struct StudioScreen: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var loc: Localization
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var toasts: ToastCenter
    @Environment(\.dismiss) private var dismiss

    let projectID: UUID
    @StateObject private var model: StudioModel
    @StateObject private var playback = PlaybackController()

    @State private var tab: StudioTab = .script
    @State private var sheet: StudioSheet?
    @State private var mediaError: String?
    @State private var isAddingMedia = false
    @State private var configured = false

    init(projectID: UUID, initialProject: DubProject) {
        self.projectID = projectID
        _model = StateObject(wrappedValue: StudioModel(project: initialProject))
    }

    var body: some View {
        ZStack {
            ScreenBackground()
                .ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statusHeader
                    mediaCard
                    if model.hasMedia {
                        playbackControls
                    }
                    if let mediaError {
                        InlineBanner(kind: .error, text: mediaError)
                    }
                    actionRow
                    tabPicker
                    tabContent
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle(model.project.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        sheet = .media
                    } label: {
                        Label(loc.t("studio.addMedia"), systemImage: "film.stack")
                    }
                    Button {
                        sheet = .settings
                    } label: {
                        Label(loc.t("studio.settings"), systemImage: "slider.horizontal.3")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 17, weight: .semibold))
                }
                .accessibilityLabel(Text(loc.t("studio.moreActions")))
            }
        }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .transcribe:
                TranscribeSheet(model: model)
                    .environmentObject(settings)
                    .environmentObject(loc)
                    .environmentObject(toasts)
            case .translate:
                TranslateSheet(model: model)
                    .environmentObject(settings)
                    .environmentObject(loc)
                    .environmentObject(toasts)
            case .media:
                MediaPickerSheet { url, info in
                    addMedia(url: url, info: info)
                }
                .environmentObject(loc)
            case .settings:
                ProjectSettingsSheet(model: model)
                    .environmentObject(loc)
                    .environmentObject(toasts)
            case .segment(let id):
                SegmentEditorSheet(model: model, segmentID: id, playback: playback)
                    .environmentObject(settings)
                    .environmentObject(loc)
                    .environmentObject(toasts)
            }
        }
        .overlay {
            if isAddingMedia {
                LoadingOverlay(text: loc.t("import.processing"))
            }
        }
        .task {
            guard !configured else { return }
            configured = true
            model.configure(settings: settings, store: store, localization: loc, toasts: toasts)
            await model.ensureWaveform()
            loadPlayback()
        }
        .onChange(of: model.project.mediaFileName) { _, _ in
            loadPlayback()
        }
        .onDisappear {
            playback.stop()
            model.flush()
        }
    }

    private var statusHeader: some View {
        HStack(spacing: 8) {
            StageBadge(stage: model.project.stage)
            if model.project.isDemo {
                BadgeView(text: loc.t("studio.demoBadge"), color: AppTheme.teal)
            }
            Spacer()
            Label(Formatters.timecode(model.project.duration), systemImage: "clock")
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textTertiary)
            Text(loc.f("studio.lineCount", model.project.segments.count))
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .padding(.horizontal, 2)
    }

    private var mediaCard: some View {
        Group {
            if let mediaURL = AppFiles.mediaURL(for: model.project) {
                if model.project.hasVideo, let player = playback.player {
                    VideoPlayer(player: player)
                        .allowsHitTesting(false)
                        .frame(height: 205)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(alignment: .bottomLeading) {
                            HStack(spacing: 10) {
                                Button {
                                    playback.toggle()
                                    Haptics.tap()
                                } label: {
                                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 40, height: 40)
                                        .background(Circle().fill(Color.black.opacity(0.48)))
                                        .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                Text(Formatters.preciseTimecode(playback.currentTime))
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(Color.black.opacity(0.42)))
                                Spacer()
                            }
                            .padding(12)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                } else {
                    audioTimelineCard(url: mediaURL)
                }
            } else {
                noMediaCard
            }
        }
    }

    private func audioTimelineCard(url: URL) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppTheme.darkGradient)
            VStack(spacing: 14) {
                HStack {
                    Label(
                        model.project.hasAudio ? loc.t("studio.originalAudio") : loc.t("studio.noMedia"),
                        systemImage: "waveform"
                    )
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.gold.opacity(0.85))
                    Spacer()
                    Text(Formatters.timecode(model.project.duration))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                }
                WaveformView(
                    values: model.project.waveform.isEmpty
                        ? WaveformFallback.stable(seed: model.project.id.uuidString, count: 96)
                        : model.project.waveform,
                    progress: model.project.duration > 0
                        ? playback.currentTime / model.project.duration
                        : 0,
                    tint: AppTheme.gold,
                    idleTint: .white.opacity(0.24)
                )
                .frame(height: 74)
                HStack(spacing: 9) {
                    Button {
                        playback.toggle()
                        Haptics.tap()
                    } label: {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(hex: 0x20180A))
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(AppTheme.gold))
                    }
                    .buttonStyle(.plain)
                    Text(Formatters.preciseTimecode(playback.currentTime))
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.65))
                    Spacer()
                    Text(loc.t("studio.originalAudio"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.38))
                }
            }
            .padding(16)
        }
        .accessibilityHint(url.lastPathComponent)
    }

    private var noMediaCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppTheme.darkGradient)
            VStack(spacing: 12) {
                Image(systemName: "film.stack")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(AppTheme.gold.opacity(0.9))
                Text(loc.t("studio.noMedia"))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(loc.t("studio.noMedia.body"))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.52))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    sheet = .media
                } label: {
                    Text(loc.t("studio.addMedia"))
                }
                .buttonStyle(CompactButtonStyle(tint: AppTheme.gold))
                .padding(.top, 2)
            }
            .padding(20)
        }
    }

    private var playbackControls: some View {
        HStack(spacing: 12) {
            Button {
                playback.toggle()
                Haptics.tap()
            } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(hex: 0x20180A))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(AppTheme.gold))
            }
            .buttonStyle(.plain)

            Text(Formatters.preciseTimecode(playback.currentTime))
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 44, alignment: .leading)

            Slider(
                value: Binding(
                    get: { playback.currentTime },
                    set: { playback.seek(to: $0) }
                ),
                in: 0...max(playback.duration, 0.01)
            )
            .tint(AppTheme.gold)

            Text(Formatters.preciseTimecode(max(playback.duration, model.project.duration)))
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.textTertiary)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 4)
    }

    private var actionRow: some View {
        HStack(spacing: 9) {
            StudioActionButton(
                symbol: "text.bubble",
                title: loc.t("studio.transcribe"),
                tint: AppTheme.indigo
            ) {
                sheet = .transcribe
            }
            StudioActionButton(
                symbol: "character.book.closed",
                title: loc.t("studio.translate"),
                tint: AppTheme.goldDeep
            ) {
                sheet = .translate
            }
            StudioActionButton(
                symbol: "plus",
                title: loc.t("studio.addSegment"),
                tint: AppTheme.tealDeep
            ) {
                addLine()
            }
        }
    }

    private var tabPicker: some View {
        HStack(spacing: 4) {
            ForEach(StudioTab.allCases) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        tab = item
                    }
                    Haptics.selection()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 10, weight: .bold))
                        Text(loc.t(item.localizationKey))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(tab == item ? Color(hex: 0x20180A) : AppTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(tab == item ? AppTheme.gold : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.surfaceMuted)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .script:
            StudioScriptView(
                model: model,
                playback: playback,
                onEdit: { id in sheet = .segment(id) },
                onTranscribe: { sheet = .transcribe },
                onAdd: { addLine() }
            )
        case .voice:
            StudioVoicePanel(model: model)
        case .export:
            ExportPanel(model: model)
        }
    }

    private func addLine() {
        let id = model.addSegment(at: playback.currentTime)
        tab = .script
        sheet = .segment(id)
        Haptics.tap()
    }

    private func loadPlayback() {
        playback.stop()
        guard let url = AppFiles.mediaURL(for: model.project) else { return }
        playback.load(url: url, durationHint: model.project.duration)
    }

    private func addMedia(url: URL, info: MediaInfo) {
        isAddingMedia = true
        mediaError = nil
        Task {
            do {
                try await model.addMedia(stagedURL: url, info: info)
                Haptics.success()
                toasts.show(loc.t("toast.saved"))
            } catch {
                try? FileManager.default.removeItem(at: url)
                mediaError = ErrorPresenter.message(for: error, localization: loc)
                Haptics.error()
            }
            isAddingMedia = false
        }
    }
}

private struct StudioActionButton: View {
    let symbol: String
    let title: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 66)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AppTheme.border, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PressableButtonStyle())
    }
}
