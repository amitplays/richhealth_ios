import Foundation

/// Wraps /api/insights/* — briefing, daily digest, dietary insights, NutriCheck.
/// Paths confirmed against ../richhealthbackend/routes/homeScreenRoutes.js
/// mounted at "/api/insights" (canonical) in index.js.
struct InsightsService {
    private let api = APIClient()

    // MARK: - Briefing

    func fetchBriefing() async throws -> BriefingResponse {
        try await api.send(Endpoint(path: "/api/insights/briefing", showsLoader: false, loaderMessage: "Preparing your daily briefing…"), as: BriefingResponse.self)
    }

    // MARK: - Daily Digest

    func fetchDailyDigest(city: String? = nil,
                          lat: Double? = nil,
                          lon: Double? = nil,
                          aqi: Int? = nil) async throws -> DailyDigestResponse {
        var q: [URLQueryItem] = []
        if let city { q.append(.init(name: "city", value: city)) }
        if let lat  { q.append(.init(name: "lat",  value: "\(lat)")) }
        if let lon  { q.append(.init(name: "lon",  value: "\(lon)")) }
        if let aqi  { q.append(.init(name: "aqi",  value: "\(aqi)")) }
        return try await api.send(Endpoint(path: "/api/insights/daily-digest", query: q, showsLoader: false, loaderMessage: "Loading your daily digest…"),
                                  as: DailyDigestResponse.self)
    }

    // MARK: - Dietary Insights

    func fetchDietaryInsights() async throws -> DietaryInsightsResponse {
        try await api.send(Endpoint(path: "/api/insights/dietary-insights", showsLoader: false, loaderMessage: "Loading dietary insights…"),
                           as: DietaryInsightsResponse.self)
    }

    func fetchDietaryInsightsHistory() async throws -> DietaryInsightsHistoryResponse {
        try await api.send(Endpoint(path: "/api/insights/dietary-insights/history", showsLoader: false, loaderMessage: "Loading history…"),
                           as: DietaryInsightsHistoryResponse.self)
    }

    // MARK: - NutriCheck

    func nutriCheck(foodItem: String,
                    previousChecks: [NutriCheckRequest.PreviousCheck] = []) async throws -> NutriCheckResponse {
        // Backend uses only last 3 previous checks for context
        let req = NutriCheckRequest(foodItem: foodItem,
                                    previousChecks: Array(previousChecks.suffix(3)))
        let body = try JSONEncoder().encode(req)
        return try await api.send(
            Endpoint(path: "/api/insights/nutri-check", method: .post, body: body, showsLoader: false, loaderMessage: "Analyzing this food…"),
            as: NutriCheckResponse.self)
    }

    func fetchNutriCheckHistory() async throws -> NutriCheckHistoryResponse {
        try await api.send(Endpoint(path: "/api/insights/nutri-check/history", showsLoader: false, loaderMessage: "Loading NutriCheck history…"),
                           as: NutriCheckHistoryResponse.self)
    }

    func submitNutriCheckFeedback(id: String, reaction: String?) async throws {
        struct Req: Encodable { let id: String; let reaction: String? }
        let body = try JSONEncoder().encode(Req(id: id, reaction: reaction))
        try await api.send(Endpoint(path: "/api/insights/nutri-check/feedback",
                                    method: .post, body: body, showsLoader: false))
    }

    func deleteNutriCheckEntry(id: String) async throws {
        try await api.send(Endpoint(path: "/api/insights/nutri-check/history/\(id)",
                                    method: .delete, showsLoader: false, loaderMessage: "Deleting…"))
    }
}
