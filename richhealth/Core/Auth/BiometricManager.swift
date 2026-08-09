import LocalAuthentication
import Foundation
import Observation

/// Manages Face ID / Touch ID lock. Owned by AppEnvironment; observed by RootView overlay.
@Observable @MainActor
final class BiometricManager {

    var isLocked = false
    private(set) var canUseBiometrics: Bool

    init() {
        canUseBiometrics = LAContext().canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics, error: nil
        )
    }

    /// Call when app moves to .background — locks if the user has the setting enabled.
    func lockIfEnabled() {
        guard UserDefaults.standard.bool(forKey: "rh.biometricEnabled"),
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
