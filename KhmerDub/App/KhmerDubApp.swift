import SwiftUI

@main
struct KhmerDubApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var localization = Localization(language: .deviceDefault)
    @StateObject private var projects = ProjectStore()
    @StateObject private var toasts = ToastCenter()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(localization)
                .environmentObject(projects)
                .environmentObject(toasts)
                .preferredColorScheme(settings.appearance.colorScheme)
                .tint(AppTheme.goldDeep)
                .onAppear {
                    localization.setLanguage(settings.appLanguage)
                    AppFiles.ensureDirectories()
                    AudioSession.configure()
                }
                .onChange(of: settings.appLanguage) { _, language in
                    localization.setLanguage(language)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active {
                        projects.flush()
                    }
                }
        }
    }
}
