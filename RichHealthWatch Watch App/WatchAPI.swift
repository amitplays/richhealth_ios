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
/// plus an access group so BOTH targets (and the widget) can read the same item.
/// DEBUG shortcut: paste a JWT into `debugToken` to test instantly without wiring sharing.
enum WatchKeychainStore {
    /// Set to "<YourTeamID>.ai.richhealth.shared" — must match the keychain-access-groups
    /// entitlement on the iOS app, the Watch app, AND the widget extension.
    static let accessGroup = "REPLACE_TEAMID.ai.richhealth.shared"
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
        case 429, 402: throw APIError.limitReached(Self.message(from: data))
        default:
            // Some backend limits reply 400 with a "limit" message — surface those as limitReached.
            let msg = Self.message(from: data)
            if http.statusCode == 400, let m = msg, m.lowercased().contains("limit") {
                throw APIError.limitReached(m)
            }
            throw APIError.server(http.statusCode, msg)
        }
    }

    private static func message(from data: Data) -> String? {
        struct Body: Decodable { let message: String? }
        return try? JSONDecoder().decode(Body.self, from: data).message
    }
}

// MARK: - ISO date helper

extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static func parse(_ s: String) -> Date? {
        ISO8601DateFormatter().date(from: s) ?? withFractionalSeconds.date(from: s)
    }
}

// MARK: - Observations (Apple Health vitals synced by the iPhone app)

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
        if let s = try? c.decode(String.self, forKey: .effectiveDateTime) {
            effectiveDateTime = ISO8601DateFormatter.parse(s)
        } else {
            effectiveDateTime = nil
        }
    }
}

struct ObservationsResponse: Decodable { let observations: [HealthObservation] }

struct HealthService {
    private let api = WatchAPIClient()

    private func fetch(_ type: String, days: Int, limit: Int) async throws -> [HealthObservation] {
        try await api.send(
            Endpoint(path: "/api/observations",
                     query: [.init(name: "type", value: type),
                             .init(name: "days", value: "\(days)"),
                             .init(name: "limit", value: "\(limit)")]),
            as: ObservationsResponse.self).observations   // backend sorts newest-first
    }

    /// Most-recent reading of a type in the last `days` (nil = no data, not an error).
    func latest(_ type: String, days: Int = 2) async throws -> HealthObservation? {
        try await fetch(type, days: days, limit: 200).first
    }

    /// Sum of a cumulative type (steps, active energy) over the last `days`.
    func total(_ type: String, days: Int = 1) async throws -> (sum: Double, asOf: Date?, source: String?)? {
        let items = try await fetch(type, days: days, limit: 1000)
        guard !items.isEmpty else { return nil }
        return (items.reduce(0) { $0 + $1.value }, items.first?.effectiveDateTime, items.first?.sourceName)
    }
}

// MARK: - Daily briefing (AI, app-open hook)

struct BriefingCard: Decodable, Identifiable {
    let priority: String?
    let title: String
    let points: [String]
    var id: String { title }
}
struct BriefingResponse: Decodable {
    let cards: [BriefingCard]
    let generatedAt: String?
    let source: String?
}

struct BriefingService {
    private let api = WatchAPIClient()
    func fetch() async throws -> BriefingResponse {
        try await api.send(Endpoint(path: "/api/insights/briefing"), as: BriefingResponse.self)
    }
}

// MARK: - NutriCheck

struct NutriCheckResponse: Decodable {
    let recommendation: String?   // strong_yes | yes | moderate | no | strong_no
    let reason: String?
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

// MARK: - Ask AI (Richie chat) — minimal one-shot shape

struct ChatSessionDTO: Decodable {
    let sessionId: String
    let title: String?
}
struct ChatMessageDTO: Decodable {
    let message: String
    let isFromAI: Bool?
}
struct SendMessageResponse: Decodable {
    let aiMessage: ChatMessageDTO
    let isLimitReached: Bool?
}

struct ChatService {
    private let api = WatchAPIClient()

    func createSession(title: String = "Watch") async throws -> String {
        struct Req: Encodable { let title: String; let dependentId: String? }
        let body = try JSONEncoder().encode(Req(title: title, dependentId: nil))
        return try await api.send(
            Endpoint(path: "/api/chat/sessions", method: .post, body: body),
            as: ChatSessionDTO.self).sessionId
    }

    func ask(_ text: String, sessionId: String) async throws -> String {
        struct Req: Encodable { let message: String; let modelType: String? }
        let body = try JSONEncoder().encode(Req(message: text, modelType: nil))
        let res = try await api.send(
            Endpoint(path: "/api/chat/sessions/\(sessionId)/messages", method: .post, body: body),
            as: SendMessageResponse.self)
        return res.aiMessage.message
    }
}
