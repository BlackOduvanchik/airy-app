//
//  PendingReviewViewModel.swift
//  Airy
//
//  Local-only: fetch/confirm/reject from SwiftData.
//

import SwiftUI

/// Pre-computed display data for a single review card.
/// Equatable so SwiftUI can skip re-rendering unchanged cards.
struct ReviewCardData: Identifiable, Equatable {
    let id: String
    let merchant: String
    let amount: Double
    let currency: String
    let date: String
    let time: String?
    let isIncome: Bool
    let categoryLabel: String
    let subcategoryLabel: String?
    let categoryIcon: String
    let isLowConfidence: Bool
    let confidencePercent: Double?
    let duplicateSeenText: String?
    /// Non-nil when merchant matches an existing subscription AND amount matches — pre-fill toggle in edit.
    let matchedSubscriptionInterval: String?
}

@Observable
final class PendingReviewViewModel {
    var pending: [PendingTransaction] = []
    var cardDataList: [ReviewCardData] = []
    var isLoading = true
    var errorMessage: String?

    func load() async {
        await MainActor.run { isLoading = true }
        defer { Task { @MainActor in isLoading = false } }
        await MainActor.run {
            pending = LocalDataStore.shared.fetchPendingTransactions()
            cardDataList = buildCardDataList()
        }
    }

    func confirm(id: String, overrides: ConfirmPendingOverrides? = nil, rememberMerchant: Bool = true) async {
        let confirmedMerchant = await MainActor.run { pending.first { $0.id == id }?.decodedPayload?.merchant }
        let ok = await MainActor.run { LocalDataStore.shared.confirmPending(id: id, overrides: overrides, rememberMerchant: rememberMerchant) }
        if ok {
            await MainActor.run {
                pending.removeAll { $0.id == id }
                cardDataList.removeAll { $0.id == id }
                if rememberMerchant, let merchant = confirmedMerchant, overrides?.category != nil || overrides?.subcategoryId != nil {
                    updateCardsForMerchant(merchant)
                }
            }
        } else {
            await MainActor.run { errorMessage = "Failed to confirm" }
        }
    }

    func reject(id: String) async {
        await MainActor.run { LocalDataStore.shared.rejectPending(id: id) }
        await MainActor.run {
            pending.removeAll { $0.id == id }
            cardDataList.removeAll { $0.id == id }
        }
    }

    /// Remove items from the displayed list immediately (for smooth swipe animation). Call before persistReject.
    @MainActor
    func removePendingLocally(ids: [String]) {
        pending.removeAll { ids.contains($0.id) }
        cardDataList.removeAll { ids.contains($0.id) }
    }

    /// Persist deletion without reloading the list (list already updated via removePendingLocally).
    func persistReject(id: String) async {
        await MainActor.run { LocalDataStore.shared.rejectPending(id: id) }
    }

    func confirmAll(rememberRules: [String: Bool]) async {
        for item in pending {
            let remember = rememberRules[item.id] ?? true
            _ = await MainActor.run { LocalDataStore.shared.confirmPending(id: item.id, overrides: nil, rememberMerchant: remember) }
        }
        await load()
    }

    func rejectAll() async {
        for item in pending {
            await MainActor.run { LocalDataStore.shared.rejectPending(id: item.id) }
        }
        await load()
    }

    // MARK: - Targeted Card Update

    /// Update only cards matching the given merchant with fresh category from MerchantCategoryRuleStore.
    @MainActor
    private func updateCardsForMerchant(_ merchant: String) {
        let merchantLower = merchant.lowercased()
        guard let newCategoryId = MerchantCategoryRuleStore.shared.categoryId(for: merchant) else { return }
        let newLabel = Self.categoryLabel(for: merchant, categoryId: newCategoryId)
        let newIcon = CategoryIconHelper.iconName(categoryId: newCategoryId)
        let newSubLabel: String? = {
            guard let subId = MerchantCategoryRuleStore.shared.subcategoryId(for: merchant) else { return nil }
            return SubcategoryStore.forParent(newCategoryId).first { $0.id == subId }?.name
        }()
        cardDataList = cardDataList.map { card in
            guard card.merchant.lowercased() == merchantLower else { return card }
            return ReviewCardData(
                id: card.id,
                merchant: card.merchant,
                amount: card.amount,
                currency: card.currency,
                date: card.date,
                time: card.time,
                isIncome: card.isIncome,
                categoryLabel: newLabel,
                subcategoryLabel: newSubLabel,
                categoryIcon: newIcon,
                isLowConfidence: card.isLowConfidence,
                confidencePercent: card.confidencePercent,
                duplicateSeenText: card.duplicateSeenText,
                matchedSubscriptionInterval: card.matchedSubscriptionInterval
            )
        }
    }

    // MARK: - Card Data Builder

