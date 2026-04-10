import SwiftUI

@main
struct StopTypingApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showDictationActivation = false
    @State private var overlayRefreshToken = UUID()
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
                    .id(overlayRefreshToken)
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
                    // Refresh the overlay so it doesn't show stale content after a return
                    if showDictationActivation {
                        overlayRefreshToken = UUID()
                    }
                case .inactive:
                    break
                @unknown default:
                    break
                }
            }
            .onChange(of: hasCompletedOnboarding) { _, completed in
                // After finishing onboarding, land directly on the activation overlay
                if completed {
                    showDictationActivation = true
                }
            }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "stoptyping" else { return }

        switch url.host {
        case "activate", "dictate":
            if showDictationActivation {
                // Overlay already visible — force a fresh rebuild so .onAppear re-fires
                // and activateSession()'s self-healing path runs
                overlayRefreshToken = UUID()
            } else {
                showDictationActivation = true
            }
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
