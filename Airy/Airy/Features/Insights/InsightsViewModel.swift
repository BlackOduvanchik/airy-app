//
//  InsightsViewModel.swift
//  Airy
//
//  Local-only: compute from SwiftData.
//

import SwiftUI

@Observable
final class InsightsViewModel {
    var summary = ""
    var insights: [InsightItem] = []
    var isLoading = true
    var showPaywall = false
    var errorMessage: String?

    var thisMonthSpent: Double = 0
    var lastMonthSpent: Double = 0
    var deltaPercent: Double = 0

    func load() async {
        isLoading = true
        defer { Task { @MainActor in isLoading = false } }
        await MainActor.run {
            let (thisMonth, prev, delta) = LocalDataStore.shared.dashboardSummary()
            thisMonthSpent = thisMonth.totalSpent
            lastMonthSpent = prev
            deltaPercent = delta
            let (sum, _) = LocalDataStore.shared.monthlySummary(month: nil)
            summary = sum
            insights = LocalDataStore.shared.behavioralInsights()
        }
    }
}
