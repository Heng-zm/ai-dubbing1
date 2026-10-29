import SwiftUI

struct VoiceChoiceGrid: View {
    @EnvironmentObject private var loc: Localization
    @Binding var selection: VoiceChoice
    var compact = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(VoiceChoice.allCases) { voice in
                Button {
                    selection = voice
                    Haptics.selection()
                } label: {
                    VStack(spacing: compact ? 4 : 7) {
                        Image(systemName: voice.symbol)
                            .font(.system(size: compact ? 16 : 20, weight: .semibold))
                            .foregroundStyle(selection == voice ? AppTheme.goldDeep : AppTheme.textTertiary)
                        Text(voice.displayName)
                            .font(.system(size: compact ? 10.5 : 12, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if !compact {
                            Text(loc.t(voice.genderKey))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(AppTheme.textTertiary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: compact ? 58 : 82)
                    .background(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(selection == voice ? AppTheme.gold.opacity(0.1) : AppTheme.surfaceMuted)
                            .overlay(
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .stroke(
                                        selection == voice ? AppTheme.gold : AppTheme.border,
                                        lineWidth: selection == voice ? 1.5 : 1
                                    )
                            )
                    )
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
    }
}

struct VoiceReadinessPill: View {
    @EnvironmentObject private var loc: Localization
    let ready: Bool
    var readyKey = "voice.azureReady"
    var missingKey = "voice.azureMissing"

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 11, weight: .bold))
            Text(loc.t(ready ? readyKey : missingKey))
                .font(.system(size: 10.5, weight: .semibold))
                .lineLimit(2)
        }
        .foregroundStyle(ready ? AppTheme.success : AppTheme.warning)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill((ready ? AppTheme.success : AppTheme.warning).opacity(0.1))
        )
    }
}

struct VoiceSliderRow: View {
    @EnvironmentObject private var loc: Localization
    let title: String
    let hint: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var format: String = "%.2f×"

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text(String(format: format, value))
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.goldDeep)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range)
                .tint(AppTheme.gold)
            Text(hint)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)
        }
    }
}

struct VoicePreviewControl: View {
    @EnvironmentObject private var loc: Localization
    let isPlaying: Bool
    let isBusy: Bool
    var titleKey = "voice.test"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView()
                        .tint(AppTheme.goldDeep)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                }
                Text(loc.t(isPlaying ? "voice.stop" : titleKey))
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
            }
            .foregroundStyle(AppTheme.goldDeep)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(AppTheme.gold.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(AppTheme.gold.opacity(0.25), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isBusy)
    }
}
