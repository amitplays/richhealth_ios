import Foundation

/// Wraps /api/feed — paginated health feed items.
/// Confirmed against ../richhealthbackend/routes/feedRoutes.js mounted at "/api/feed".
/// Note: POST /api/feed and /batch are admin-only — not exposed here.
struct FeedService {
    private let api = APIClient()

    /// Returns paginated feed items. type: "podcast" | "article" | "news" | nil (all).
    func fetchFeed(page: Int = 1, limit: Int = 20, type: String? = nil) async throws -> FeedResponse {
        var q: [URLQueryItem] = [
            .init(name: "page",  value: "\(page)"),
            .init(name: "limit", value: "\(limit)")
        ]
        if let type { q.append(.init(name: "type", value: type)) }
        return try await api.send(Endpoint(path: "/api/feed", query: q, showsLoader: false, loaderMessage: "Loading your feed…"), as: FeedResponse.self)
    }

    /// Full detail for one item — includes aiReason field (may be absent with ?explain=0).
    func fetchFeedItem(id: String) async throws -> FeedItem {
        try await api.send(Endpoint(path: "/api/feed/\(id)", showsLoader: false, loaderMessage: "Loading article…"), as: FeedItem.self)
    }
}
