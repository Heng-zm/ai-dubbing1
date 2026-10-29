import SwiftUI

struct StudioScriptView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var loc: Localization
    @ObservedObject var model: StudioModel
    @ObservedObject var playback: PlaybackController

    var onEdit: (UUID) -> Void
    var onTranscribe: () -> Void
    var onAdd: () -> Void

    @StateObject private var preview = SpeechPreviewPlayer()
    @State private var previewingID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let message = preview.errorMessage {
                InlineBanner(kind: .warning, text: message)
            }
            if model.project.segments.isEmpty {
                EmptyStateView(
                    symbol: "text.badge.plus",
                    title: loc.t("studio.noSegments.title"),
                    body: loc.t("studio.noSegments.body"),
                    actionTitle: loc.t("studio.transcribe"),
                    action: onTranscribe
                )
                .appCard()
            } else {
                LazyVStack(spacing: 11) {
                    ForEach(model.project.segments) { segment in
                        segmentRow(segment)
                    }
                }
                Button {
                    onAdd()
                } label: {
                    Label(loc.t("studio.addSegment"), systemImage: "plus")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .onChange(of: preview.isPlaying) { _, playing in
            if !playing {
                previewingID = nil
            }
        }
        .onDisappear {
            preview.stop()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(loc.t("studio.script"))
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(loc.t("studio.tapToEdit"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            Spacer()
            Text("\(model.project.translatedCount)/\(model.project.segments.count)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.goldDeep)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(AppTheme.gold.opacity(0.12)))
        }
    }

    private func segmentRow(_ segment: DubSegment) -> some View {
        let isCurrentPlayback = playback.isPlaying && playback.currentTime >= segment.start && playback.currentTime <= segment.end
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Button {
                    guard playback.hasItem else { return }
                    if isCurrentPlayback {
                        playback.pause()
                    } else {
                        playback.seekAndPlay(to: segment.start)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isCurrentPlayback ? "speaker.wave.3.fill" : "play.fill")
                            .font(.system(size: isCurrentPlayback ? 8 : 7, weight: .bold))
                            .foregroundStyle(isCurrentPlayback ? AppTheme.goldDeep : AppTheme.textSecondary)
                        Text(Formatters.preciseTimecode(segment.start))
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(isCurrentPlayback ? AppTheme.goldDeep : AppTheme.textSecondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(isCurrentPlayback ? AppTheme.gold.opacity(0.18) : AppTheme.surfaceMuted))
                }
                .buttonStyle(.plain)
                .disabled(!playback.hasItem)
                .accessibilityLabel(Text(loc.t("studio.seekToLine")))

                Text(segment.speaker)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineLimit(1)

                VoiceBadge(voice: segment.voice)
                Spacer(minLength: 4)

                Button {
                    toggleIncluded(segment.id)
                    Haptics.selection()
                } label: {
                    Image(systemName: segment.isIncluded ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(segment.isIncluded ? AppTheme.teal : AppTheme.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(loc.t("studio.toggleIncluded")))

                Menu {
                    Button {
                        onEdit(segment.id)
                    } label: {
                        Label(loc.t("studio.openSegment"), systemImage: "pencil")
                    }
                    Button {
                        previewSegment(segment)
                    } label: {
                        Label(loc.t("studio.linePreview"), systemImage: "speaker.wave.2")
                    }
                    .disabled(!segment.isTranslated)
                    Button {
                        _ = model.splitSegment(id: segment.id)
                    } label: {
                        Label(loc.t("segment.split"), systemImage: "scissors")
                    }
                    .disabled(segment.duration < 0.8)
                    Button {
                        if let newID = model.duplicateSegment(id: segment.id) {
                            onEdit(newID)
                        }
                    } label: {
                        Label(loc.t("segment.duplicate"), systemImage: "plus.square.on.square")
                    }
                    Divider()
                    Button(role: .destructive) {
                        preview.stop()
                        model.deleteSegment(id: segment.id)
                    } label: {
                        Label(loc.t("segment.delete"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppTheme.textTertiary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(AppTheme.surfaceMuted))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(segment.originalText.trimmed.isEmpty ? "—" : segment.originalText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(2)
                HStack(alignment: .top, spacing: 8) {
                    Text(segment.translatedText.trimmed.isEmpty ? loc.t("studio.noTranslation") : segment.translatedText)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(segment.isTranslated ? AppTheme.textPrimary : AppTheme.textTertiary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onEdit(segment.id)
            }

            HStack(spacing: 8) {
                if segment.isTranslated {
                    Button {
                        previewSegment(segment)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: previewingID == segment.id && preview.isPlaying ? "stop.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text(loc.t(previewingID == segment.id && preview.isPlaying ? "voice.stop" : "studio.linePreview"))
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(AppTheme.goldDeep)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(AppTheme.gold.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text(Formatters.preciseTimecode(segment.start) + " – " + Formatters.preciseTimecode(segment.end))
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(isCurrentPlayback ? AppTheme.surfaceElevated : AppTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            isCurrentPlayback ? AppTheme.gold : (segment.isIncluded ? AppTheme.border : AppTheme.border.opacity(0.45)),
                            lineWidth: isCurrentPlayback ? 1.5 : 1
                        )
                )
        )
        .animation(.easeInOut(duration: 0.22), value: isCurrentPlayback)
        .opacity(segment.isIncluded ? 1 : 0.55)
        .contextMenu {
            Button {
                onEdit(segment.id)
            } label: {
                Label(loc.t("studio.openSegment"), systemImage: "pencil")
            }
            Button {
                previewSegment(segment)
            } label: {
                Label(loc.t("studio.linePreview"), systemImage: "speaker.wave.2")
            }
            .disabled(!segment.isTranslated)
            Button(role: .destructive) {
                preview.stop()
                model.deleteSegment(id: segment.id)
            } label: {
                Label(loc.t("segment.delete"), systemImage: "trash")
            }
        }
    }

    private func toggleIncluded(_ id: UUID) {
        guard let index = model.project.segments.firstIndex(where: { $0.id == id }) else { return }
        model.project.segments[index].isIncluded.toggle()
        model.project.recalculateStage()
    }

    private func previewSegment(_ segment: DubSegment) {
        if previewingID == segment.id, preview.isPlaying {
            preview.stop()
            previewingID = nil
            return
        }
        preview.stop()
        previewingID = segment.id
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
}
