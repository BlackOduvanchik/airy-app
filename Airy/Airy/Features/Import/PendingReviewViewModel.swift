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

    func confirm(id: String, overrides: ConfirmPendingOverrides? = nil) async {
        let ok = await MainActor.run { LocalDataStore.shared.confirmPending(id: id, overrides: overrides) }
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
}
