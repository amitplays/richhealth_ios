import Foundation
import Security

// MARK: - Config

enum WatchAPIConfig {
    /// SAME base URL as iOS `APIConfig` — single source of truth for the backend.
    static let baseURL = URL(string: "https://richhealthbackend.vercel.app")!
}

// MARK: - Auth token (shared with the iPhone app)

/// Reads the JWT the iPhone app stores in the Keychain, so the watch is signed in
/// automatically. Mirrors iOS `KeychainStore` (service `ai.richhealth.auth`, account `jwt`)
/// but adds an access group so BOTH targets can see the same item.
///
/// TWO things must line up for this to work (see the wiring steps):
///   1. Both the iOS target and this Watch target list the SAME Keychain access group.
///   2. The iOS `KeychainStore` writes the token WITH that access group.
/// Until then, `token` is nil on the watch and the UI shows a "Sign in on iPhone" state.
///
/// DEBUG shortcut: paste a JWT into `debugToken` to test the whole watch app in minutes
/// against the live backend WITHOUT wiring Keychain sharing first. Leave it "" for release.
enum WatchKeychainStore {
    /// Set to your Team ID + suffix, e.g. "ABCDE12345.ai.richhealth.shared".
    /// Must exactly match the keychain-access-groups entitlement on BOTH targets.
    static let accessGroup = "REPLACE_TEAMID.ai.richhealth.shared"

    /// DEBUG-only manual token for instant testing. Paste your JWT here, run, done.
    static let debugToken = ""

    private static let service = "ai.richhealth.auth"
    private static let account = "jwt"

    static var token: String? {
        #if DEBUG
        if !debugToken.isEmpty { return debugToken }
        #endif
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if !accessGroup.hasPrefix("REPLACE_") {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Networking (self-contained mirror of iOS Endpoint/APIClient)

enum HTTPMethod: String { case get = "GET", post = "POST" }

struct Endpoint {
    var path: String
    var method: HTTPMethod = .get
    var query: [URLQueryItem] = []
    var body: Data? = nil
    var requiresAuth: Bool = true
}

enum APIError: Error, LocalizedError {
    case notSignedIn
    case limitReached(String?)
    case unauthorized
    case server(Int, String?)
    case transport(String)
    case decoding

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Sign in on your iPhone to continue."
        case .limitReached(let m): return m ?? "You've reached your limit. Upgrade on your iPhone."
        case .unauthorized: return "Session expired — open the app on your iPhone."
        case .server(_, let m): return m ?? "Something went wrong. Try again."
        case .transport: return "No connection. Check your network."
        case .decoding: return "Unexpected response."
        }
    }
}

struct WatchAPIClient {
    var session: URLSession = .shared
    var tokenProvider: @Sendable () -> String? = { WatchKeychainStore.token }

    func send<T: Decodable>(_ endpoint: Endpoint, as type: T.Type) async throws -> T {
        let data = try await send(endpoint)
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw APIError.decoding }
    }

    @discardableResult
    func send(_ endpoint: Endpoint) async throws -> Data {
        guard var components = URLComponents(url: WatchAPIConfig.baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.server(0, nil)
        }
        components.path = endpoint.path
        if !endpoint.query.isEmpty { components.queryItems = endpoint.query }
        guard let url = components.url else { throw APIError.server(0, nil) }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body
        if endpoint.body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if endpoint.requiresAuth {
            guard let token = tokenProvider() else { throw APIError.notSignedIn }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw APIError.transport(error.localizedDescription) }

        guard let http = response as? HTTPURLResponse else { throw APIError.server(0, nil) }
        switch http.statusCode {
        case 200...299: return data
        case 401: throw APIError.unauthorized
        case 429: throw APIError.limitReached(Self.message(from: data))
        default: throw APIError.server(http.statusCode, Self.message(from: data))
        }
    }

    private static func message(from data: Data) -> String? {
        struct Body: Decodable { let message: String? }
        return try? JSONDecoder().decode(Body.self, from: data).message
    }
}

// MARK: - Models (match backend response shapes)

/// One reading from GET /api/observations → `{ observations: [...] }` (backend Observation model).
/// Named `HealthObservation` to avoid clashing with the `Observation` framework module.
struct HealthObservation: Decodable {
    let type: String
    let value: Double
    let unit: String?
    let effectiveDateTime: Date?
    let sourceName: String?

    enum CodingKeys: String, CodingKey { case type, value, unit, effectiveDateTime, sourceName }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        value = try c.decode(Double.self, forKey: .value)
        unit = try? c.decode(String.self, forKey: .unit)
        sourceName = try? c.decode(String.self, forKey: .sourceName)
        // Backend sends ISO-8601 strings; decode leniently.
        if let s = try? c.decode(String.self, forKey: .effectiveDateTime) {
            effectiveDateTime = ISO8601DateFormatter().date(from: s)
                ?? ISO8601DateFormatter.withFractionalSeconds.date(from: s)
        } else {
            effectiveDateTime = nil
        }
    }
}

struct ObservationsResponse: Decodable { let observations: [HealthObservation] }

/// POST /api/insights/nutri-check → `{ recommendation, reason, ... }`.
struct NutriCheckResponse: Decodable {
    let recommendation: String?   // strong_yes | yes | moderate | no | strong_no
    let reason: String?
}

extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

// MARK: - Services

struct HealthService {
    private let api = WatchAPIClient()

    /// Latest reading of a type in the last `days`.
    func latest(_ type: String, days: Int = 1) async throws -> HealthObservation? {
        let res = try await api.send(
            Endpoint(path: "/api/observations",
                     query: [.init(name: "type", value: type),
                             .init(name: "days", value: "\(days)"),
                             .init(name: "limit", value: "200")]),
            as: ObservationsResponse.self)
        return res.observations.first   // backend sorts newest-first
    }

    /// Sum of a type's values over the last `days` (for cumulative metrics like steps/energy).
    func total(_ type: String, days: Int = 1) async throws -> (sum: Double, asOf: Date?, source: String?) {
        let res = try await api.send(
            Endpoint(path: "/api/observations",
                     query: [.init(name: "type", value: type),
                             .init(name: "days", value: "\(days)"),
                             .init(name: "limit", value: "1000")]),
            as: ObservationsResponse.self)
        let sum = res.observations.reduce(0) { $0 + $1.value }
        return (sum, res.observations.first?.effectiveDateTime, res.observations.first?.sourceName)
    }
}

struct NutriCheckService {
    private let api = WatchAPIClient()

    func check(_ foodItem: String) async throws -> NutriCheckResponse {
        struct Req: Encodable { let foodItem: String; let previousChecks: [String] }
        let body = try JSONEncoder().encode(Req(foodItem: foodItem, previousChecks: []))
        return try await api.send(
            Endpoint(path: "/api/insights/nutri-check", method: .post, body: body),
            as: NutriCheckResponse.self)
    }
}
