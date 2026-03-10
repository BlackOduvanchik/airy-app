//
//  PendingReviewViewModel.swift
//  Airy
//

import SwiftUI

@Observable
final class PendingReviewViewModel {
    var pending: [PendingTransaction] = []
    var isLoading = true
    var errorMessage: String?

    func load() async {
        isLoading = true
        defer { Task { @MainActor in isLoading = false } }
        do {
            let res = try await APIClient.shared.getPendingTransactions()
            await MainActor.run { pending = res.pending }
        } catch {
            await MainActor.run {
                pending = []
                errorMessage = error.localizedDescription
            }
        }
    }

    func confirm(id: String, overrides: ConfirmPendingOverrides? = nil) async {
        do {
            try await APIClient.shared.confirmPending(id: id, overrides: overrides)
            await load()
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    func reject(id: String) async {
        do {
            try await APIClient.shared.rejectPending(id: id)
            await load()
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }
}
