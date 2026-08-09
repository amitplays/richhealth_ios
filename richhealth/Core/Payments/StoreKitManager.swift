import Foundation
import StoreKit

/// StoreKit 2 In-App Purchase for RichHealth Pro.
/// Product IDs must match App Store Connect AND the backend map (APPLE_PRODUCT_PLAN):
///   richhealth.plus → plus · richhealth.pro → pro · richhealth.ultra → ultra
/// Purchase runs on-device; the signed transaction is sent to the backend, which verifies it
/// with Apple and activates Pro. Shared singleton so the renewal listener runs once.
@MainActor @Observable
final class StoreKitManager {
    static let shared = StoreKitManager()

    /// Order matters — displayed plus → pro → ultra.
    static let productIDs = ["richhealth.plus", "richhealth.pro", "richhealth.ultra"]

    private(set) var products: [Product] = []
    private(set) var isLoading = false
    var isPurchasing = false
    var errorMessage: String?

    private let service = PaymentService()
    private var updatesTask: Task<Void, Never>?

    private init() {
        // Catch renewals / Ask-to-Buy approvals / cross-device transactions for the app's lifetime.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { continue }
                if let transaction = try? self.checkVerified(update) {
                    _ = await self.sendToBackend(productID: transaction.productID, jws: update.jwsRepresentation)
                    await transaction.finish()
                }
            }
        }
    }

    func loadProducts() async {
        guard products.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await Product.products(for: Self.productIDs)
            products = Self.productIDs.compactMap { id in fetched.first { $0.id == id } }
            if products.isEmpty { errorMessage = "No plans are available right now." }
        } catch {
            errorMessage = "Couldn't load plans. \(error.localizedDescription)"
        }
    }

    /// Returns true once the backend confirms Pro is active.
    func purchase(_ product: Product) async -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                let activated = await sendToBackend(productID: transaction.productID,
                                                    jws: verification.jwsRepresentation)
                await transaction.finish()
                return activated
            case .userCancelled:
                return false
            case .pending:
                errorMessage = "Your purchase is pending approval."
                return false
            @unknown default:
                return false
            }
        } catch {
            errorMessage = "Purchase failed. \(error.localizedDescription)"
            return false
        }
    }

    /// Re-sends the user's active entitlement to the backend (new device / reinstall).
    func restore() async -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }
        var restored = false
        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result),
               await sendToBackend(productID: transaction.productID, jws: result.jwsRepresentation) {
                restored = true
            }
        }
        if !restored { errorMessage = "No active subscription found to restore." }
        return restored
    }

    // MARK: - Helpers

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error): throw error
        case .verified(let safe):       return safe
        }
    }

    private func sendToBackend(productID: String, jws: String) async -> Bool {
        do {
            let resp = try await service.verifyApple(productId: productID, jws: jws)
            return resp.success
        } catch {
            errorMessage = "Couldn't activate Pro on the server. \(error.localizedDescription)"
            return false
        }
    }
}
