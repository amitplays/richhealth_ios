import SwiftUI

enum AppTab: Hashable {
    case richie, healthHub, services, profile

    var analyticsName: String {
        switch self {
        case .richie:    return "richie"
        case .healthHub: return "health_hub"
        case .services:  return "services"
        case .profile:   return "profile"
        }
    }
}

/// Root shell: routes to splash/login/tabs based on AppEnvironment.phase.
/// Handles biometric lock via scenePhase observer — no tab or feature needs to care about it.
struct RootView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: AppTab = .richie
    @State private var loader = LoadingController.shared

    var body: some View {
        Group {
            switch appEnv.phase {
            case .launching:
                SplashView()

            case .unauthenticated:
                NavigationStack {
                    LoginView()
                }

            case .authenticated:
                tabShell
                    .overlay {
                        if appEnv.biometric.isLocked {
                            BiometricLockScreen {
                                Task { await appEnv.biometric.authenticate() }
                            }
                            .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.25), value: appEnv.biometric.isLocked)
            }
        }
        // Global branded loader — one mount here covers every screen; APIClient toggles it.
        .overlay {
            if loader.isActive {
                BrandedLoaderView(message: loader.message)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: loader.isActive)
        .animation(.easeInOut(duration: 0.3), value: appEnv.phase)
        .task { await appEnv.bootstrap() }
        .onChange(of: scenePhase) { _, new in
            if new == .background {
                appEnv.biometric.lockIfEnabled()
            }
            // Auto-sync Apple Health each time the app comes to the foreground (throttled internally).
            if new == .active, appEnv.phase == .authenticated {
                Task { await HealthKitManager.shared.autoSyncIfNeeded() }
            }
        }
    }

    @ViewBuilder private var tabShell: some View {
        TabView(selection: $selectedTab) {
            Tab("Richie", systemImage: "sparkles", value: AppTab.richie) { RichieView() }
            Tab("Health Hub", systemImage: "heart.text.square", value: AppTab.healthHub) { HealthHubView() }
            Tab("Services", systemImage: "square.grid.2x2", value: AppTab.services) { ServicesHomeView() }
            Tab("Profile", systemImage: "person.crop.circle", value: AppTab.profile) { ProfileView() }
        }
        .onChange(of: selectedTab, initial: true) { _, tab in
            Analytics.shared.track(.screenView, ["tab": tab.analyticsName])
        }
    }
}

#Preview { RootView().environment(AppEnvironment()) }
