//
//  StoreKitService.swift
//  Airy
//
//  StoreKit 2: products, purchase, restore. Local-only.
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

actor StoreKitService {
    static let shared = StoreKitService()
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

    func purchase(_ product: Product) async throws -> StoreKit.Transaction? {
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

    func currentEntitlements() async -> [StoreKit.Transaction] {
        var txs: [StoreKit.Transaction] = []
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let tx) = result, tx.revocationDate == nil {
                txs.append(tx)
            }
        }
        return txs
    }

    /// Restores purchases. Returns transaction ID for local session. Throws if no Pro entitlement.
    func restore() async throws -> String? {
        try await AppStore.sync()
        let entitlements = await currentEntitlements()
        guard let latest = entitlements
            .filter({ $0.productID == Self.productId || $0.productID == Self.productIdYearly })
            .max(by: { $0.purchaseDate < $1.purchaseDate }) else {
            throw StoreKitError.noPurchasesFound
        }
        return String(latest.id)
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreKitError.notEntitled
        case .verified(let value):
            return value
        }
    }

    /// Checks if the user is eligible for the introductory (free trial) offer on a given product.
    func isEligibleForIntroOffer(for productId: String) async -> Bool {
        let products = try? await Product.products(for: [productId])
        guard let product = products?.first,
              let subscription = product.subscription else { return false }
        return await subscription.isEligibleForIntroOffer
    }

    /// Listens to Transaction.updates, finishes transactions, posts AiryEntitlementsDidChange.
    func startTransactionUpdatesListener() async {
        for await result in StoreKit.Transaction.updates {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.productID == Self.productId || transaction.productID == Self.productIdYearly else { continue }
            await transaction.finish()
            await MainActor.run {
                NotificationCenter.default.post(name: .airyEntitlementsDidChange, object: nil)
            }
        }
    }
}
