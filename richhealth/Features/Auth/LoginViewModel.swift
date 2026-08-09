import Foundation
import Observation

@Observable @MainActor final class LoginViewModel {
    var email = ""
    var password = ""
    var isLoading = false
    var errorMessage: String?

    /// POST /api/auth/login via AuthManager. On success AppEnvironment.phase → .authenticated.
    func login(auth: AuthManager) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await auth.login(email: email, password: password)
        } catch let err as APIError {
            errorMessage = err.userMessage
        } catch {
            errorMessage = "Something went wrong. Please try again."
        }
    }
}
