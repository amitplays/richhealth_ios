import Foundation

enum HTTPMethod: String {
    case get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE"
}

struct Endpoint {
    var path: String                 // e.g. "/api/auth/login" — confirm against ../richhealthbackend/routes
    var method: HTTPMethod = .get
    var query: [URLQueryItem] = []
    var body: Data? = nil
    var requiresAuth: Bool = true
    // Set false to skip the global branded loader (e.g. chat send — it has its own thinking bubble).
    var showsLoader: Bool = true
    // Context shown on the branded loader while this call is in flight. Keep it specific and honest.
    var loaderMessage: String = "Loading…"
}
