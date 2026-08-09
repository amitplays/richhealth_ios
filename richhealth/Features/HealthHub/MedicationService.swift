import Foundation

/// Wraps /api/health/medications.
/// Confirmed against ../richhealthbackend/routes/medicationRoutes.js
struct MedicationService {
    private let client = APIClient()

    // showsLoader defaults true (HealthHub tab landing blocker). Richie passes false (subtitle only).
    func getStats(showsLoader: Bool = true) async throws -> MedicationStats {
        // Unified message so the HealthHub landing reads consistently regardless of which
        // concurrent /stats call begins last (both feed the same landing loader).
        try await client.send(Endpoint(path: "/api/health/medications/stats", showsLoader: showsLoader, loaderMessage: "Loading your health data…"), as: MedicationStats.self)
    }

    func list(status: String = "all", page: Int = 1, limit: Int = 50) async throws -> MedicationsListResponse {
        let query = [URLQueryItem(name: "status", value: status),
                     URLQueryItem(name: "page", value: "\(page)"),
                     URLQueryItem(name: "limit", value: "\(limit)")]
        // showsLoader:false — medication list loads inside the Medications sheet (own skeleton).
        return try await client.send(Endpoint(path: "/api/health/medications", query: query, showsLoader: false, loaderMessage: "Loading your medications…"), as: MedicationsListResponse.self)
    }

    func create(_ body: CreateMedicationRequest) async throws -> MedicationRecord {
        let response = try await client.send(
            Endpoint(path: "/api/health/medications", method: .post, body: try JSONEncoder().encode(body), showsLoader: false, loaderMessage: "Saving medication…"),
            as: MedicationSingleResponse.self
        )
        return response.medication
    }

    func update(_ id: String, _ body: CreateMedicationRequest) async throws -> MedicationRecord {
        let response = try await client.send(
            Endpoint(path: "/api/health/medications/\(id)", method: .put, body: try JSONEncoder().encode(body), showsLoader: false, loaderMessage: "Updating medication…"),
            as: MedicationSingleResponse.self
        )
        return response.medication
    }

    /// PATCH /api/health/medications/:id/discontinue — sets endDate + isOngoing=false.
    /// Sends optional discontinueDate and reason in body (Android: body { discontinueDate, reason }).
    func discontinue(_ id: String, reason: String?, date: Date?) async throws -> MedicationRecord {
        struct Body: Encodable {
            let discontinueDate: String?
            let reason: String?
        }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let body = try JSONEncoder().encode(Body(
            discontinueDate: date.map { fmt.string(from: $0) },
            reason: reason?.isEmpty == false ? reason : nil
        ))
        let response = try await client.send(
            Endpoint(path: "/api/health/medications/\(id)/discontinue", method: .patch, body: body, showsLoader: false, loaderMessage: "Updating medication…"),
            as: MedicationSingleResponse.self
        )
        return response.medication
    }

    func delete(_ id: String) async throws {
        try await client.send(Endpoint(path: "/api/health/medications/\(id)", method: .delete, showsLoader: false, loaderMessage: "Removing medication…"))
    }
}
