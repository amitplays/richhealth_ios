import Foundation
import Observation

/// App-wide session state injected via `.environment(appEnv)`.
/// Owns AuthManager and BiometricManager so all views access them from one environment object.
@Observable @MainActor final class AppEnvironment {
    enum Phase: Equatable { case launching, unauthenticated, authenticated }

    let auth = AuthManager()
    let biometric = BiometricManager()

    /// Bump after any cross-screen data mutation so observing views can refresh cheaply.
    var invalidationToken = UUID()

    private var isLaunching = true

    var phase: Phase {
        if isLaunching { return .launching }
        return auth.isAuthenticated ? .authenticated : .unauthenticated
    }

    /// Minimum time the splash stays up — gives the brand a beat and lets the background warmup
    /// get a head start before the first screen appears. Never blocks on slow network.
    private static let minSplashSeconds: TimeInterval = 2.5

    /// Validates the stored Keychain token once at app launch. Called by RootView.task.
    /// Kicks off a background cache warmup so Services tab data is ready on first navigation.
    func bootstrap() async {
        let start = Date()
        await auth.bootstrap()
        // Start the StoreKit transaction listener at launch (not only when the paywall opens)
        // so auto-renewals / Ask-to-Buy / cross-device purchases are verified with the backend.
        _ = StoreKitManager.shared
        if auth.isAuthenticated {
            Task { await startupDataWarmup() }  // runs during the splash floor AND continues after
        }
        // Hold the splash for a minimum duration; subtract time already spent on the auth check
        // so we never add delay on a slow network — only pad a fast launch.
        let elapsed = Date().timeIntervalSince(start)
        if elapsed < Self.minSplashSeconds {
            try? await Task.sleep(nanoseconds: UInt64((Self.minSplashSeconds - elapsed) * 1_000_000_000))
        }
        isLaunching = false
    }

    /// Pre-warms SessionCache during splash for the expensive, cacheable dashboard reads so the
    /// Services tab renders instantly on first navigation (briefing/digest = same-day; dietary = 8h).
    /// Only fetches on a cache miss, and SAVES the result (the ViewModel is now cache-first, so a
    /// warm entry means zero re-fetch of these slow calls — briefing ~26s, dietary ~46s).
    private func startupDataWarmup() async {
        let svc = InsightsService()
        await withTaskGroup(of: Void.self) { group in
            if SessionCache.loadToday(BriefingResponse.self, key: "briefing") == nil {
                group.addTask { if let r = try? await svc.fetchBriefing() { SessionCache.save(r, key: "briefing") } }
            }
            if SessionCache.loadToday(DailyDigestResponse.self, key: "digest") == nil {
                group.addTask { if let r = try? await svc.fetchDailyDigest() { SessionCache.save(r, key: "digest") } }
            }
            if SessionCache.load(DietaryInsightsResponse.self, key: "dietary", maxAge: 8 * 3600) == nil {
                group.addTask { if let r = try? await svc.fetchDietaryInsights() { SessionCache.save(r, key: "dietary") } }
            }
        }
    }

    func markDataChanged() { invalidationToken = UUID() }
}
