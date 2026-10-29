import AVKit
import SwiftUI
import UniformTypeIdentifiers

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
    @State private var showSRTImporter = false

    init(projectID: UUID, initialProject: DubProject) {
        self.projectID = projectID
        _model = StateObject(wrappedValue: StudioModel(project: initialProject))
    }

    var body: some View {
        ZStack {
            ScreenBackground()
                .ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    statusHeader
                    mediaCard
                    if model.hasMedia {
                        timelineScrubberCard
                    }
                    if let mediaError {
                        InlineBanner(kind: .error, text: mediaError)
                    }
                    capcutActionDock
                    tabPicker
                    tabContent
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 36)
            }
        }
        .navigationTitle(model.project.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showSRTImporter = true
                    } label: {
                        Label(loc.t("srt.import"), systemImage: "captions.bubble")
                    }
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
        .fileImporter(
            isPresented: $showSRTImporter,
            allowedContentTypes: [.plainText, UTType(filenameExtension: "srt") ?? .plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                model.importSRT(url: url)
            case .failure(let error):
                mediaError = ErrorPresenter.message(for: error, localization: loc)
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

    // MARK: - CapCut Stage Viewport
    private var mediaCard: some View {
        Group {
            if let mediaURL = AppFiles.mediaURL(for: model.project) {
                if model.project.hasVideo, let player = playback.player {
                    ZStack(alignment: .bottom) {
                        VideoPlayer(player: player)
                            .allowsHitTesting(false)
                            .frame(height: 220)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                        // CapCut Top HUD Overlay
                        VStack {
                            HStack {
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(playback.isPlaying ? AppTheme.teal : AppTheme.capcutNeonGold)
                                        .frame(width: 6, height: 6)
                                    Text(Formatters.preciseTimecode(playback.currentTime))
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    Text("/")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.55))
                                    Text(Formatters.preciseTimecode(max(playback.duration, model.project.duration)))
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.75))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.black.opacity(0.65)))
                                .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))

                                Spacer()

                                HStack(spacing: 4) {
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 9, weight: .black))
                                        .foregroundStyle(AppTheme.capcutCyan)
                                    Text("1080P · 60FPS · GPU")
                                        .font(.system(size: 9.5, weight: .black, design: .rounded))
                                        .foregroundStyle(.white)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.black.opacity(0.65)))
                                .overlay(Capsule().stroke(AppTheme.capcutCyan.opacity(0.4), lineWidth: 1))
                            }
                            .padding(10)
                            Spacer()
                        }

                        // CapCut Center/Bottom Floating Playback Controls
                        HStack(spacing: 20) {
                            Button {
                                playback.seek(to: max(0, playback.currentTime - 2.0))
                                Haptics.tap()
                            } label: {
                                Image(systemName: "gobackward.2")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(Color.black.opacity(0.55)))
                                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                            }
                            .buttonStyle(.plain)

                            Button {
                                playback.toggle()
                                Haptics.tap()
                            } label: {
                                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 18, weight: .heavy))
                                    .foregroundStyle(Color(hex: 0x0A0D14))
                                    .frame(width: 48, height: 48)
                                    .background(Circle().fill(AppTheme.capcutNeonGold))
                                    .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1.5))
                                    .shadow(color: AppTheme.capcutNeonGold.opacity(0.45), radius: 8, x: 0, y: 0)
                            }
                            .buttonStyle(.plain)

                            Button {
                                playback.seek(to: min(model.project.duration, playback.currentTime + 2.0))
                                Haptics.tap()
                            } label: {
                                Image(systemName: "goforward.2")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(Color.black.opacity(0.55)))
                                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.bottom, 14)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
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
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.capcutPanel)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
            VStack(spacing: 14) {
                HStack {
                    Label(
                        model.project.hasAudio ? loc.t("studio.originalAudio") : loc.t("studio.noMedia"),
                        systemImage: "waveform"
                    )
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.capcutNeonGold)
                    Spacer()
                    Text("AUDIO · 60FPS · GPU")
                        .font(.system(size: 9.5, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.capcutCyan)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.black.opacity(0.4)))
                }
                WaveformView(
                    values: model.project.waveform.isEmpty
                        ? WaveformFallback.stable(seed: model.project.id.uuidString, count: 96)
                        : model.project.waveform,
                    progress: model.project.duration > 0
                        ? playback.currentTime / model.project.duration
                        : 0,
                    tint: AppTheme.capcutNeonGold,
                    idleTint: .white.opacity(0.24)
                )
                .frame(height: 74)
                HStack(spacing: 12) {
                    Button {
                        playback.seek(to: max(0, playback.currentTime - 2.0))
                        Haptics.tap()
                    } label: {
                        Image(systemName: "gobackward.2")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.black.opacity(0.55)))
                    }
                    .buttonStyle(.plain)

                    Button {
                        playback.toggle()
                        Haptics.tap()
                    } label: {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundStyle(Color(hex: 0x0A0D14))
                            .frame(width: 42, height: 42)
                            .background(Circle().fill(AppTheme.capcutNeonGold))
                            .shadow(color: AppTheme.capcutNeonGold.opacity(0.4), radius: 6)
                    }
                    .buttonStyle(.plain)

                    Button {
                        playback.seek(to: min(model.project.duration, playback.currentTime + 2.0))
                        Haptics.tap()
                    } label: {
                        Image(systemName: "goforward.2")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.black.opacity(0.55)))
                    }
                    .buttonStyle(.plain)

                    Spacer()
                    Text(Formatters.preciseTimecode(playback.currentTime) + " / " + Formatters.timecode(model.project.duration))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .padding(16)
        }
        .accessibilityHint(url.lastPathComponent)
    }

    private var noMediaCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.capcutPanel)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
            VStack(spacing: 12) {
                Image(systemName: "film.stack")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(AppTheme.capcutNeonGold)
                Text(loc.t("studio.noMedia"))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(loc.t("studio.noMedia.body"))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button {
                        sheet = .media
                    } label: {
                        Text(loc.t("studio.addMedia"))
                    }
                    .buttonStyle(CompactButtonStyle(tint: AppTheme.capcutNeonGold))

                    Button {
                        showSRTImporter = true
                    } label: {
                        Label(loc.t("srt.import"), systemImage: "captions.bubble.fill")
                    }
                    .buttonStyle(CompactButtonStyle(tint: AppTheme.capcutCyan))
                }
                .padding(.top, 4)
            }
            .padding(20)
        }
    }

    // MARK: - CapCut Multi-Track Timeline Scrubber
    private var timelineScrubberCard: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text(Formatters.preciseTimecode(playback.currentTime))
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppTheme.capcutNeonGold)
                    .frame(width: 48, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { playback.currentTime },
                        set: { playback.seek(to: $0) }
                    ),
                    in: 0...max(playback.duration, model.project.duration, 0.01)
                )
                .tint(AppTheme.capcutNeonGold)

                Text(Formatters.preciseTimecode(max(playback.duration, model.project.duration)))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.textTertiary)
                    .frame(width: 48, alignment: .trailing)
            }

            if !model.project.segments.isEmpty, model.project.duration > 0 {
                GeometryReader { geo in
                    let total = max(model.project.duration, playback.duration, 0.01)
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 8)

                        ForEach(model.project.segments) { segment in
                            let left = (segment.start / total) * geo.size.width
                            let width = max(4, ((segment.end - segment.start) / total) * geo.size.width)
                            let isCurrent = playback.isPlaying && playback.currentTime >= segment.start && playback.currentTime <= segment.end
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(isCurrent ? AppTheme.capcutNeonGold : (segment.isTranslated ? AppTheme.teal : AppTheme.indigo))
                                .frame(width: min(width, geo.size.width - left), height: 8)
                                .offset(x: left)
                        }

                        let cursorX = (playback.currentTime / total) * geo.size.width
                        Capsule()
                            .fill(Color.white)
                            .frame(width: 3, height: 14)
                            .offset(x: max(0, min(cursorX, geo.size.width - 3)))
                            .shadow(color: .white.opacity(0.9), radius: 3)
                    }
                }
                .frame(height: 14)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - CapCut Action Dock
    private var capcutActionDock: some View {
        HStack(spacing: 2) {
            CapCutDockItem(
                symbol: "scissors",
                title: loc.t("segment.split"),
                tint: AppTheme.capcutCyan
            ) {
                splitAtPlayhead()
            }
            CapCutDockItem(
                symbol: "captions.bubble.fill",
                title: "SRT",
                tint: AppTheme.indigo
            ) {
                showSRTImporter = true
            }
            CapCutDockItem(
                symbol: "character.book.closed.fill",
                title: loc.t("studio.translate"),
                tint: AppTheme.goldDeep
            ) {
                sheet = .translate
            }
            CapCutDockItem(
                symbol: "waveform.circle.fill",
                title: loc.t("studio.voice"),
                tint: AppTheme.teal
            ) {
                withAnimation { tab = .voice }
            }
            CapCutDockItem(
                symbol: "bolt.badge.clock.fill",
                title: "60 FPS",
                tint: AppTheme.capcutNeonGold
            ) {
                withAnimation { tab = .export }
            }
            CapCutDockItem(
                symbol: "plus.circle.fill",
                title: loc.t("common.add"),
                tint: .white
            ) {
                addLine()
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.capcutPanel)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 10, y: 5)
        )
    }

    private func splitAtPlayhead() {
        let time = playback.currentTime
        if let segment = model.project.segments.first(where: { time > $0.start + 0.3 && time < $0.end - 0.3 }) {
            _ = model.splitSegment(id: segment.id)
            Haptics.success()
            toasts.show(loc.t("segment.split"))
        } else {
            addLine()
        }
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

private struct CapCutDockItem: View {
    let symbol: String
    let title: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(height: 20)
                Text(title)
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(PressableButtonStyle())
    }
}
