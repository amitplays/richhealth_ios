import Foundation

enum APIError: Error, Equatable {
    case invalidResponse
    case unauthorized              // 401 → force logout / login
    case notAllowed(String?)       // 403 → upgrade required (surface paywall)
    case limitReached(String?)     // 429 → usage limit hit (surface paywall)
    case server(status: Int, message: String?)
    case decoding
    case transport(String)
}

extension APIError {
    /// User-facing message — used in error labels and alerts.
    var userMessage: String {
        switch self {
        case .unauthorized:          return "Invalid email or password."
        case .notAllowed(let msg):   return msg ?? "Access not allowed."
        case .limitReached(let msg): return msg ?? "Usage limit reached. Upgrade to continue."
        case .server(_, let msg):    return msg ?? "Server error. Please try again."
        case .decoding:              return "Unexpected server response. Please try again."
        case .transport:             return "Connection failed. Check your network."
        case .invalidResponse:       return "Invalid response from server."
        }
    }
}
