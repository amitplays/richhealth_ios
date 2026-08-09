import Foundation

/// Wraps /api/users/doctor/doctor/* — patient-side doctor search and connection management.
/// Confirmed against ../richhealthbackend/routes/doctorRoutes.js
/// mounted at "/api/users/doctor" in index.js.
///
/// Note: paths contain /doctor/doctor/ — the route file is mounted at /api/users/doctor
/// and each handler adds an additional /doctor/ prefix. This is intentional per the backend code.
/// No 429 or 403 on any endpoint — all authenticated users can search and connect.
struct DoctorService {
    private let api = APIClient()

    // MARK: - Search

    func searchDoctors(query: String) async throws -> [DoctorSearchResult] {
        let q = [URLQueryItem(name: "query", value: query)]
        return try await api.send(
            Endpoint(path: "/api/users/doctor/doctor/search", query: q, showsLoader: false, loaderMessage: "Searching doctors…"),
            as: [DoctorSearchResult].self)
    }

    // MARK: - Connection management (patient → doctor)

    func sendConnectionRequest(doctorId: String, message: String? = nil) async throws {
        struct Req: Encodable { let doctorId: String; let message: String? }
        let body = try JSONEncoder().encode(Req(doctorId: doctorId, message: message))
        try await api.send(Endpoint(path: "/api/users/doctor/doctor/request",
                                    method: .post, body: body, showsLoader: false, loaderMessage: "Sending request…"))
    }

    func cancelConnectionRequest(doctorId: String) async throws {
        struct Req: Encodable { let doctorId: String }
        let body = try JSONEncoder().encode(Req(doctorId: doctorId))
        try await api.send(Endpoint(path: "/api/users/doctor/doctor/cancel",
                                    method: .post, body: body, showsLoader: false, loaderMessage: "Cancelling request…"))
    }

    // MARK: - Lists

    func fetchConnectedDoctors() async throws -> [DoctorSearchResult] {
        try await api.send(Endpoint(path: "/api/users/doctor/doctor/connected", showsLoader: false, loaderMessage: "Loading your doctors…"),
                           as: [DoctorSearchResult].self)
    }

    func fetchPendingRequests() async throws -> [DoctorPendingRecord] {
        try await api.send(Endpoint(path: "/api/users/doctor/doctor/pending", showsLoader: false, loaderMessage: "Loading requests…"),
                           as: [DoctorPendingRecord].self)
    }

    /// Incoming requests initiated by doctors (returns email + name + status only).
    func fetchIncomingRequests() async throws -> [IncomingDoctorRequest] {
        let response = try await api.send(Endpoint(path: "/api/users/doctor/doctor/requests", showsLoader: false, loaderMessage: "Loading requests…"),
                                          as: IncomingDoctorRequestsResponse.self)
        return response.incomingDoctorRequests
    }

    /// Respond to a doctor-initiated incoming request.
    func respondToRequest(email: String, accept: Bool) async throws {
        struct Req: Encodable { let email: String; let accept: Bool }
        let body = try JSONEncoder().encode(Req(email: email, accept: accept))
        try await api.send(Endpoint(path: "/api/users/doctor/doctor/respond",
                                    method: .post, body: body, showsLoader: false, loaderMessage: "Updating request…"))
    }
}
