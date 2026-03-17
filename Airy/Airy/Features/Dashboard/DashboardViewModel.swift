//
//  DashboardViewModel.swift
//  Airy
//
//  Local-only: aggregate from SwiftData.
//

import SwiftUI

@Observable
final class DashboardViewModel {
    var thisMonth: MonthSummary?
    var previousMonthSpent: Double = 0
    var deltaPercent: Double = 0
    var isLoading = true
    var errorMessage: String?

    var recentTransactions: [Transaction] = []
    var upcomingSubscriptions: [Subscription] = []
    var aiSummaryLine: String?

    func load() async {
        isLoading = true
        defer { Task { @MainActor in isLoading = false } }
        await MainActor.run {
            LocalDataStore.shared.processDueSubscriptions()
            let (this, prev, delta) = LocalDataStore.shared.dashboardSummary()
            thisMonth = this
            previousMonthSpent = prev
            deltaPercent = delta
            recentTransactions = LocalDataStore.shared.fetchTransactions(limit: 5)
            let subs = LocalDataStore.shared.subscriptionsFromTransactions()
            upcomingSubscriptions = subs
                .filter { $0.nextBillingDate != nil && !($0.nextBillingDate?.isEmpty ?? true) }
                .sorted { (a, b) in
                    guard let da = a.nextBillingDate, let db = b.nextBillingDate else { return false }
                    return da.compare(db) == .orderedAscending
                }
                .prefix(5)
                .map { $0 }
            if delta < 0 {
                let absPct = abs(Int(delta.rounded()))
                aiSummaryLine = "Spending is down \(absPct)% vs last month. Keep it up."
            } else if delta > 0 {
                aiSummaryLine = "Spending is up \(Int(delta.rounded()))% vs last month. Review your habits."
            } else {
                aiSummaryLine = "Your spending is in line with last month."
            }
        }
    }
}
