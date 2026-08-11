import Foundation

/// Calls the backend Apple-IAP verification endpoint.
/// POST /api/payment/apple/verify  { productId, transactionJWS }
/// → { success, plan, expiryDate, message }. Backend verifies the signed transaction
///   with Apple's App Store Server Library and flips the user to Pro.
struct PaymentService {
    private let api = APIClient()

    // MARK: - Plans catalog (display source of truth for BOTH platforms)

    /// One purchasable plan from GET /api/payment/plans (backend config/plans.js).
    /// Prices here are INR; on iOS the *charged/displayed* price comes from StoreKit
    /// (App Store Connect) — this is used for features / discount copy / most-popular.
    struct PaymentPlan: Decodable, Identifiable {
        let planId: Int
        let tierKey: String            // "plus" | "pro" | "ultra"
        let name: String               // "RichHealth Pro"
        let price: Int
        let originalPrice: Int?
        let discountPercent: Int?
        let discountMessage: String?
        let durationMonths: Int?
        let isMostPopular: Bool?
        let features: [String]
        var id: String { tierKey }
        /// StoreKit product id convention: richhealth.<tier>. Matches APPLE_PRODUCT_PLAN.
        var appleProductID: String { "richhealth.\(tierKey)" }
    }

    struct PlansResponse: Decodable {
        let plans: [PaymentPlan]
        let currentTier: String?
    }

    /// GET /api/payment/plans → the 3-plan catalog + the user's current tier.
    func fetchPlans() async throws -> PlansResponse {
        try await api.send(
            Endpoint(path: "/api/payment/plans", showsLoader: false),
            as: PlansResponse.self
        )
    }

    struct AppleVerifyResponse: Decodable {
        let success: Bool
        let plan: String?
        let expiryDate: Double?   // ms since epoch
        let message: String?
    }

    private struct AppleVerifyRequest: Encodable {
        let productId: String
        let transactionJWS: String
    }

    @discardableResult
    func verifyApple(productId: String, jws: String) async throws -> AppleVerifyResponse {
        let body = try JSONEncoder().encode(AppleVerifyRequest(productId: productId, transactionJWS: jws))
        return try await api.send(
            Endpoint(path: "/api/payment/apple/verify", method: .post, body: body, showsLoader: false, loaderMessage: "Confirming your purchase…"),
            as: AppleVerifyResponse.self
        )
    }
}