    @MainActor
    private func buildCardDataList() -> [ReviewCardData] {
        // Fetch saved transactions ONCE for duplicate detection
        let savedTransactions = LocalDataStore.shared.fetchTransactions(limit: 200)

        // Pre-compute duplicate texts for all pending in a single pass
        let duplicateTexts = computeAllDuplicateTexts(savedTransactions: savedTransactions)

        // Fetch existing subscriptions ONCE for subscription matching
        let existingSubscriptions = LocalDataStore.shared.subscriptionsFromTransactions()

        return pending.compactMap { item -> ReviewCardData? in
            guard let p = item.decodedPayload else { return nil }
            let merchant = p.merchant ?? "Transaction"
            let effectiveCategoryId = MerchantCategoryRuleStore.shared.categoryId(for: merchant) ?? p.category
            let effectiveSubcategoryId = MerchantCategoryRuleStore.shared.subcategoryId(for: merchant) ?? p.subcategory
            let effectiveIcon: String = {
                if let cid = effectiveCategoryId, !cid.isEmpty, cid != "other" {
                    return CategoryIconHelper.iconName(categoryId: cid)
                }
                return Self.categoryIcon(for: merchant)
            }()
            let isLowConfidence = Self.isLowConfidenceMerchant(merchant) || (item.confidence ?? 1) < 0.6
            let isIncome = (p.type ?? "expense").lowercased() == "income"

            // Match against existing subscriptions by merchant + amount
            let matchedInterval: String? = {
                let amt = p.amountOriginal ?? 0
                return existingSubscriptions.first { sub in
                    sub.merchant.lowercased() == merchant.lowercased() && abs(sub.amount - amt) < 0.01
                }?.interval
            }()

            let subcategoryName: String? = {
                guard let catId = effectiveCategoryId, let subId = effectiveSubcategoryId else { return nil }
                return SubcategoryStore.forParent(catId).first { $0.id == subId }?.name
                    ?? SubcategoryStore.forParent(catId).first { $0.name == subId }?.name
            }()

            return ReviewCardData(
                id: item.id,
                merchant: merchant,
                amount: p.amountOriginal ?? 0,
                currency: p.currencyOriginal ?? "USD",
                date: p.transactionDate ?? "",
                time: p.transactionTime,
                isIncome: isIncome,
                categoryLabel: Self.categoryLabel(for: merchant, categoryId: effectiveCategoryId),
                subcategoryLabel: subcategoryName,
                categoryIcon: effectiveIcon,
                isLowConfidence: isLowConfidence,
                confidencePercent: isLowConfidence ? (item.confidence ?? 0.45) * 100 : nil,
                duplicateSeenText: duplicateTexts[item.id],
                matchedSubscriptionInterval: matchedInterval
            )
        }
    }

    @MainActor
    private func computeAllDuplicateTexts(savedTransactions: [Transaction]) -> [String: String] {
        var results: [String: String] = [:]

        for item in pending {
            guard let p = item.decodedPayload,
                  let amt = p.amountOriginal,
                  let merchant = p.merchant, !merchant.isEmpty else { continue }

            if p.probableDuplicateOfId != nil {
                results[item.id] = "Possible duplicate of a saved transaction"
                continue
            }

            let pendingDateStr = (p.transactionDate ?? "").prefix(10).description
            let merchantLower = merchant.lowercased()

            // Check against saved transactions
            var found = false
            for tx in savedTransactions {
                guard abs(tx.amountOriginal - amt) < 0.01,
                      tx.transactionDate.prefix(10).description == pendingDateStr else { continue }
                let txMerchant = (tx.merchant ?? "").lowercased()
                guard txMerchant.contains(merchantLower) || merchantLower.contains(txMerchant) else { continue }
                results[item.id] = "Возможно дубликат"
                found = true
                break
            }
            if found { continue }

            // Check against other pending transactions
            for other in pending where other.id != item.id {
                guard let pl = other.decodedPayload,
                      let pam = pl.amountOriginal,
                      abs(pam - amt) < 0.01,
                      let pd = pl.transactionDate,
                      String(pd.prefix(10)) == pendingDateStr,
                      let pm = pl.merchant, !pm.isEmpty else { continue }
                let pmLower = pm.lowercased()
                guard pmLower.contains(merchantLower) || merchantLower.contains(pmLower) else { continue }
                results[item.id] = "Возможно дубликат"
                break
            }
        }
        return results
    }

    // MARK: - Static Helpers (moved from view for pre-computation)

    private static func isLowConfidenceMerchant(_ merchant: String) -> Bool {
        merchant.contains("_") || merchant.count < 3 || merchant == "Transaction"
    }

    private static func categoryLabel(for merchant: String, categoryId: String?) -> String {
        if let cat = categoryId, !cat.isEmpty, cat != "other" {
            if let c = CategoryStore.byId(cat) { return c.name }
        }
        let m = merchant.lowercased()
        if m.contains("coffee") || m.contains("food") || m.contains("restaurant") || m.contains("grocery") { return "Food & Drink" }
        if m.contains("gas") || m.contains("shell") || m.contains("uber") || m.contains("taxi") || m.contains("transit") { return "Transportation" }
        if m.contains("grocery") || m.contains("whole foods") || m.contains("market") { return "Groceries" }
        if m.contains("netflix") || m.contains("spotify") || m.contains("hulu") || m.contains("entertainment") { return "Entertainment" }
        return "Other"
    }

    private static func categoryIcon(for merchant: String) -> String {
        let m = merchant.lowercased()
        if m.contains("coffee") || m.contains("food") || m.contains("restaurant") { return "cup.and.saucer.fill" }
        if m.contains("gas") || m.contains("shell") || m.contains("uber") || m.contains("taxi") || m.contains("transit") { return "car.fill" }
        if m.contains("grocery") || m.contains("whole foods") || m.contains("market") { return "bag.fill" }
        if m.contains("netflix") || m.contains("spotify") || m.contains("hulu") { return "rectangle.grid.1x2.fill" }
        return "creditcard.fill"
    }
}
