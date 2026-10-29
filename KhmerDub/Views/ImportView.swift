import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var loc: Localization
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var toasts: ToastCenter

    var onCreated: (UUID) -> Void

    @State private var title = ""
    @State private var sourceLanguage: SourceLanguage = .auto
    @State private var photoItem: PhotosPickerItem?
    @State private var stagedURL: URL?
    @State private var mediaInfo: MediaInfo?
    @State private var isInspecting = false
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var showFileImporter = false
    @State private var showSRTImporter = false
    @State private var didCreate = false

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                    .ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        SheetHeader(
                            title: loc.t("import.title"),
                            subtitle: loc.t("import.subtitle"),
                            onClose: { dismiss() }
                        )

                        mediaSection
                        detailsSection

                        if let errorMessage {
                            InlineBanner(kind: .error, text: errorMessage)
                        }

                        Button {
                            createProject()
                        } label: {
                            HStack(spacing: 8) {
                                if isCreating {
                                    ProgressView()
                                        .tint(Color(hex: 0x1A160D))
                                }
                                Text(loc.t(isCreating ? "import.creating" : "import.create"))
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(isCreating || isInspecting || stagedURL == nil || title.trimmed.isEmpty)

                        Text(loc.t("import.tip"))
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(AppTheme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(loc.t("import.supported"))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                }
                .scrollDismissesKeyboard(.interactively)

                if isInspecting {
                    LoadingOverlay(text: loc.t("import.analyzing"))
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.movie, .audio],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await loadFile(url: url) }
            case .failure(let error):
                errorMessage = ErrorPresenter.message(for: error, localization: loc)
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
                loadSRT(url: url)
            case .failure(let error):
                errorMessage = ErrorPresenter.message(for: error, localization: loc)
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
        .onDisappear {
            if !didCreate, let stagedURL {
                try? FileManager.default.removeItem(at: stagedURL)
            }
        }
    }

    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: loc.t("import.selected"))
            if let mediaInfo, let stagedURL {
                VStack(spacing: 14) {
                    if let thumbnail = mediaInfo.thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 190)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(AppTheme.darkGradient)
                                .frame(height: 150)
                            Image(systemName: "waveform")
                                .font(.system(size: 38, weight: .light))
                                .foregroundStyle(AppTheme.gold)
                        }
                    }
                    VStack(spacing: 8) {
                        InfoRow(
                            label: loc.t("import.duration"),
                            value: Formatters.timecode(mediaInfo.duration),
                            symbol: "clock"
                        )
                        InfoRow(
                            label: loc.t("import.fileSize"),
                            value: Formatters.fileSize(mediaInfo.fileSize),
                            symbol: "externaldrive"
                        )
                        InfoRow(
                            label: loc.t("common.about"),
                            value: mediaInfo.hasVideo ? loc.t("import.video") : loc.t("import.audioOnly"),
                            symbol: mediaInfo.hasVideo ? "film" : "waveform"
                        )
                    }
                    Button {
                        removeSelection()
                    } label: {
                        Label(loc.t("import.replace"), systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityHint(stagedURL.lastPathComponent)
                }
                .appCard(elevated: true)
            } else {
                HStack(spacing: 10) {
                    PhotosPicker(selection: $photoItem, matching: .videos) {
                        VStack(spacing: 9) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(AppTheme.goldDeep)
                            Text(loc.t("import.fromPhotos"))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.textPrimary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 112)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(AppTheme.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(AppTheme.border, lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(PressableButtonStyle())

                    Button {
                        showFileImporter = true
                    } label: {
                        VStack(spacing: 9) {
                            Image(systemName: "folder")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(AppTheme.tealDeep)
                            Text(loc.t("import.fromFiles"))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.textPrimary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 112)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(AppTheme.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(AppTheme.border, lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(PressableButtonStyle())

                    Button {
                        showSRTImporter = true
                    } label: {
                        VStack(spacing: 9) {
                            Image(systemName: "captions.bubble.fill")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(AppTheme.capcutCyan)
                            Text(loc.t("srt.import"))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.textPrimary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 112)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(AppTheme.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(AppTheme.border, lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(PressableButtonStyle())
                }
                Text(loc.t("import.videoHint") + " · " + loc.t("import.audioHint"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: loc.t("studio.settings"))
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(loc.t("import.titleLabel"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                    TextField(loc.t("import.titlePlaceholder"), text: $title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .textInputAutocapitalization(.sentences)
                        .cardFieldStyle()
                }
                HStack {
                    Text(loc.t("import.sourceLanguage"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                    Picker("", selection: $sourceLanguage) {
                        ForEach(SourceLanguage.allCases) { language in
                            Text(loc.t(language.localizationKey)).tag(language)
                        }
                    }
                    .labelsHidden()
                    .tint(AppTheme.goldDeep)
                }
            }
            .appCard()
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        await MainActor.run {
            isInspecting = true
            errorMessage = nil
        }
        do {
            guard let movie = try await item.loadTransferable(type: MovieTransferable.self) else {
                throw MediaError.invalidFile
            }
            let info = try await MediaImporter.inspect(url: movie.url)
            applySelection(url: movie.url, info: info, suggestedTitle: nil)
        } catch {
            await MainActor.run {
                errorMessage = ErrorPresenter.message(for: error, localization: loc)
                isInspecting = false
            }
        }
    }

    private func loadFile(url: URL) async {
        await MainActor.run {
            isInspecting = true
            errorMessage = nil
        }
        do {
            let staged = try await Task.detached(priority: .userInitiated) {
                try MediaImporter.stageImport(from: url)
            }.value
            let info = try await MediaImporter.inspect(url: staged)
            applySelection(
                url: staged,
                info: info,
                suggestedTitle: url.deletingPathExtension().lastPathComponent
            )
        } catch {
            await MainActor.run {
                errorMessage = ErrorPresenter.message(for: error, localization: loc)
                isInspecting = false
            }
        }
    }

    private func applySelection(url: URL, info: MediaInfo, suggestedTitle: String?) {
        if let old = stagedURL, old != url {
            try? FileManager.default.removeItem(at: old)
        }
        stagedURL = url
        mediaInfo = info
        if title.trimmed.isEmpty {
            let suggestion = suggestedTitle?.trimmed.nonEmpty
            title = suggestion ?? loc.t("import.titlePlaceholder")
        }
        isInspecting = false
        errorMessage = nil
    }

    private func removeSelection() {
        if let stagedURL {
            try? FileManager.default.removeItem(at: stagedURL)
        }
        stagedURL = nil
        mediaInfo = nil
        photoItem = nil
        errorMessage = nil
    }

    private func loadSRT(url: URL) {
        do {
            let segments = try SubtitleImporter.load(
                from: url,
                defaultVoice: initialVoice,
                speaker: loc.t("segment.speakerPlaceholder")
            )
            guard !segments.isEmpty else {
                errorMessage = loc.t("srt.importFailed")
                return
            }
            let srtTitle = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ")
            let maxDuration = segments.map(\.end).max() ?? 10.0
            var project = DubProject(
                title: srtTitle.isEmpty ? loc.t("demo.title") : srtTitle,
                sourceLanguage: sourceLanguage
            )
            project.segments = segments
            project.duration = maxDuration
            project.mode = settings.defaultMode
            project.style = settings.defaultStyle
            project.fitSpeech = settings.defaultFitSpeech
            project.defaultVoice = initialVoice
            project.waveform = WaveformFallback.demo(count: 96)
            project.recalculateStage()
            store.upsert(project, immediate: true)
            Haptics.success()
            toasts.show(loc.f("srt.importedCount", segments.count))
            onCreated(project.id)
            dismiss()
        } catch {
            errorMessage = loc.t("srt.importFailed")
        }
    }

    private func createProject() {
        guard !isCreating, !isInspecting else { return }
        guard let stagedURL, let mediaInfo else {
            errorMessage = loc.t("import.noMedia")
            return
        }
        let cleanTitle = title.trimmed
        guard !cleanTitle.isEmpty else {
            errorMessage = loc.t("import.titleRequired")
            return
        }
        isCreating = true
        errorMessage = nil
        Task {
            defer { isCreating = false }
            do {
                var project = DubProject(
                    title: cleanTitle,
                    sourceLanguage: sourceLanguage
                )
                project.mode = settings.defaultMode
                project.style = settings.defaultStyle
                project.fitSpeech = settings.defaultFitSpeech
                project.defaultVoice = initialVoice
                try MediaImporter.addMedia(
                    stagedURL: stagedURL,
                    info: mediaInfo,
                    to: &project
                )
                if let mediaURL = AppFiles.mediaURL(for: project) {
                    let waveform = try? await WaveformGenerator.generate(from: mediaURL, bars: 112)
                    if let waveform, !waveform.isEmpty {
                        project.waveform = waveform
                    } else {
                        project.waveform = WaveformFallback.stable(
                            seed: project.id.uuidString,
                            count: 96
                        )
                    }
                }
                project.recalculateStage()
                store.upsert(project, immediate: true)
                didCreate = true
                self.stagedURL = nil
                Haptics.success()
                toasts.show(loc.t("toast.projectCreated"))
                onCreated(project.id)
                dismiss()
            } catch {
                errorMessage = ErrorPresenter.message(for: error, localization: loc)
                Haptics.error()
            }
        }
    }

    private var initialVoice: VoiceChoice {
        if settings.hasAzureKey { return .sreymom }
        if !AppleTTSService.khmerVoices().isEmpty { return .system }
        return .sreymom
    }
}
