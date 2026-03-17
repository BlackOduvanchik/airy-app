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
        // Capture family/template info before confirming (SwiftData object may be deleted after confirm)
        let (familyId, imageHash, templateId) = await MainActor.run {
            let raw = LocalDataStore.shared.fetchPendingLocalTransaction(byId: id)
            return (raw?.sourceFamilyId, raw?.sourceImageHash, raw?.sourceTemplateId)
        }
        let ok = await MainActor.run { LocalDataStore.shared.confirmPending(id: id, overrides: overrides, rememberMerchant: rememberMerchant) }
        if ok {
            // Feed result back to the learning system so the family profile can improve or degrade
            if let fid = familyId, let hash = imageHash {
                let correctionMade = overrides != nil
                LayoutFamilyLearningStore.shared.recordUserFeedback(
                    familyId: fid,
                    imageHash: hash,
                    correctionMade: correctionMade
                )
                if correctionMade {
                    LayoutFamilyLearningStore.shared.checkAndApplyDegradation(familyId: fid)
                }
            }
            // If user unchecked "Remember rule", invalidate the template
            if !rememberMerchant, let tid = templateId {
                OCRTemplateStore.shared.remove(id: tid)
            }
            await load()
        } else {
            await MainActor.run { errorMessage = "Failed to confirm" }
        }
    }

    func reject(id: String) async {
        // Rejecting a transaction counts as a correction signal — user said our extraction was wrong
        let (familyId, imageHash) = await MainActor.run {
            let raw = LocalDataStore.shared.fetchPendingLocalTransaction(byId: id)
            return (raw?.sourceFamilyId, raw?.sourceImageHash)
        }
        await MainActor.run { LocalDataStore.shared.rejectPending(id: id) }
        if let fid = familyId, let hash = imageHash {
            LayoutFamilyLearningStore.shared.recordUserFeedback(
                familyId: fid,
                imageHash: hash,
                correctionMade: true
            )
            LayoutFamilyLearningStore.shared.checkAndApplyDegradation(familyId: fid)
        }
        await load()
    }

    /// Remove items from the displayed list immediately (for smooth swipe animation). Call before persistReject.
    @MainActor
    func removePendingLocally(ids: [String]) {
        pending.removeAll { ids.contains($0.id) }
    }

    /// Persist deletion without reloading the list (list already updated via removePendingLocally).
    func persistReject(id: String) async {
        // Capture template id before deleting the SwiftData record
        let templateId = await MainActor.run {
            LocalDataStore.shared.fetchPendingLocalTransaction(byId: id)?.sourceTemplateId
        }
        await MainActor.run { LocalDataStore.shared.rejectPending(id: id) }
        // Template extracted this transaction and user rejected it → invalidate the template
        if let tid = templateId {
            OCRTemplateStore.shared.remove(id: tid)
        }
    }

    func confirmAll(rememberRules: [String: Bool]) async {
        for item in pending {
            let remember = rememberRules[item.id] ?? true
            let (familyId, imageHash) = await MainActor.run {
                let raw = LocalDataStore.shared.fetchPendingLocalTransaction(byId: item.id)
                return (raw?.sourceFamilyId, raw?.sourceImageHash)
            }
            _ = await MainActor.run { LocalDataStore.shared.confirmPending(id: item.id, overrides: nil, rememberMerchant: remember) }
            // Bulk confirm without overrides = positive signal (no corrections)
            if let fid = familyId, let hash = imageHash {
                LayoutFamilyLearningStore.shared.recordUserFeedback(
                    familyId: fid,
                    imageHash: hash,
                    correctionMade: false
                )
            }
        }
        await load()
    }

    func rejectAll() async {
        for item in pending {
            await MainActor.run { LocalDataStore.shared.rejectPending(id: item.id) }
        }
        await load()
    }

    /// Returns duplicate warning when payload has probableDuplicateOfId or when same transaction is found in saved/pending.
    @MainActor
    func duplicateSeenText(for payload: PendingTransactionPayload?, excludePendingId: String? = nil) -> String? {
        guard let p = payload,
              let amt = p.amountOriginal,
              let merchant = p.merchant, !merchant.isEmpty else { return nil }
        if p.probableDuplicateOfId != nil {
            return "Possible duplicate of a saved transaction"
        }
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
