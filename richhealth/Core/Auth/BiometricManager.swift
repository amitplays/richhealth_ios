import LocalAuthentication
import Foundation
import Observation

/// Manages Face ID / Touch ID lock. Owned by AppEnvironment; observed by RootView overlay.
@Observable @MainActor
final class BiometricManager {

    // UserDefaults keys — the single source of truth for the biometric-lock pref
    // (device-local only, matching ProfileViewModel; never synced to the server).
    private static let enabledKey = "rh.biometricEnabled"
    private static let offeredKey = "rh.biometricPromptShown"

    var isLocked = false
    private(set) var canUseBiometrics: Bool
    /// Human label for the device's biometry ("Face ID" / "Touch ID" / "biometric lock").
    private(set) var biometryLabel: String

    init() {
        let ctx = LAContext()
        canUseBiometrics = ctx.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics, error: nil
        )
        switch ctx.biometryType {
        case .faceID: biometryLabel = "Face ID"
        case .touchID: biometryLabel = "Touch ID"
        default: biometryLabel = "biometric lock"
        }
    }

    /// Whether biometric lock is currently turned on (device-local pref).
    var isBiometricEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    /// True when we should show the one-time post-login setup offer: the device can do
    /// biometrics, it isn't already on, and we haven't offered before. Mirrors Android's
    /// LoginActivity.offerBiometricSetup gate (canAuthenticate + !enabled + !prompted).
    var shouldOfferSetup: Bool {
        canUseBiometrics
            && !isBiometricEnabled
            && !UserDefaults.standard.bool(forKey: Self.offeredKey)
    }

    /// User accepted the one-time offer: verify biometrics, and on success turn the lock on.
    /// Records the offer as shown either way so it never re-prompts. Returns whether it enabled.
    @discardableResult
    func enableFromOffer() async -> Bool {
        let ok = await verifyForSetup()
        if ok { UserDefaults.standard.set(true, forKey: Self.enabledKey) }
        UserDefaults.standard.set(true, forKey: Self.offeredKey)
        return ok
    }

    /// User declined the one-time offer — record it as shown so we don't ask again.
    func declineOffer() {
        UserDefaults.standard.set(true, forKey: Self.offeredKey)
    }

    /// Call when app moves to .background — locks if the user has the setting enabled.
    func lockIfEnabled() {
        guard UserDefaults.standard.bool(forKey: Self.enabledKey),
              canUseBiometrics else { return }
        isLocked = true
    }

    /// Authenticate to unlock. Called automatically on .active, or on tap from lock screen.
    func authenticate() async {
        let ctx = LAContext()
        do {
            let ok = try await ctx.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Verify your identity to access your health data"
            )
            if ok { isLocked = false }
            // userCancel / systemCancel → stay locked; user sees retry button
        } catch let err as LAError {
            if err.code == .biometryLockout {
                // Device locked out of biometry — fall back to passcode
                let fallback = LAContext()
                if let ok = try? await fallback.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: "Enter your passcode to access RichHealth"
                ), ok {
                    isLocked = false
                }
            }
        } catch {
            isLocked = false // unknown hardware error — fail open
        }
    }

    /// Call when the toggle turns ON — verifies Face ID works before saving.
    /// Returns false if the user cancels or the device can't authenticate.
    func verifyForSetup() async -> Bool {
        guard canUseBiometrics else { return false }
        let ctx = LAContext()
        return (try? await ctx.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Set up biometric lock for RichHealth"
        )) ?? false
    }
}
