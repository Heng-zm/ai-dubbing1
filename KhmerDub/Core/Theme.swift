import SwiftUI
import UIKit

enum AppTheme {
    static let background = Color.adaptive(light: 0xF7F4ED, dark: 0x090C12)
    static let backgroundDeep = Color.adaptive(light: 0xEFE9DC, dark: 0x05070B)
    static let surface = Color.adaptive(light: 0xFFFFFF, dark: 0x111621)
    static let surfaceElevated = Color.adaptive(light: 0xFFFDF8, dark: 0x171E2C)
    static let surfaceMuted = Color.adaptive(light: 0xF0EBE0, dark: 0x0E131D)
    static let textPrimary = Color.adaptive(light: 0x171B24, dark: 0xF7F2E8)
    static let textSecondary = Color.adaptive(light: 0x5E6572, dark: 0xA7AFBF)
    static let textTertiary = Color.adaptive(light: 0x8B919B, dark: 0x707A8D)
    static let border = Color.adaptive(light: 0xE4DED2, dark: 0x232B3A)
    static let borderStrong = Color.adaptive(light: 0xD3C9B7, dark: 0x334056)

    static let gold = Color(hex: 0xF2B75C)
    static let goldDeep = Color(hex: 0xD99335)
    static let teal = Color(hex: 0x2AC7A6)
    static let tealDeep = Color(hex: 0x14947E)
    static let indigo = Color(hex: 0x6E7BFF)
    static let coral = Color(hex: 0xFF7A6E)
    static let danger = Color(hex: 0xE85D62)
    static let success = Color(hex: 0x32B67A)
    static let warning = Color(hex: 0xF0A23E)

    // CapCut Video Editor Palette
    static let capcutDark = Color(hex: 0x0A0D14)
    static let capcutPanel = Color(hex: 0x121722)
    static let capcutCard = Color(hex: 0x1A202E)
    static let capcutCyan = Color(hex: 0x00E5FF)
    static let capcutNeonGold = Color(hex: 0xFFC837)

    static let heroGradient = LinearGradient(
        colors: [Color(hex: 0x13231F), Color(hex: 0x1D3B36), Color(hex: 0x2A2415)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let goldGradient = LinearGradient(
        colors: [Color(hex: 0xFFD88B), Color(hex: 0xE9A83E)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let tealGradient = LinearGradient(
        colors: [Color(hex: 0x41E2C1), Color(hex: 0x159F87)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let darkGradient = LinearGradient(
        colors: [Color(hex: 0x111C22), Color(hex: 0x0B1017)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardShadow = Color.black.opacity(0.07)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(
            uiColor: UIColor { traits in
                UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
            }
        )
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}

struct ScreenBackground: View {
    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            RadialGradient(
                colors: [AppTheme.gold.opacity(0.09), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 430
            )
            .ignoresSafeArea()
            RadialGradient(
                colors: [AppTheme.teal.opacity(0.08), .clear],
                center: .bottomLeading,
                startRadius: 10,
                endRadius: 380
            )
            .ignoresSafeArea()
        }
    }
}

struct CardModifier: ViewModifier {
    var padding: CGFloat
    var radius: CGFloat
    var elevated: Bool

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(elevated ? AppTheme.surfaceElevated : AppTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(AppTheme.border.opacity(0.85), lineWidth: 1)
            )
            .shadow(
                color: elevated ? AppTheme.cardShadow : .clear,
                radius: elevated ? 18 : 0,
                x: 0,
                y: elevated ? 8 : 0
            )
    }
}

extension View {
    func appCard(
        padding: CGFloat = 18,
        radius: CGFloat = 22,
        elevated: Bool = false
    ) -> some View {
        modifier(CardModifier(padding: padding, radius: radius, elevated: elevated))
    }

    func screenPadding() -> some View {
        padding(.horizontal, 20)
    }

    func hideKeyboardOnTap() -> some View {
        onTapGesture {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
        }
    }
}

struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = AppTheme.gold

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(Color(hex: 0x1A160D))
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(tint)
                    .overlay(
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.26), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
            )
            .shadow(color: tint.opacity(0.28), radius: 14, x: 0, y: 7)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(AppTheme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AppTheme.borderStrong, lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct CompactButtonStyle: ButtonStyle {
    var tint: Color = AppTheme.textPrimary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule(style: .continuous)
                    .fill(AppTheme.surface)
                    .overlay(Capsule().stroke(AppTheme.border, lineWidth: 1))
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

struct SectionTitle: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.goldDeep)
                    .buttonStyle(.plain)
            }
        }
    }
}

struct BadgeView: View {
    let text: String
    var color: Color = AppTheme.gold
    var filled: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(filled ? Color(hex: 0x17130A) : color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(filled ? color : color.opacity(0.12))
            )
    }
}

struct IconCircle: View {
    let systemName: String
    var tint: Color = AppTheme.gold
    var size: CGFloat = 42

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(tint.opacity(0.13))
            )
    }
}

struct DividerLine: View {
    var body: some View {
        Rectangle()
            .fill(AppTheme.border)
            .frame(height: 1)
    }
}
