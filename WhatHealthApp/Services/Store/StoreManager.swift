import Foundation
import StoreKit

@Observable
@MainActor
final class StoreManager {
    var products: [Product] = []
    var purchasedSubscription: Product?
    var isLoading: Bool = false
    var errorMessage: String?

    nonisolated(unsafe) private var transactionListenerTask: Task<Void, Error>?

    static let productIDs: Set<String> = [
        "com.whathealth.app.pro.monthly"
    ]

    init() {}

    deinit {
        transactionListenerTask?.cancel()
    }

    // MARK: - Load products

    func loadProducts() async {
        isLoading = true
        do {
            products = try await Product.products(for: StoreManager.productIDs)
                .sorted { $0.price < $1.price }
        } catch {
            errorMessage = "상품을 불러오는데 실패했습니다: \(error.localizedDescription)"
        }
        isLoading = false
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async {
        isLoading = true
        errorMessage = nil

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await verifyTransaction(transaction)
                await transaction.finish()
                purchasedSubscription = product
            case .pending:
                break
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = "구매 중 오류가 발생했습니다: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Restore purchases

    func restorePurchases() async {
        isLoading = true
        do {
            try await AppStore.sync()
            for await result in Transaction.currentEntitlements {
                if let transaction = try? checkVerified(result) {
                    await verifyTransaction(transaction)
                    await transaction.finish()
                }
            }
        } catch {
            errorMessage = "구매 복원 중 오류가 발생했습니다: \(error.localizedDescription)"
        }
        isLoading = false
    }

    // MARK: - Listen for transaction updates

    func listenForTransactions() {
        transactionListenerTask = Task.detached(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                do {
                    let transaction = try self.checkVerified(result)
                    await self.verifyTransaction(transaction)
                    await transaction.finish()
                } catch {
                    let errorMsg = error.localizedDescription
                    await MainActor.run {
                        self.errorMessage = "트랜잭션 처리 오류: \(errorMsg)"
                    }
                }
            }
        }
    }

    // MARK: - Verify with backend

    private func verifyTransaction(_ transaction: Transaction) async {
        guard AuthManager.shared.isAuthenticated else { return }

        let receiptData = transaction.jsonRepresentation.base64EncodedString()
        let requestBody = VerifyReceiptRequest(
            receiptData: receiptData,
            productId: transaction.productID
        )

        do {
            let response: VerifyReceiptResponse = try await APIClient.shared.post(
                endpoint: "/api/verify-receipt",
                body: requestBody
            )
            if response.success, let newTierRaw = response.newTier,
               let newTier = SubscriptionTier(rawValue: newTierRaw),
               let user = AuthManager.shared.currentUser {
                let updatedUser = AuthUser(
                    id: user.id,
                    email: user.email,
                    displayName: user.displayName,
                    subscriptionTier: newTier,
                    isPro: newTier == .pro
                )
                AuthManager.shared.currentUser = updatedUser
            }
        } catch {
            // Non-critical - transaction still counted locally
        }
    }

    // MARK: - Helpers

    nonisolated private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
}

enum StoreError: LocalizedError {
    case failedVerification

    var errorDescription: String? {
        switch self {
        case .failedVerification:
            return "구매 검증에 실패했습니다."
        }
    }
}
