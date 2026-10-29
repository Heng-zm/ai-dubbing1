import SwiftUI

enum AppTab: Hashable {
    case home
    case projects
    case voice
    case settings
}

struct RootView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var toasts: ToastCenter

    var body: some View {
        ZStack {
            if settings.hasCompletedOnboarding {
                MainTabView()
                    .transition(.opacity)
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: settings.hasCompletedOnboarding)
        .overlay(alignment: .top) {
            if let message = toasts.message {
                ToastView(text: message)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(20)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: toasts.message)
    }
}

struct MainTabView: View {
    @EnvironmentObject private var loc: Localization
    @State private var selectedTab: AppTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(selectedTab: $selectedTab)
                .tag(AppTab.home)
                .tabItem {
                    Label(loc.t("tab.home"), systemImage: "house.fill")
                }

            ProjectsView(selectedTab: $selectedTab)
                .tag(AppTab.projects)
                .tabItem {
                    Label(loc.t("tab.projects"), systemImage: "rectangle.stack.fill")
                }

            VoiceLabView(selectedTab: $selectedTab)
                .tag(AppTab.voice)
                .tabItem {
                    Label(loc.t("tab.voice"), systemImage: "waveform.circle.fill")
                }

            SettingsView()
                .tag(AppTab.settings)
                .tabItem {
                    Label(loc.t("tab.settings"), systemImage: "gearshape.fill")
                }
        }
    }
}
