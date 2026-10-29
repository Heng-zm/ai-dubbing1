import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var loc: Localization
    @State private var page = 0

    private let pages: [(symbol: String, titleKey: String, bodyKey: String, accent: Color)] = [
        ("waveform.badge.mic", "onboarding.1.title", "onboarding.1.body", AppTheme.gold),
        ("person.wave.2.fill", "onboarding.2.title", "onboarding.2.body", AppTheme.teal),
        ("lock.shield.fill", "onboarding.3.title", "onboarding.3.body", AppTheme.indigo)
    ]

    var body: some View {
        ZStack {
            AppTheme.heroGradient
                .ignoresSafeArea()
            RadialGradient(
                colors: [AppTheme.gold.opacity(0.2), .clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 400
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { index in
                        OnboardingPage(
                            symbol: pages[index].symbol,
                            title: loc.t(pages[index].titleKey),
                            message: loc.t(pages[index].bodyKey),
                            accent: pages[index].accent
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.25), value: page)

                dots
                    .padding(.top, 4)
                    .padding(.bottom, 20)
                footer
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
        }
        .preferredColorScheme(.dark)
        .onChange(of: settings.appLanguage) { _, language in
            loc.setLanguage(language)
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(AppTheme.goldGradient)
                        .frame(width: 36, height: 36)
                    Image(systemName: "character.book.closed.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color(hex: 0x20180A))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(loc.t("app.name"))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(loc.t("app.tagline"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Text(loc.t("onboarding.language"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                ForEach(AppLanguage.allCases) { language in
                    Button {
                        settings.appLanguage = language
                        loc.setLanguage(language)
                        Haptics.selection()
                    } label: {
                        HStack(spacing: 5) {
                            Text(language.flag)
                            Text(language.nativeName)
                                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(settings.appLanguage == language ? Color(hex: 0x20180A) : .white.opacity(0.75))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            Capsule(style: .continuous)
                                .fill(settings.appLanguage == language ? AppTheme.gold : Color.white.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(pages.indices, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index == page ? AppTheme.gold : Color.white.opacity(0.22))
                    .frame(width: index == page ? 22 : 7, height: 7)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: page)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 13) {
            HStack(spacing: 12) {
                Button(loc.t("common.skip")) {
                    complete()
                }
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .buttonStyle(.plain)

                Spacer()

                Button {
                    if page < pages.count - 1 {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            page += 1
                        }
                        Haptics.selection()
                    } else {
                        complete()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(loc.t(page == pages.count - 1 ? "onboarding.start" : "common.next"))
                        Image(systemName: page == pages.count - 1 ? "sparkles" : "arrow.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0x20180A))
                    .padding(.horizontal, 22)
                    .frame(height: 52)
                    .background(
                        Capsule(style: .continuous)
                            .fill(AppTheme.goldGradient)
                    )
                    .shadow(color: AppTheme.gold.opacity(0.28), radius: 18, x: 0, y: 8)
                }
                .buttonStyle(PressableButtonStyle())
            }

            Text(loc.t("onboarding.privacy"))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.38))
        }
        .padding(.bottom, 10)
    }

    private func complete() {
        Haptics.success()
        settings.completeOnboarding()
    }
}

private struct OnboardingPage: View {
    let symbol: String
    let title: String
    let message: String
    let accent: Color

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 16)
            ZStack {
                Circle()
                    .fill(accent.opacity(0.12))
                    .frame(width: 236, height: 236)
                Circle()
                    .stroke(accent.opacity(0.2), lineWidth: 1)
                    .frame(width: 196, height: 196)
                Circle()
                    .fill(accent.opacity(0.09))
                    .frame(width: 140, height: 140)
                Image(systemName: symbol)
                    .font(.system(size: 62, weight: .light))
                    .foregroundStyle(accent)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 13) {
                Text(title)
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.75)
                Text(message)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.64))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
            }
            Spacer(minLength: 20)
        }
    }
}
