//
//  StoreKitService.swift
//  Airy
//
//  StoreKit 2: products, purchase, restore, sync to backend.
//

import Foundation
import StoreKit

enum StoreKitError: LocalizedError {
    case notEntitled
    case noProduct
    case noPurchasesFound

    var errorDescription: String? {
        switch self {
        case .notEntitled: return "Purchase could not be verified."
        case .noProduct: return "Product not available."
        case .noPurchasesFound: return "No purchases found for this Apple ID."
        }
    }
}

extension Notification.Name {
    static let airyEntitlementsDidChange = Notification.Name("AiryEntitlementsDidChange")
}

@available(iOS 15.0, *)
actor StoreKitService {
    nonisolated(unsafe) static let shared = StoreKitService()
    static let productId = "airy_pro_monthly"
    static let productIdYearly = "airy_pro_yearly"

    func loadProducts() async throws -> [Product] {
        let ids = [Self.productId]
        return try await Product.products(for: Set(ids))
    }

    /// Loads both monthly and yearly Pro products for onboarding/paywall offer.
    func loadAllProProducts() async throws -> [Product] {
        return try await Product.products(for: Set([Self.productId, Self.productIdYearly]))
    }

    func purchase(_ product: Product) async throws -> Transaction? {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            return transaction
        case .userCancelled, .pending:
            return nil
        @unknown default:
            return nil
        }
    }

    func currentEntitlements() async -> [Transaction] {
        var txs: [Transaction] = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result {
                txs.append(tx)
            }
        }
        return txs
    }

    func syncToBackend(productId: String?, transactionId: String?, expiresAt: Date?) async throws {
        let expiresAtStr = expiresAt.map { ISO8601DateFormatter().string(from: $0) }
        _ = try await APIClient.shared.syncBilling(
            productId: productId,
            transactionId: transactionId,
            expiresAt: expiresAtStr
        )
    }

    /// Restores purchases; syncs latest Pro entitlement to backend. Throws `StoreKitError.noPurchasesFound` if no Pro entitlement exists.
    func restore() async throws {
        try await AppStore.sync()
        let entitlements = await currentEntitlements()
        guard let latest = entitlements
            .filter({ $0.productID == Self.productId || $0.productID == Self.productIdYearly })
            .max(by: { $0.purchaseDate < $1.purchaseDate }) else {
            throw StoreKitError.noPurchasesFound
        }
        let exp = latest.expirationDate
        try await syncToBackend(
            productId: latest.productID,
            transactionId: String(latest.id),
            expiresAt: exp
        )
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreKitError.notEntitled
        case .verified(let value):
            return value
        }
    }

    /// Call from app launch when user is logged in. Listens to Transaction.updates, syncs to backend, and posts AiryEntitlementsDidChange.
    func startTransactionUpdatesListener() async {
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.productID == Self.productId || transaction.productID == Self.productIdYearly else { continue }
            do {
                try await syncToBackend(
                    productId: transaction.productID,
                    transactionId: String(transaction.id),
                    expiresAt: transaction.expirationDate
                )
                await transaction.finish()
                await MainActor.run {
                    NotificationCenter.default.post(name: .airyEntitlementsDidChange, object: nil)
                }
            } catch {
                // Log and continue; do not finish transaction so it may be retried
                continue
            }
        }
    }
}
