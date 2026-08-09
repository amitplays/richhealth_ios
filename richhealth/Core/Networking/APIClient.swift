import Foundation

/// The ONE place network calls happen. Injects the Bearer token from Keychain, decodes JSON,
/// and maps status codes to typed APIError. Views never touch URLSession directly:
/// View -> ViewModel -> (per-domain Service) -> APIClient.
///
/// Debug logging: every request/response is printed to Xcode console in DEBUG builds.
/// Filter with "[RH]" in the console search bar.
struct APIClient {
    var session: URLSession = .shared
    var tokenProvider: () -> String? = { KeychainStore.shared.token }

    // nonisolated → the whole request AND the JSON decode run OFF the main actor (CLAUDE.md §1.5).
    // Decoding large launch responses (profile ~49KB, feed ~26KB, briefing, dietary, stats) on the
    // main thread was starving the keyboard's first-tap RTIInputSystem session → the 3s gate timeout.
    nonisolated func send<T: Decodable>(_ endpoint: Endpoint, as type: T.Type) async throws -> T {
        let data = try await send(endpoint)
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch {
            rhLog("✗ DECODE  \(endpoint.path) — \(error.localizedDescription)")
            throw APIError.decoding
        }
    }

    @discardableResult
    nonisolated func send(_ endpoint: Endpoint) async throws -> Data {
        // Branded UI blocker: on before the call, off on success OR any thrown error.
        // Opt-out per endpoint (e.g. chat send already shows a thinking bubble). Loader lives on
        // the MainActor, so hop there just to toggle it — the request/decode stay off-main.
        let loaderID: Int? = endpoint.showsLoader
            ? await MainActor.run { LoadingController.shared.begin(endpoint.loaderMessage) }
            : nil
        defer { if let loaderID { Task { @MainActor in LoadingController.shared.end(loaderID) } } }

        guard var components = URLComponents(url: APIConfig.baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidResponse
        }
        components.path = endpoint.path
        if !endpoint.query.isEmpty { components.queryItems = endpoint.query }
        guard let url = components.url else { throw APIError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body
        if endpoint.body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if endpoint.requiresAuth, let token = tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        rhLog("→ \(endpoint.method.rawValue)  \(endpoint.path)\(endpoint.body.map { "  (\($0.count)B body)" } ?? "")")

        let started = Date()
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch {
            rhLog("✗ TRANSPORT  \(endpoint.path)  (\(Self.ms(since: started))) — \(error.localizedDescription)")
            throw APIError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        let took = Self.ms(since: started)

        switch http.statusCode {
        case 200...299:
            rhLog("← \(http.statusCode)  \(endpoint.path)  (\(data.count) bytes, \(took))")
            return data
        case 401:
            rhLog("✗ 401  \(endpoint.path)  (\(took)) — unauthorized")
            throw APIError.unauthorized
        case 403:
            let msg = Self.message(from: data)
            rhLog("✗ 403  \(endpoint.path)  (\(took)) — \(msg ?? "not allowed")")
            throw APIError.notAllowed(msg)
        case 429:
            let msg = Self.message(from: data)
            rhLog("✗ 429  \(endpoint.path)  (\(took)) — \(msg ?? "limit reached")")
            throw APIError.limitReached(msg)
        default:
            let msg = Self.message(from: data)
            rhLog("✗ \(http.statusCode)  \(endpoint.path)  (\(took)) — \(msg ?? "server error")")
            throw APIError.server(status: http.statusCode, message: msg)
        }
    }

    /// Multipart upload for medical report files. Field name must be "file" per backend contract.
    nonisolated func sendMultipart<T: Decodable>(path: String, fields: [String: String], fileData: Data, fileName: String, mimeType: String, showsLoader: Bool = true, loaderMessage: String = "Uploading…", as type: T.Type) async throws -> T {
        let loaderID: Int? = showsLoader
            ? await MainActor.run { LoadingController.shared.begin(loaderMessage) }
            : nil
        defer { if let loaderID { Task { @MainActor in LoadingController.shared.end(loaderID) } } }

        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        let crlf = "\r\n"
        for (key, value) in fields {
            body += "--\(boundary)\(crlf)Content-Disposition: form-data; name=\"\(key)\"\(crlf)\(crlf)\(value)\(crlf)".data
        }
        body += "--\(boundary)\(crlf)Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\(crlf)Content-Type: \(mimeType)\(crlf)\(crlf)".data
        body += fileData
        body += "\(crlf)--\(boundary)--\(crlf)".data

        guard var components = URLComponents(url: APIConfig.baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidResponse
        }
        components.path = path
        guard let url = components.url else { throw APIError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        if let token = tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        rhLog("→ POST  \(path)  (multipart, \(body.count)B)")

        let started = Date()
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: request) }
        catch {
            rhLog("✗ TRANSPORT  \(path)  (\(Self.ms(since: started))) — \(error.localizedDescription)")
            throw APIError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        let took = Self.ms(since: started)
        switch http.statusCode {
        case 200...299:
            rhLog("← \(http.statusCode)  \(path)  (\(data.count) bytes, \(took))")
            do { return try JSONDecoder().decode(T.self, from: data) }
            catch {
                rhLog("✗ DECODE  \(path) — \(error.localizedDescription)")
                throw APIError.decoding
            }
        case 401:
            rhLog("✗ 401  \(path)  (\(took)) — unauthorized")
            throw APIError.unauthorized
        case 403:
            let msg = Self.message(from: data)
            rhLog("✗ 403  \(path)  (\(took)) — \(msg ?? "not allowed")")
            throw APIError.notAllowed(msg)
        case 429:
            let msg = Self.message(from: data)
            rhLog("✗ 429  \(path)  (\(took)) — \(msg ?? "limit reached")")
            throw APIError.limitReached(msg)
        default:
            let msg = Self.message(from: data)
            rhLog("✗ \(http.statusCode)  \(path)  (\(took)) — \(msg ?? "server error")")
            throw APIError.server(status: http.statusCode, message: msg)
        }
    }

    private static func message(from data: Data) -> String? {
        struct ErrorBody: Decodable { let message: String? }
        return try? JSONDecoder().decode(ErrorBody.self, from: data).message
    }

    // Elapsed response time as a compact string for the [RH] logs, e.g. "342ms".
    private static func ms(since start: Date) -> String {
        "\(Int(Date().timeIntervalSince(start) * 1000))ms"
    }
}

private extension String {
    nonisolated var data: Data { Data(utf8) }
}

/// Console log visible in Xcode debug output. Filter by "[RH]" in console search.
/// Format:  [RH] → METHOD  /path  (body)
///          [RH] ← STATUS  /path  (bytes)
///          [RH] ✗ STATUS  /path — message
func rhLog(_ message: String) {
    #if DEBUG
    print("[RH] \(message)")
    #endif
}
