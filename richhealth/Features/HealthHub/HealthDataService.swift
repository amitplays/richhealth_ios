import Foundation

/// Wraps /api/medical-data — unified symptoms + measurements endpoint.
/// Confirmed against ../richhealthbackend/routes/medicalDataRoutes.js
struct HealthDataService {
    private let client = APIClient()

    // showsLoader defaults true (HealthHub tab landing blocker). Richie passes false — it only
    // needs the counts for a subtitle and must not cover the chat with a full-screen loader.
    func getStats(showsLoader: Bool = true) async throws -> MedicalDataStats {
        // Message reads correctly for the one place it shows — the HealthHub tab landing.
        try await client.send(Endpoint(path: "/api/medical-data/stats", showsLoader: showsLoader, loaderMessage: "Loading your health data…"),
                              as: MedicalDataStats.self)
    }

    func list(type: String? = nil, page: Int = 1, limit: Int = 50) async throws -> MedicalDataListResponse {
        var query = [URLQueryItem(name: "page", value: "\(page)"),
                     URLQueryItem(name: "limit", value: "\(limit)")]
        if let type { query.append(URLQueryItem(name: "type", value: type)) }
        // Message reflects what's being loaded — symptoms vs measurements vs both.
        let message: String
        switch type {
        case "symptom":     message = "Loading your symptoms…"
        case "measurement": message = "Loading your measurements…"
        default:            message = "Loading your records…"
        }
        // showsLoader:false — symptoms/measurements lists load inside sheets (own skeletons).
        return try await client.send(Endpoint(path: "/api/medical-data", query: query, showsLoader: false, loaderMessage: message),
                                     as: MedicalDataListResponse.self)
    }

    func create(_ body: CreateMedicalDataRequest) async throws -> MedicalDataRecord {
        let response = try await client.send(
            Endpoint(path: "/api/medical-data", method: .post, body: try JSONEncoder().encode(body),
                     showsLoader: false, loaderMessage: "Saving your entry…"),
            as: MedicalDataSingleResponse.self
        )
        return response.data
    }

    func update(_ id: String, _ body: CreateMedicalDataRequest) async throws -> MedicalDataRecord {
        let response = try await client.send(
            Endpoint(path: "/api/medical-data/\(id)", method: .put, body: try JSONEncoder().encode(body),
                     showsLoader: false, loaderMessage: "Updating your entry…"),
            as: MedicalDataSingleResponse.self
        )
        return response.data
    }

    func delete(_ id: String) async throws {
        try await client.send(Endpoint(path: "/api/medical-data/\(id)", method: .delete, showsLoader: false, loaderMessage: "Deleting…"))
    }
}
