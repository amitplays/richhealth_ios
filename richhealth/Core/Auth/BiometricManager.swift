import LocalAuthentication
import Foundation
import Observation

/// Manages the app lock (Face ID / Touch ID, or the device passcode as a fallback).
/// Owned by AppEnvironment; observed by RootView overlay. Not every user has biometrics
/// enrolled, but almost everyone has a passcode — so the lock uses device-owner
/// authentication, which presents biometrics when available and passcode otherwise.
@Observable @MainActor
final class BiometricManager {

    // UserDefaults keys — the single source of truth for the app-lock pref
    // (device-local only, matching ProfileViewModel; never synced to the server).
    private static let enabledKey = "rh.biometricEnabled"
    private static let offeredKey = "rh.biometricPromptShown"

    var isLocked = false
    /// True if the device has an enrolled biometric (Face ID / Touch ID).
    private(set) var canUseBiometrics: Bool
    /// True if the device can authenticate the owner at all — biometrics OR a passcode.
    /// This is the real gate for offering the lock: passcode-only users qualify too.
    private(set) var canDeviceAuthenticate: Bool
    /// Human label for how the lock verifies on THIS device:
    /// "Face ID" / "Touch ID" when enrolled, else "your passcode".
    private(set) var biometryLabel: String

    init() {
        let ctx = LAContext()
        canUseBiometrics = ctx.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics, error: nil
        )
        // deviceOwnerAuthentication == biometrics if available, else the passcode.
        canDeviceAuthenticate = ctx.canEvaluatePolicy(
            .deviceOwnerAuthentication, error: nil
        )
        switch ctx.biometryType {
        case .faceID:  biometryLabel = "Face ID"
        case .touchID: biometryLabel = "Touch ID"
        default:       biometryLabel = "your passcode"
        }
    }

    /// Whether the app lock is currently turned on (device-local pref).
    var isBiometricEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    /// True when we should show the one-time post-login setup offer: the device can
    /// authenticate the owner (biometrics OR passcode), the lock isn't already on, and
    /// we haven't offered before. Mirrors Android's LoginActivity.offerBiometricSetup gate.
    var shouldOfferSetup: Bool {
        canDeviceAuthenticate
            && !isBiometricEnabled
            && !UserDefaults.standard.bool(forKey: Self.offeredKey)
    }

    /// User accepted the one-time offer: verify identity, and on success turn the lock on.
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
              canDeviceAuthenticate else { return }
        isLocked = true
    }

    /// Authenticate to unlock. Called automatically on .active, or on tap from lock screen.
    /// Uses device-owner auth: iOS shows Face ID/Touch ID with a passcode fallback, or the
    /// passcode directly on devices without biometrics.
    func authenticate() async {
        let ctx = LAContext()
        do {
            let ok = try await ctx.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Verify your identity to access your health data"
            )
            if ok { isLocked = false }
            // userCancel / systemCancel → stay locked; user sees the retry button.
        } catch {
            isLocked = false // unknown hardware/config error — fail open rather than lock out.
        }
    }

    /// Call when enabling the lock — verifies Face ID/Touch ID/passcode works before saving.
    /// Returns false if the user cancels or the device can't authenticate the owner.
    func verifyForSetup() async -> Bool {
        guard canDeviceAuthenticate else { return false }
        let ctx = LAContext()
        return (try? await ctx.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Set up app lock for RichHealth"
        )) ?? false
    }
}
