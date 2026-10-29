import SwiftUI
import UIKit

// MARK: - Toast

@MainActor
final class ToastCenter: ObservableObject {
    @Published private(set) var message: String?

    private var hideTask: Task<Void, Never>?

    func show(_ text: String) {
        guard !text.trimmed.isEmpty else { return }
        message = text
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }
}

struct ToastView: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(AppTheme.teal)
            Text(text)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(Capsule().stroke(AppTheme.border, lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.14), radius: 18, x: 0, y: 8)
        .padding(.horizontal, 24)
        .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - Waveform

struct WaveformView: View {
    let values: [Double]
    var progress: Double = 0
    var tint: Color = AppTheme.gold
    var idleTint: Color = AppTheme.textTertiary

    var body: some View {
        Canvas { context, size in
            guard !values.isEmpty, size.width > 1, size.height > 1 else { return }
            let count = values.count
            let gap = max(1.0, size.width / CGFloat(count) * 0.28)
            let barWidth = max(1.0, (size.width - gap * CGFloat(max(0, count - 1))) / CGFloat(count))
            let clampedProgress = progress.clamped(to: 0...1)
            for index in values.indices {
                let value = values[index].clamped(to: 0...1)
                let barHeight = max(2.0, size.height * CGFloat(value))
                let x = CGFloat(index) * (barWidth + gap)
                let rect = CGRect(
                    x: x,
                    y: (size.height - barHeight) / 2,
                    width: barWidth,
                    height: barHeight
                )
                let played = Double(index + 1) / Double(count) <= clampedProgress
                let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                context.fill(path, with: .color(played ? tint : idleTint.opacity(0.5)))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Media and status

struct ProjectThumbnailView: View {
    let project: DubProject
    var width: CGFloat = 92
    var height: CGFloat = 64
    var radius: CGFloat = 13

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(AppTheme.darkGradient)
            if let url = AppFiles.thumbnailURL(for: project),
               let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: project.hasVideo ? "film.stack" : "waveform")
                    .font(.system(size: min(width, height) * 0.34, weight: .semibold))
                    .foregroundStyle(AppTheme.gold.opacity(0.9))
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

struct StageBadge: View {
    @EnvironmentObject private var loc: Localization
    let stage: ProjectStage

    private var color: Color {
        switch stage {
        case .draft: return AppTheme.textSecondary
        case .transcribed: return AppTheme.indigo
        case .translated: return AppTheme.goldDeep
        case .exported: return AppTheme.success
        }
    }

    var body: some View {
        BadgeView(text: loc.t(stage.localizationKey), color: color)
    }
}

struct VoiceBadge: View {
    @EnvironmentObject private var loc: Localization
    let voice: VoiceChoice

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: voice.symbol)
                .font(.system(size: 9, weight: .bold))
            Text(voice.displayName)
                .font(.system(size: 10, weight: .bold, design: .rounded))
        }
        .foregroundStyle(voice.isAzure ? AppTheme.goldDeep : AppTheme.textSecondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill((voice.isAzure ? AppTheme.gold : AppTheme.textSecondary).opacity(0.11))
        )
    }
}

struct InlineBanner: View {
    enum Kind {
        case info
        case warning
        case success
        case error
    }

    let kind: Kind
    let text: String

    private var color: Color {
        switch kind {
        case .info: return AppTheme.indigo
        case .warning: return AppTheme.warning
        case .success: return AppTheme.success
        case .error: return AppTheme.danger
        }
    }

    private var symbol: String {
        switch kind {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(color)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(color.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(color.opacity(0.18), lineWidth: 1)
        )
    }
}

// MARK: - Layout helpers

struct SheetHeader: View {
    let title: String
    var subtitle: String?
    var onClose: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(AppTheme.surfaceMuted))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
            }
        }
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let body: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 13) {
            ZStack {
                Circle()
                    .fill(AppTheme.gold.opacity(0.1))
                    .frame(width: 78, height: 78)
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(AppTheme.goldDeep)
            }
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.center)
            Text(body)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 18)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(CompactButtonStyle(tint: AppTheme.goldDeep))
                    .padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

struct LoadingOverlay: View {
    let text: String
    var progress: Double?

    var body: some View {
        ZStack {
            Color.black.opacity(0.26)
                .ignoresSafeArea()
            VStack(spacing: 15) {
                ProgressView()
                    .tint(AppTheme.gold)
                    .scaleEffect(1.15)
                Text(text)
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                    .multilineTextAlignment(.center)
                if let progress {
                    ProgressView(value: progress.clamped(to: 0...1))
                        .tint(AppTheme.gold)
                        .frame(width: 190)
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 22)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(AppTheme.border, lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.18), radius: 22, x: 0, y: 10)
        }
        .transition(.opacity)
        .accessibilityAddTraits(.isModal)
    }
}

struct StatTile: View {
    let value: String
    let label: String
    let symbol: String
    var tint: Color = AppTheme.gold

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(AppTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
        )
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    var symbol: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.textTertiary)
                    .frame(width: 17)
            }
            Text(label)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct SettingsRow<Destination: View>: View {
    let symbol: String
    let title: String
    var subtitle: String?
    var tint: Color = AppTheme.gold
    let destination: Destination

    init(
        symbol: String,
        title: String,
        subtitle: String? = nil,
        tint: Color = AppTheme.gold,
        @ViewBuilder destination: () -> Destination
    ) {
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
        self.destination = destination()
    }

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 13) {
                IconCircle(systemName: symbol, tint: tint, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 6)
            }
            .padding(.vertical, 3)
        }
    }
}

struct CardIconTitle: View {
    let symbol: String
    let title: String
    var subtitle: String?
    var tint: Color = AppTheme.gold

    var body: some View {
        HStack(spacing: 12) {
            IconCircle(systemName: symbol, tint: tint, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct ProgressLine: View {
    let title: String
    let progress: Double
    var tint: Color = AppTheme.gold

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                Text("\(Int((progress.clamped(to: 0...1) * 100).rounded()))%")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
            }
            ProgressView(value: progress.clamped(to: 0...1))
                .tint(tint)
        }
    }
}

struct DividerWithLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(AppTheme.border)
                .frame(height: 1)
            Text(text)
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textTertiary)
                .textCase(.uppercase)
            Rectangle()
                .fill(AppTheme.border)
                .frame(height: 1)
        }
    }
}

extension View {
    func appSheetBackground() -> some View {
        background(ScreenBackground().ignoresSafeArea())
    }

    func appListBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(ScreenBackground())
    }

    func cardFieldStyle() -> some View {
        padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.surfaceMuted)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AppTheme.border, lineWidth: 1)
                    )
            )
    }
}

enum AppInfo {
    static var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    static var displayName: String {
        Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? "KhmerDub"
    }
}
