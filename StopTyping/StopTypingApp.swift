import SwiftUI

@main
struct StopTypingApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showDictationActivation = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                if hasCompletedOnboarding {
                    MainTabView()
                } else {
                    OnboardingView {
                        hasCompletedOnboarding = true
                        UserDefaults.standard.removeObject(forKey: "onboardingCurrentPage")
                        var settings = UserSettings.load()
                        settings.hasCompletedOnboarding = true
                        settings.save()
                    }
                }

                if showDictationActivation {
                    DictationOverlayView(onClose: {
                        withAnimation { showDictationActivation = false }
                    })
                    .zIndex(100)
                }
            }
            .onOpenURL { url in
                handleDeepLink(url)
            }
            .onChange(of: scenePhase) { _, newPhase in
                let service = BackgroundDictationService.shared
                switch newPhase {
                case .background:
                    service.handleBackground()
                case .active:
                    service.handleForeground()
                case .inactive:
                    break
                @unknown default:
                    break
                }
            }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "stoptyping" else { return }

        switch url.host {
        case "activate", "dictate":
            showDictationActivation = true
        default:
            break
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "mic.fill")
                }

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}

#Preview {
    MainTabView()
}
