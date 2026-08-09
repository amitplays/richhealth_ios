import Foundation

enum APIConfig {
    /// SINGLE source of truth for the base URL. Android hardcoded this in ~13 places — never do that.
    /// Value mirrors ../richhealth_android/app/src/main/java/Utils/ApiConfig.java.
    static let baseURL = URL(string: "https://richhealthbackend.vercel.app")!
}
