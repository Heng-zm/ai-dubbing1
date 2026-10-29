import SwiftUI

struct ExportPanel: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var loc: Localization

    @ObservedObject var model: StudioModel

    @State private var format: ExportFormat = .audio
    @State private var includeSubtitles = true

    private var readiness: VoiceReadiness {
        TTSService.shared.readiness(settings: settings)
    }

    private var includedSegments: [DubSegment] {
        model.includedTranslatedSegments
    }

    private var sortedExports: [ExportRecord] {
        model.project.exports.sorted { $0.createdAt > $1.createdAt }
    }

    private var voiceIssue: String? {
        guard !includedSegments.isEmpty else { return nil }
        let usesAzure = includedSegments.contains { $0.voice.isAzure }
        let usesApple = includedSegments.contains { !$0.voice.isAzure }
        if usesAzure, !settings.hasAzureKey {
            return loc.t("voice.azureMissing")
        }
        if usesApple, AppleTTSService.khmerVoices().isEmpty {
            return loc.t("voice.appleMissing")
        }
        return nil
    }

    private var canExport: Bool {
        !includedSegments.isEmpty &&
        !model.isExporting &&
        voiceIssue == nil &&
        (format == .audio || model.project.hasVideo)
    }

    private var phaseText: String {
        guard let phase = model.exportPhase else {
            return loc.t("export.working")
        }
        return loc.t(phase.localizationKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            readinessCard
            formatCard
            optionsCard
            if model.isExporting {
                progressCard
            }
            if let error = model.exportError {
                VStack(alignment: .leading, spacing: 9) {
                    InlineBanner(kind: .error, text: error)
                    Button {
                        model.clearExportError()
                    } label: {
                        Text(loc.t("common.dismiss"))
                    }
                    .buttonStyle(CompactButtonStyle(tint: AppTheme.textSecondary))
                }
            }
            exportButton
            if let result = model.lastExport {
                resultCard(result)
            }
            recentExports
        }
        .onAppear {
            format = model.project.hasVideo ? .video : .audio
            includeSubtitles = model.project.includeSubtitles
        }
        .onChange(of: model.project.hasVideo) { _, hasVideo in
            if !hasVideo, format == .video {
                format = .audio
            }
        }
    }

    private var readinessCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            CardIconTitle(
                symbol: canExport ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                title: loc.t("studio.export"),
                subtitle: canExport ? loc.t("studio.exportReady") : loc.t("studio.exportNeedsTranslation"),
                tint: canExport ? AppTheme.success : AppTheme.warning
            )
            checkRow(
                title: loc.t("export.duration"),
                value: Formatters.timecode(model.project.duration),
                ready: model.hasMedia,
                symbol: "clock"
            )
            checkRow(
                title: loc.t("translate.review"),
                value: loc.f("studio.lineCount", includedSegments.count),
                ready: !includedSegments.isEmpty,
                symbol: "text.bubble"
            )
            checkRow(
                title: loc.t("voice.readiness"),
                value: readiness.isReady ? loc.t("common.ready") : loc.t("common.notConfigured"),
                ready: readiness.isReady,
                symbol: "waveform"
            )
            if let voiceIssue {
                InlineBanner(kind: .warning, text: voiceIssue)
            }
        }
        .appCard()
    }

    private func checkRow(
        title: String,
        value: String,
        ready: Bool,
        symbol: String
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: ready ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(ready ? AppTheme.success : AppTheme.textTertiary)
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.textTertiary)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
        }
    }

    private var formatCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            CardIconTitle(
                symbol: "film",
                title: loc.t("export.format"),
                tint: AppTheme.goldDeep
            )
            HStack(spacing: 9) {
                formatOption(
                    .video,
                    symbol: "film",
                    title: loc.t("export.video"),
                    hint: loc.t("export.videoHint"),
                    enabled: model.project.hasVideo
                )
                formatOption(
                    .audio,
                    symbol: "waveform",
                    title: loc.t("export.audio"),
                    hint: loc.t("export.audioHint"),
                    enabled: true
                )
            }
            if !model.project.hasVideo {
                Text(loc.t("export.videoNeedsMedia"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(AppTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .appCard()
    }

    private func formatOption(
        _ option: ExportFormat,
        symbol: String,
        title: String,
        hint: String,
        enabled: Bool
    ) -> some View {
        Button {
            guard enabled else { return }
            format = option
            Haptics.selection()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(format == option ? AppTheme.goldDeep : AppTheme.textTertiary)
                    Spacer()
                    Image(systemName: format == option ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(format == option ? AppTheme.goldDeep : AppTheme.textTertiary)
                }
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(hint)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(format == option ? AppTheme.gold.opacity(0.1) : AppTheme.surfaceMuted)
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(
                                format == option ? AppTheme.gold : AppTheme.border,
                                lineWidth: format == option ? 1.5 : 1
                            )
                    )
            )
            .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!enabled)
    }

    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardIconTitle(
                symbol: "slider.horizontal.3",
                title: loc.t("export.title"),
                tint: AppTheme.indigo
            )
            Toggle(isOn: $includeSubtitles) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc.t("export.subtitles"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(loc.t("export.subtitlesHint"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
            .tint(AppTheme.teal)

            Toggle(isOn: Binding(
                get: { model.project.fitSpeech },
                set: { model.project.fitSpeech = $0 }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc.t("export.fit"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(loc.t("voice.fitHint"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
            .tint(AppTheme.teal)

            Toggle(isOn: Binding(
                get: { model.project.normalizeVolume },
                set: { model.project.normalizeVolume = $0 }
            )) {
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

            Text(loc.t("export.overwriteHint"))
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
                Text(phaseText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text("\(Int((model.exportProgress * 100).rounded()))%")
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppTheme.goldDeep)
            }
            ProgressView(value: model.exportProgress)
                .tint(AppTheme.gold)
            HStack {
                Text(loc.t("export.working"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(AppTheme.textTertiary)
                Spacer()
                Button {
                    model.cancelExport()
                } label: {
                    Label(loc.t("common.cancel"), systemImage: "stop.circle")
                }
                .buttonStyle(CompactButtonStyle(tint: AppTheme.danger))
            }
        }
        .appCard()
    }

    private var exportButton: some View {
        Button {
            model.startExport(format: format, includeSubtitles: includeSubtitles)
            Haptics.tap()
        } label: {
            HStack(spacing: 8) {
                if model.isExporting {
                    ProgressView()
                        .tint(Color(hex: 0x1A160D))
                }
                Text(loc.t("export.start"))
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!canExport)
        .opacity(canExport ? 1 : 0.55)
    }

    private func resultCard(_ result: DubExportResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CardIconTitle(
                symbol: result.kind.symbol,
                title: loc.t("export.done"),
                subtitle: result.url.lastPathComponent,
                tint: AppTheme.success
            )
            HStack(spacing: 16) {
                InfoRow(label: loc.t("export.duration"), value: Formatters.timecode(result.duration), symbol: "clock")
                InfoRow(label: loc.t("export.fileSize"), value: Formatters.fileSize(result.fileSize), symbol: "externaldrive")
            }
            HStack(spacing: 9) {
                ShareLink(item: result.url) {
                    Label(loc.t("export.share"), systemImage: "square.and.arrow.up")
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.goldDeep)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(AppTheme.gold.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)

                if result.kind == .video {
                    Button {
                        Task { await model.saveLastVideoToPhotos() }
                    } label: {
                        HStack(spacing: 6) {
                            if model.isSavingPhoto {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "photo.badge.arrow.down")
                            }
                            Text(loc.t("export.savePhotos"))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.tealDeep)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(AppTheme.teal.opacity(0.1))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isSavingPhoto)
                }
            }
            if let subtitleURL = result.subtitleURL {
                ShareLink(item: subtitleURL) {
                    Label(loc.t("export.subtitleReady"), systemImage: "captions.bubble")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
        .appCard(elevated: true)
    }

    private var recentExports: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: loc.t("export.recent"))
            if model.project.exports.isEmpty {
                Text(loc.t("export.none"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(sortedExports) { record in
                        exportRow(record)
                        if record.id != sortedExports.last?.id {
                            DividerLine()
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AppTheme.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(AppTheme.border, lineWidth: 1)
                        )
                )
            }
        }
    }

    private func exportRow(_ record: ExportRecord) -> some View {
        let url = AppFiles.exportURL(for: model.project, fileName: record.fileName)
        return HStack(spacing: 10) {
            Image(systemName: record.kind.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.goldDeep)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.fileName)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                Text("\(Formatters.fileSize(record.fileSize)) · \(Formatters.relativeDate(record.createdAt, language: loc.language))")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            Spacer(minLength: 4)
            if FileManager.default.fileExists(atPath: url.path) {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(AppTheme.surfaceMuted))
                }
                .buttonStyle(.plain)
            }
            Menu {
                Button(role: .destructive) {
                    model.deleteExport(record)
                } label: {
                    Label(loc.t("common.delete"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.textTertiary)
                    .frame(width: 28, height: 28)
            }
        }
        .padding(.vertical, 10)
    }
}
