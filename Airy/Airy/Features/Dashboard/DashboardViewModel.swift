//
//  DashboardViewModel.swift
//  Airy
//
//  Local-only: aggregate from SwiftData.
//

import SwiftUI

@Observable
final class DashboardViewModel {
    static let shared = DashboardViewModel()

    var thisMonth: MonthSummary?
    var previousMonthSpent: Double = 0
    var deltaPercent: Double = 0
    var isLoading = true
    var errorMessage: String?

    var recentTransactions: [Transaction] = []
    var upcomingSubscriptions: [Subscription] = []
    var aiSummaryLine: String?

    private init() {}

    func load() async {
        let perfStart = CFAbsoluteTimeGetCurrent()
        if thisMonth == nil { isLoading = true }
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
            let snapshot = SpendingInsightsEngine.compute()
            aiSummaryLine = SpendingInsightsEngine.generateSummaryText(snapshot)
            isLoading = false
            let perfEnd = CFAbsoluteTimeGetCurrent()
            print("[Perf] DashboardVM.load() took \(String(format: "%.1f", (perfEnd - perfStart) * 1000))ms")
        }
    }
}
