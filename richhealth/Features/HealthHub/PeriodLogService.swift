import Foundation

/// Wraps /api/health/period-logs.
/// Confirmed against ../richhealthbackend/routes/periodLogRoutes.js
struct PeriodLogService {
    private let client = APIClient()

    func list(page: Int = 1, limit: Int = 50) async throws -> PeriodLogsListResponse {
        let query = [URLQueryItem(name: "page", value: "\(page)"),
                     URLQueryItem(name: "limit", value: "\(limit)")]
        return try await client.send(Endpoint(path: "/api/health/period-logs", query: query, showsLoader: false, loaderMessage: "Loading your cycle log…"), as: PeriodLogsListResponse.self)
    }

    func create(_ body: CreatePeriodLogRequest) async throws -> PeriodLogRecord {
        struct Wrapper: Decodable { let data: PeriodLogRecord }
        let response = try await client.send(
            Endpoint(path: "/api/health/period-logs", method: .post, body: try JSONEncoder().encode(body), showsLoader: false, loaderMessage: "Saving your log…"),
            as: Wrapper.self
        )
        return response.data
    }

    func update(_ id: String, _ body: CreatePeriodLogRequest) async throws -> PeriodLogRecord {
        let response = try await client.send(
            Endpoint(path: "/api/health/period-logs/\(id)", method: .put, body: try JSONEncoder().encode(body), showsLoader: false, loaderMessage: "Updating your log…"),
            as: PeriodLogSingleResponse.self
        )
        guard let record = response.record else { throw APIError.decoding }
        return record
    }

    func delete(_ id: String) async throws {
        try await client.send(Endpoint(path: "/api/health/period-logs/\(id)", method: .delete, showsLoader: false, loaderMessage: "Deleting…"))
    }
}
