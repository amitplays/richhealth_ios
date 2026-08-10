import Foundation

/// Wraps /api/user/relationship/* for incoming family (relative) requests.
/// Confirmed against ../richhealthbackend/routes/userRoutes.js. Mirrors the
/// Doctor incoming-request flow. Uses the singular /api/user prefix, matching the
/// app's other working relationship calls (request/delete/cancel/edit).
struct FamilyService {
    private let api = APIClient()

    /// Pending incoming family connection requests (accept/reject candidates).
    func fetchIncomingRequests() async throws -> [IncomingFamilyRequest] {
        let response = try await api.send(
            Endpoint(path: "/api/user/relationship/requests", showsLoader: false),
            as: FamilyRequestsResponse.self)
        // status defaults to "pending"; treat missing as pending too.
        return response.incomingRequests.filter { ($0.status ?? "pending").lowercased() == "pending" }
    }

    /// Accept (true) or reject (false) a relative-initiated request, keyed by sender email.
    func respondToRequest(email: String, accept: Bool) async throws {
        struct Req: Encodable { let email: String; let accept: Bool }
        let body = try JSONEncoder().encode(Req(email: email, accept: accept))
        try await api.send(Endpoint(path: "/api/user/relationship/respond",
                                    method: .post, body: body, showsLoader: false))
    }
}
