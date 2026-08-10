import Foundation
import Observation

@Observable @MainActor final class LoginViewModel {
    var email = ""
    var password = ""
    var isLoading = false

    /// General/banner error (network, server, unknown).
    var errorMessage: String?
    /// Field-level errors shown under the email / password fields.
    var emailError: String?
    var passwordError: String?

    // TODO: Android's LoginActivity also offers biometric-at-login (BiometricHelper) and a
    //       Terms & Conditions gate before submitting. Both are intentionally out of scope here.

    /// Basic RFC-ish email format check — mirrors Android's `Patterns.EMAIL_ADDRESS`
    /// (used before hitting the API to avoid a pointless round-trip).
    private func isValidEmail(_ value: String) -> Bool {
        let pattern = "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    /// Validate inputs before calling the API. Populates field-level errors.
    /// Returns true when it's safe to proceed. Mirrors Android validateEmail()/validatePassword().
    private func validateInputs() -> Bool {
        emailError = nil
        passwordError = nil
        errorMessage = nil

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        var ok = true

        if trimmedEmail.isEmpty {
            emailError = "Email is required"
            ok = false
        } else if !isValidEmail(trimmedEmail) {
            emailError = "Invalid email format"
            ok = false
        }

        if password.isEmpty {
            passwordError = "Password is required"
            ok = false
        }

        return ok
    }

    /// POST /api/auth/login via AuthManager. On success AppEnvironment.phase → .authenticated.
    func login(auth: AuthManager) async {
        guard validateInputs() else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await auth.login(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
        } catch let err as APIError {
            applyError(err)
        } catch let err as URLError {
            // Defensive: URLSession errors normally arrive wrapped as APIError.transport,
            // but handle a raw URLError too so timeout/offline stay distinct.
            errorMessage = message(for: err.code)
        } catch {
            errorMessage = "Something went wrong. Please try again."
        }
    }

    /// Map a thrown APIError to a user-facing message, mirroring Android's handleLoginError():
    /// distinct copy for 401 vs server error vs timeout vs no-connection.
    private func applyError(_ err: APIError) {
        switch err {
        case .unauthorized:
            // 401 → bad credentials. Surface at the fields like Android does.
            let msg = "Invalid email or password."
            emailError = msg
            passwordError = msg
            errorMessage = msg
        case .server(let status, let serverMsg):
            errorMessage = serverMsg ?? (status >= 500
                ? "Server error. Please try again later."
                : "Login failed. Please try again.")
        case .transport(let description):
            // APIError.transport collapses the URLError into a localized string, so we
            // recover timeout vs no-connection by inspecting it. See message(forDescription:).
            errorMessage = message(forDescription: description)
        default:
            errorMessage = err.userMessage
        }
    }

    private func message(for code: URLError.Code) -> String {
        switch code {
        case .timedOut:
            return "Connection timeout. Please check your internet or try again later."
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return "No internet connection. Please check your network settings."
        default:
            return "Connection failed. Check your network."
        }
    }

    private func message(forDescription description: String) -> String {
        let lower = description.lowercased()
        if lower.contains("timed out") || lower.contains("timeout") {
            return "Connection timeout. Please check your internet or try again later."
        }
        if lower.contains("offline") || lower.contains("not connect")
            || lower.contains("network connection was lost")
            || lower.contains("internet connection") {
            return "No internet connection. Please check your network settings."
        }
        return "Connection failed. Check your network."
    }
}
