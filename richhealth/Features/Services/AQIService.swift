import Foundation
import CoreLocation
import MapKit

/// Wraps /api/aqi/* — AQI data storage and retrieval.
/// Confirmed against ../richhealthbackend/routes/aqiRoutes.js mounted at "/api/aqi".
/// No 429 / 403 on any AQI endpoint.
struct AQIService {
    private let api = APIClient()

    /// Latest AQI reading for a city (aggregated across all users).
    func fetchLatest(city: String, state: String? = nil) async throws -> AQIData {
        var q = [URLQueryItem(name: "city", value: city)]
        if let state { q.append(.init(name: "state", value: state)) }
        let response = try await api.send(Endpoint(path: "/api/aqi/latest", query: q, showsLoader: false, loaderMessage: "Checking air quality…"),
                                          as: AQILatestResponse.self)
        return response.aqi
    }

    /// Time-series for trend chart. Array is newest-first — reverse before passing to Swift Charts.
    func fetchHistory(city: String, days: Int = 7) async throws -> [AQIData] {
        let q = [URLQueryItem(name: "city", value: city),
                 URLQueryItem(name: "days", value: "\(days)")]
        let response = try await api.send(Endpoint(path: "/api/aqi/history", query: q, showsLoader: false, loaderMessage: "Loading air quality trend…"),
                                          as: AQIHistoryResponse.self)
        return response.history
    }

    /// Store a new AQI reading for the current user's location.
    func storeAQI(_ req: AQIStoreRequest) async throws {
        let body = try JSONEncoder().encode(req)
        try await api.send(Endpoint(path: "/api/aqi/store", method: .post, body: body, showsLoader: false))
    }

    // MARK: - Location helpers (CoreLocation)

    /// One-shot reverse geocode: coordinates → (city, state). Returns nil on failure.
    /// Uses MKReverseGeocodingRequest (iOS 26 replacement for deprecated CLGeocoder).
    func reverseGeocode(latitude: Double, longitude: Double) async -> (city: String, state: String)? {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        guard let req = MKReverseGeocodingRequest(location: location) else { return nil }
        return await withCheckedContinuation { continuation in
            req.getMapItems { items, _ in
                guard let reps = items?.first?.addressRepresentations,
                      let city = reps.cityName, !city.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                let state = reps.regionName ?? ""
                continuation.resume(returning: (city, state))
            }
        }
    }
}
