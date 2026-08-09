import Foundation

/// Fetches and generates the AI-driven health analysis.
/// GET  /api/health/analysis           — current cached analysis + profile context.
/// POST /api/health/analysis/generate  — trigger fresh LLM analysis (up to ~120s).
final class HealthAnalysisService {
    private let client = APIClient()

    // Generate can take up to 2 minutes — use a 150s timeout session.
    private let longClient: APIClient = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 150
        config.timeoutIntervalForResource = 150
        return APIClient(session: URLSession(configuration: config))
    }()

    func fetch() async throws -> HealthAnalysisResponse {
        try await client.send(Endpoint(path: "/api/health/analysis", showsLoader: false, loaderMessage: "Loading your health analysis…"), as: HealthAnalysisResponse.self)
    }

    func generate() async throws -> HealthAnalysisResponse {
        try await longClient.send(
            Endpoint(path: "/api/health/analysis/generate", method: .post, showsLoader: false, loaderMessage: "Generating your health analysis…"),
            as: HealthAnalysisResponse.self
        )
    }
}
