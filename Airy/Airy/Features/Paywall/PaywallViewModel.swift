//
//  PaywallViewModel.swift
//  Airy
//  StoreKit 2 purchase/restore and backend sync.
//

import SwiftUI
import StoreKit

struct ProductDisplay: Identifiable {
    let id: String
    let displayName: String
    let displayPrice: String
}

@Observable
@available(iOS 15.0, *)
final class PaywallViewModel {
    var products: [ProductDisplay] = []
    var isPurchasing = false
    var isRestoring = false
    var errorMessage: String?
    var didSucceed = false
    private let storeKit = StoreKitService()

    /// Load entitlements first; if already Pro, set didSucceed and skip purchase UI. Otherwise load StoreKit products.
    func loadProducts() async {
        do {
            let entitlements = try await APIClient.shared.getEntitlements()
            if entitlements.unlimitedAiAnalysis == true {
                await MainActor.run { didSucceed = true }
                return
            }
            let list = try await storeKit.loadProducts()
            await MainActor.run {
                products = list.map {
                    ProductDisplay(
                        id: $0.id,
                        displayName: $0.displayName,
                        displayPrice: String(describing: $0.displayPrice)
                    )
                }
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    func purchase() async {
        isPurchasing = true
        errorMessage = nil
        defer { Task { @MainActor in isPurchasing = false } }
        do {
            let list = try await storeKit.loadProducts()
            guard let product = list.first else {
                await MainActor.run { errorMessage = "Product not available" }
                return
            }
            guard let transaction = try await storeKit.purchase(product) else {
                return
            }
            let exp = transaction.expirationDate
            try await storeKit.syncToBackend(
                productId: transaction.productID,
                transactionId: String(transaction.id),
                expiresAt: exp
            )
            await MainActor.run { didSucceed = true }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    func restore() async {
        isRestoring = true
        errorMessage = nil
        defer { Task { @MainActor in isRestoring = false } }
        do {
            try await storeKit.restore()
            await MainActor.run { didSucceed = true }
        } catch StoreKitError.noPurchasesFound {
            await MainActor.run { errorMessage = (StoreKitError.noPurchasesFound as LocalizedError).errorDescription }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }
}
