import Foundation

/// Calls the backend Apple-IAP verification endpoint.
/// POST /api/payment/apple/verify  { productId, transactionJWS }
/// → { success, plan, expiryDate, message }. Backend verifies the signed transaction
///   with Apple's App Store Server Library and flips the user to Pro.
struct PaymentService {
    private let api = APIClient()

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
