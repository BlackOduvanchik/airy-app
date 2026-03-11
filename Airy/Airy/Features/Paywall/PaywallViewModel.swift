//
//  PaywallViewModel.swift
//  Airy
//  StoreKit 2 purchase/restore. Local-only, no backend.
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
    private let storeKit = StoreKitService.shared

    /// Check StoreKit entitlements; if already Pro, skip. Otherwise load products.
    func loadProducts() async {
        do {
            let entitlements = await storeKit.currentEntitlements()
            let hasPro = entitlements.contains { $0.productID == StoreKitService.productId || $0.productID == StoreKitService.productIdYearly }
            if hasPro {
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
            guard let _ = try await storeKit.purchase(product) else {
                return
            }
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
            _ = try await storeKit.restore()
            await MainActor.run { didSucceed = true }
        } catch StoreKitError.noPurchasesFound {
            await MainActor.run { errorMessage = (StoreKitError.noPurchasesFound as LocalizedError).errorDescription }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }
}
