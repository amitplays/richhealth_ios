import Foundation
import Observation

/// Owns auth state: Keychain token, current user, login/signup/logout.
/// Pro state is ALWAYS re-derived from the server — never copied from Android's buggy boolean.
/// Paths confirmed against ../richhealthbackend/index.js route mounting.
@Observable @MainActor final class AuthManager {
    private(set) var isAuthenticated = false
    private(set) var currentUser: UserProfile?
    private let api = APIClient()

    init() {
        // Optimistic: if a token exists treat as authenticated; bootstrap() confirms with the server.
        isAuthenticated = KeychainStore.shared.token != nil
    }

    // ─── Launch ───────────────────────────────────────────────────────────────

    /// GET /api/user/profile — validates the stored token. 401 → logout; network error → keep token.
    func bootstrap() async {
        guard KeychainStore.shared.token != nil else { isAuthenticated = false; return }
        do {
            // showsLoader:false — the splash screen IS the launch loading state; no overlay on top.
            let response = try await api.send(Endpoint(path: "/api/user/profile", showsLoader: false, loaderMessage: "Loading your profile…"), as: ProfileResponse.self)
            currentUser = response.user
            isAuthenticated = true
            rhLog("← bootstrap: authenticated as \(response.user.name ?? "(no name)"), id=\(response.user.id)")
        } catch APIError.unauthorized {
            rhLog("✗ bootstrap: 401 — token rejected, logging out")
            logout()
        } catch {
            isAuthenticated = true   // trust the stored token when offline
            rhLog("✗ bootstrap: network error (keeping token) — \(error.localizedDescription)")
        }
    }

    // ─── Login ────────────────────────────────────────────────────────────────

    /// POST /api/auth/login
    func login(email: String, password: String) async throws {
        let body = try JSONEncoder().encode(LoginRequest(email: email, password: password))
        let response = try await api.send(
            // showsLoader:false — the Log in button shows its own inline "Signing in…" spinner.
            Endpoint(path: "/api/auth/login", method: .post, body: body, requiresAuth: false, showsLoader: false, loaderMessage: "Signing in…"),
            as: AuthResponse.self
        )
        KeychainStore.shared.token = response.token
        isAuthenticated = true
        await loadProfile()
        Analytics.shared.track(.login)
    }

    // ─── Signup ───────────────────────────────────────────────────────────────

    /// POST /api/auth/signup — stores the token but does NOT set isAuthenticated.
    /// Call activateSession() after optional OTP verification (or skip).
    /// This keeps SignupView visible for the OTP step instead of auto-transitioning.
    func signup(_ request: SignupRequest) async throws {
        let body = try JSONEncoder().encode(request)
        let response = try await api.send(
            // showsLoader:false — SignupView shows its own inline button spinner.
            Endpoint(path: "/api/auth/signup", method: .post, body: body, requiresAuth: false, showsLoader: false, loaderMessage: "Creating your account…"),
            as: AuthResponse.self
        )
        KeychainStore.shared.token = response.token
        // isAuthenticated intentionally left false here.
    }

    /// Transitions to authenticated state — called after OTP verification or skip.
    func activateSession() async {
        isAuthenticated = true
        await loadProfile()
        Analytics.shared.track(.signupCompleted)
    }

    // ─── OTP ──────────────────────────────────────────────────────────────────

    /// POST /api/auth/send-otp
    func sendOTP(email: String) async throws -> OTPSentResponse {
        let body = try JSONEncoder().encode(SendOTPRequest(email: email))
        return try await api.send(
            Endpoint(path: "/api/auth/send-otp", method: .post, body: body, requiresAuth: false, showsLoader: false, loaderMessage: "Sending verification code…"),
            as: OTPSentResponse.self
        )
    }

    /// POST /api/auth/verify-otp
    func verifyOTP(email: String, otp: String) async throws -> OTPVerifyResponse {
        let body = try JSONEncoder().encode(VerifyOTPRequest(email: email, otp: otp))
        return try await api.send(
            Endpoint(path: "/api/auth/verify-otp", method: .post, body: body, requiresAuth: false, showsLoader: false, loaderMessage: "Verifying your code…"),
            as: OTPVerifyResponse.self
        )
    }

    // ─── Session ──────────────────────────────────────────────────────────────

    func logout() {
        Analytics.shared.track(.logout)   // fire while the token is still valid
        KeychainStore.shared.token = nil
        isAuthenticated = false
        currentUser = nil
        HealthKitManager.shared.clearSyncState()   // don't carry Apple-sync dedup ledger across accounts
    }

    /// Force-reload the profile. showsLoader:true only for the Profile tab's own load — post-edit
    /// and post-purchase refreshes stay silent (they happen behind a sheet / after their own UI).
    func refreshProfile(showsLoader: Bool = false) async { await loadProfile(showsLoader: showsLoader) }

    /// PUT /api/user/profile — updates only the supplied fields; refreshes currentUser on success.
    func updateProfile(_ request: UpdateProfileRequest) async throws {
        let body = try JSONEncoder().encode(request)
        let response = try await api.send(
            // showsLoader:false — profile edit happens in EditProfileSheet (its own saving state).
            Endpoint(path: "/api/user/profile", method: .put, body: body, showsLoader: false, loaderMessage: "Saving your profile…"),
            as: ProfileResponse.self
        )
        currentUser = response.user
    }

    /// GET /api/user/pro-access — always from server, never local logic (CLAUDE.md §7).
    /// showsLoader:false — runs on the Profile tab, which shows its own skeletons.
    func fetchProAccess() async throws -> ProAccess {
        return try await api.send(Endpoint(path: "/api/user/pro-access", showsLoader: false, loaderMessage: "Checking your plan…"), as: ProAccess.self)
    }

    /// GET /api/user/usage — plan tier + per-feature counts/limits.
    func fetchUsage() async throws -> UserUsageResponse {
        return try await api.send(Endpoint(path: "/api/user/usage", showsLoader: false, loaderMessage: "Checking your usage…"), as: UserUsageResponse.self)
    }

    /// Loads the user's profile (name, height, weight, …). showsLoader is opt-in: the Profile tab
    /// passes true so its "user values" load shows the branded loader; login/signup/paywall pass
    /// false (they have their own spinner or run behind a sheet).
    private func loadProfile(showsLoader: Bool = false) async {
        do {
            let response = try await api.send(
                Endpoint(path: "/api/user/profile", showsLoader: showsLoader, loaderMessage: "Loading your profile…"), as: ProfileResponse.self
            )
            let u = response.user
            currentUser = u
            let h = u.height.map { "\(Int($0))" } ?? "nil"
            let w = u.weight.map { String(format: "%.1f", $0) } ?? "nil"
            rhLog("← loadProfile: \(u.name ?? "(no name)"), gender=\(u.gender ?? "nil") height=\(h) weight=\(w)")
        } catch {
            rhLog("✗ loadProfile failed: \(error.localizedDescription)")
        }
    }
}
