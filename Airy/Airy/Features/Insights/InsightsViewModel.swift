//
//  InsightsViewModel.swift
//  Airy
//
//  Local-only: compute from SwiftData via SpendingInsightsEngine.
//

import SwiftUI

@Observable
final class InsightsViewModel {
    var snapshot: SpendingSnapshot?
    var summaryText = ""
    var isLoading = true
    var showPaywall = false
    var errorMessage: String?

    var thisMonthSpent: Double { snapshot?.thisMonthSpent ?? 0 }
    var lastMonthSpent: Double { snapshot?.lastMonthSpent ?? 0 }
    var deltaPercent: Double { snapshot?.monthDeltaPercent ?? 0 }

    var hasEnoughData: Bool { (snapshot?.totalTransactionCount ?? 0) >= 5 }
    var hasMultipleMonths: Bool { (snapshot?.lastMonthSpent ?? 0) > 0 }
    var hasIncome: Bool { (snapshot?.thisMonthIncome ?? 0) > 0 }

    func load() async {
        isLoading = true
        defer { Task { @MainActor in isLoading = false } }
        await MainActor.run {
            let s = SpendingInsightsEngine.shared.compute()
            snapshot = s
            summaryText = SpendingInsightsEngine.shared.generateSummaryText(s)
        }
    }
}
