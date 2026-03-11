//
//  PendingReviewViewModel.swift
//  Airy
//
//  Local-only: fetch/confirm/reject from SwiftData.
//

import SwiftUI

@Observable
final class PendingReviewViewModel {
    var pending: [PendingTransaction] = []
    var isLoading = true
    var errorMessage: String?

    func load() async {
        await MainActor.run { isLoading = true }
        defer { Task { @MainActor in isLoading = false } }
        await MainActor.run {
            pending = LocalDataStore.shared.fetchPendingTransactions()
        }
    }

    func confirm(id: String, overrides: ConfirmPendingOverrides? = nil, rememberMerchant: Bool = true) async {
        let ok = await MainActor.run { LocalDataStore.shared.confirmPending(id: id, overrides: overrides, rememberMerchant: rememberMerchant) }
        if ok {
            await load()
        } else {
            await MainActor.run { errorMessage = "Failed to confirm" }
        }
    }

    func reject(id: String) async {
        await MainActor.run { LocalDataStore.shared.rejectPending(id: id) }
        await load()
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

    /// Returns duplicate warning when the same transaction (same merchant, amount) is found on the same day.
    @MainActor
    func duplicateSeenText(for payload: PendingTransactionPayload?, excludePendingId: String? = nil) -> String? {
        guard let p = payload,
              let amt = p.amountOriginal,
              let merchant = p.merchant, !merchant.isEmpty else { return nil }
        let pendingDateStr = (p.transactionDate ?? "").prefix(10).description
        let merchantLower = merchant.lowercased()

        let transactions = LocalDataStore.shared.fetchTransactions(limit: 200)
        for tx in transactions {
            guard abs(tx.amountOriginal - amt) < 0.01 else { continue }
            guard tx.transactionDate.prefix(10).description == pendingDateStr else { continue }
            let txMerchant = (tx.merchant ?? "").lowercased()
            guard txMerchant.contains(merchantLower) || merchantLower.contains(txMerchant) else { continue }
            return "Возможно дубликат"
        }

        let pendingList = LocalDataStore.shared.fetchPendingTransactions()
        for item in pendingList where item.id != excludePendingId {
            guard let pl = item.decodedPayload,
                  let pam = pl.amountOriginal,
                  abs(pam - amt) < 0.01,
                  let pd = pl.transactionDate,
                  String(pd.prefix(10)) == pendingDateStr,
                  let pm = pl.merchant, !pm.isEmpty else { continue }
            let pmLower = pm.lowercased()
            guard pmLower.contains(merchantLower) || merchantLower.contains(pmLower) else { continue }
            return "Возможно дубликат"
        }
        return nil
    }
}
