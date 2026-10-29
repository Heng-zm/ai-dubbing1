import SwiftUI

struct ProjectRowView: View {
    @EnvironmentObject private var loc: Localization
    let project: DubProject
    var showProgress = true

    var body: some View {
        HStack(spacing: 13) {
            ProjectThumbnailView(project: project, width: 88, height: 62)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Text(project.title)
                        .font(.system(size: 14.5, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                    if project.isDemo {
                        BadgeView(text: loc.t("projects.demo"), color: AppTheme.teal)
                    }
                }
                HStack(spacing: 8) {
                    StageBadge(stage: project.stage)
                    Text(Formatters.timecode(project.duration))
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.textTertiary)
                    Text("·")
                        .foregroundStyle(AppTheme.textTertiary)
                    Text(loc.f("studio.lineCount", project.segments.count))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                if showProgress {
                    HStack(spacing: 8) {
                        ProgressView(value: project.progress)
                            .tint(project.stage == .exported ? AppTheme.success : AppTheme.gold)
                        Text("\(Int((project.progress * 100).rounded()))%")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.textTertiary)
                            .frame(width: 30, alignment: .trailing)
                    }
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AppTheme.textTertiary.opacity(0.7))
        }
        .contentShape(Rectangle())
    }
}

struct ProjectMenuButton: View {
    @EnvironmentObject private var loc: Localization
    var onDuplicate: () -> Void
    var onDelete: () -> Void

    var body: some View {
        Menu {
            Button {
                onDuplicate()
            } label: {
                Label(loc.t("projects.duplicate"), systemImage: "plus.square.on.square")
            }
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label(loc.t("common.delete"), systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(AppTheme.surfaceMuted))
        }
    }
}
