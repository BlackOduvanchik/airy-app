//
//  DashboardViewModel.swift
//  Airy
//

import SwiftUI

@Observable
final class DashboardViewModel {
    var thisMonth: MonthSummary?
    var previousMonthSpent: Double = 0
    var deltaPercent: Double = 0
    var isLoading = true
    var errorMessage: String?

    /// Recent transactions for "Recent Activity" (up to 5).
    var recentTransactions: [Transaction] = []
    /// Subscriptions with nextBillingDate for "Upcoming Bills".
    var upcomingSubscriptions: [Subscription] = []
    /// One-line AI summary for the dashboard card (e.g. from insights or computed).
    var aiSummaryLine: String?

    func load() async {
        isLoading = true
        defer { Task { @MainActor in isLoading = false } }
        do {
            async let dashboardTask = APIClient.shared.getDashboard()
            async let transactionsTask = APIClient.shared.getTransactions(limit: 5)
            async let subscriptionsTask: Result<SubscriptionsResponse, Error> = Result { try await APIClient.shared.getSubscriptions() }

            let res = try await dashboardTask
            await MainActor.run {
                thisMonth = res.thisMonth
                previousMonthSpent = res.previousMonthSpent
                deltaPercent = res.deltaPercent
            }

            let txRes = try await transactionsTask
            await MainActor.run { recentTransactions = txRes.transactions }

            switch await subscriptionsTask {
            case .success(let subRes):
                let sorted = subRes.subscriptions
                    .filter { $0.nextBillingDate != nil && !($0.nextBillingDate?.isEmpty ?? true) }
                    .sorted { (a, b) in
                        guard let da = a.nextBillingDate, let db = b.nextBillingDate else { return false }
                        return da.compare(db) == .orderedAscending
                    }
                await MainActor.run { upcomingSubscriptions = Array(sorted.prefix(5)) }
            case .failure:
                await MainActor.run { upcomingSubscriptions = [] }
            }

            await MainActor.run {
                if res.deltaPercent < 0 {
                    let absPct = abs(Int(res.deltaPercent.rounded()))
                    aiSummaryLine = "Spending is down \(absPct)% vs last month. Keep it up."
                } else if res.deltaPercent > 0 {
                    aiSummaryLine = "Spending is up \(Int(res.deltaPercent.rounded()))% vs last month. Review your habits."
                } else {
                    aiSummaryLine = "Your spending is in line with last month."
                }
            }
        } catch {
            await MainActor.run {
                thisMonth = nil
                recentTransactions = []
                upcomingSubscriptions = []
                errorMessage = error.localizedDescription
            }
        }
    }
}
