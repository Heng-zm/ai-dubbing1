import SwiftUI

struct HomeView: View {
    @Binding var selectedTab: AppTab
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var loc: Localization
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var toasts: ToastCenter

    @State private var path: [UUID] = []
    @State private var showImport = false

    private var readiness: VoiceReadiness {
        TTSService.shared.readiness(settings: settings)
    }

    private var recentProjects: [DubProject] {
        Array(store.sortedProjects.prefix(3))
    }

    private var voiceClipCount: Int {
        store.projects.reduce(0) { $0 + $1.translatedCount }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                ScreenBackground()
                    .ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        greeting
                        hero
                        stats
                        if recentProjects.isEmpty {
                            emptyRecent
                        } else {
                            recent
                        }
                        voiceCard
                        tipCard
                        howItWorks
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 28)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                StudioView(projectID: id)
            }
            .sheet(isPresented: $showImport) {
                ImportView { id in
                    path.append(id)
                }
                .environmentObject(settings)
                .environmentObject(loc)
                .environmentObject(store)
                .environmentObject(toasts)
            }
        }
    }

    private var greeting: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(loc.t("home.greeting"))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.goldDeep)
                Text(loc.t("home.subtitle"))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                    .minimumScaleFactor(0.8)
            }
            Spacer()
            ZStack {
                Circle()
                    .fill(AppTheme.surface)
                    .frame(width: 46, height: 46)
                    .overlay(Circle().stroke(AppTheme.border, lineWidth: 1))
                Text("🇰🇭")
                    .font(.system(size: 22))
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                Text(loc.t("home.hero.eyebrow"))
            }
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(AppTheme.gold)
            .tracking(1.3)

            Text(loc.t("home.hero.title"))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineSpacing(1)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: true)

            Text(loc.t("home.hero.body"))
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.64))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    showImport = true
                    Haptics.tap()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "plus")
                        Text(loc.t("home.newDub"))
                    }
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0x20180A))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Capsule().fill(AppTheme.goldGradient))
                }
                .buttonStyle(PressableButtonStyle())

                Button {
                    openDemo()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "play.fill")
                        Text(loc.t("home.demo"))
                    }
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Capsule().fill(Color.white.opacity(0.11)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                }
                .buttonStyle(PressableButtonStyle())
            }
            .padding(.top, 2)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(AppTheme.heroGradient)
        )
        .overlay(alignment: .topTrailing) {
            WaveformView(
                values: WaveformFallback.demo(count: 24),
                tint: AppTheme.gold.opacity(0.65),
                idleTint: AppTheme.gold.opacity(0.22)
            )
            .frame(width: 130, height: 46)
            .rotationEffect(.degrees(-8))
            .padding(.top, 20)
            .padding(.trailing, 16)
            .opacity(0.9)
            .allowsHitTesting(false)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 22, x: 0, y: 12)
    }

    private var stats: some View {
        HStack(spacing: 10) {
            StatTile(
                value: "\(store.projectCount)",
                label: loc.t("home.stats.projects"),
                symbol: "rectangle.stack",
                tint: AppTheme.gold
            )
            StatTile(
                value: "\(voiceClipCount)",
                label: loc.t("home.stats.voices"),
                symbol: "waveform",
                tint: AppTheme.teal
            )
            StatTile(
                value: String(format: "%.1f", store.totalDubSeconds / 60),
                label: loc.t("home.stats.minutes"),
                symbol: "clock",
                tint: AppTheme.indigo
            )
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 11) {
            SectionTitle(
                title: loc.t("home.recent"),
                actionTitle: loc.t("home.seeAll"),
                action: { selectedTab = .projects }
            )
            VStack(spacing: 0) {
                ForEach(Array(recentProjects.enumerated()), id: \.element.id) { index, project in
                    NavigationLink(value: project.id) {
                        ProjectRowView(project: project)
                            .padding(.vertical, 11)
                    }
                    .buttonStyle(.plain)
                    if index < recentProjects.count - 1 {
                        DividerLine()
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AppTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(AppTheme.border, lineWidth: 1)
                    )
            )
        }
    }

    private var emptyRecent: some View {
        VStack(alignment: .leading, spacing: 11) {
            SectionTitle(title: loc.t("home.recent"))
            EmptyStateView(
                symbol: "rectangle.stack.badge.plus",
                title: loc.t("home.empty.title"),
                body: loc.t("home.empty.body"),
                actionTitle: loc.t("home.newDub"),
                action: { showImport = true }
            )
            .appCard()
        }
    }

    private var voiceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardIconTitle(
                symbol: readiness.isReady ? "waveform.circle.fill" : "waveform.badge.exclamationmark",
                title: loc.t("home.voiceCard.title"),
                subtitle: readiness.isReady
                    ? loc.t("home.voiceCard.ready")
                    : loc.t("home.voiceCard.needsSetup"),
                tint: readiness.isReady ? AppTheme.teal : AppTheme.warning
            )
            VStack(spacing: 8) {
                voiceRow(
                    title: loc.t("home.voiceCard.azure"),
                    ready: readiness.azureReady,
                    symbol: "cloud.fill"
                )
                voiceRow(
                    title: loc.t("home.voiceCard.apple"),
                    ready: readiness.appleReady,
                    symbol: "apple.logo"
                )
            }
            Button {
                selectedTab = .voice
            } label: {
                Text(loc.t("home.voiceCard.check"))
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .appCard()
    }

    private func voiceRow(title: String, ready: Bool, symbol: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ready ? AppTheme.teal : AppTheme.textTertiary)
                .frame(width: 18)
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
            Spacer()
            Image(systemName: ready ? "checkmark.circle.fill" : "minus.circle")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(ready ? AppTheme.teal : AppTheme.textTertiary)
        }
    }

    private var tipCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AppTheme.gold)
                .frame(width: 34, height: 34)
                .background(Circle().fill(AppTheme.gold.opacity(0.12)))
            VStack(alignment: .leading, spacing: 4) {
                Text(loc.t("home.tip.title"))
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(loc.t("home.tip.body"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .appCard(padding: 15)
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 11) {
            SectionTitle(title: loc.t("home.works.title"))
            VStack(spacing: 0) {
                ForEach(1...4, id: \.self) { index in
                    HStack(spacing: 12) {
                        Text("\(index)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: 0x20180A))
                            .frame(width: 25, height: 25)
                            .background(Circle().fill(AppTheme.goldGradient))
                        Text(loc.t("home.works.\(index)"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                        if index < 4 {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(AppTheme.textTertiary.opacity(0.5))
                        }
                    }
                    .padding(.vertical, 10)
                    if index < 4 {
                        DividerLine()
                    }
                }
            }
            .padding(.horizontal, 15)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AppTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(AppTheme.border, lineWidth: 1)
                    )
            )
        }
    }

    private func openDemo() {
        let project = DemoProjectFactory.make(localization: loc)
        store.upsert(project, immediate: true)
        toasts.show(loc.t("home.demoCreated"))
        Haptics.success()
        path.append(project.id)
    }
}
