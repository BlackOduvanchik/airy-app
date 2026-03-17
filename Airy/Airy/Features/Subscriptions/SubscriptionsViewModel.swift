//
//  SubscriptionsViewModel.swift
//  Airy
//
//  Local-only: derive from SwiftData transactions.
//

import SwiftUI

@Observable
final class SubscriptionsViewModel {
    var subscriptions: [Subscription] = []
    var isLoading = true
    var showPaywall = false
    var errorMessage: String?

    var nextUpSubscriptions: [Subscription] {
        subscriptions
            .filter { $0.nextBillingDate != nil && !($0.nextBillingDate?.isEmpty ?? true) }
            .sorted { (a, b) in
                guard let da = a.nextBillingDate, let db = b.nextBillingDate else { return false }
                return da.compare(db) == .orderedAscending
            }
    }

    var totalMonthly: Double {
        let base = BaseCurrencyStore.baseCurrency
        return subscriptions.reduce(0) { sum, sub in
            let monthly: Double
            let interval = sub.interval.lowercased()
            if interval.hasPrefix("year") || interval.hasPrefix("annual") {
                monthly = sub.amount / 12
            } else if interval.hasPrefix("week") {
                monthly = sub.amount * (52.0 / 12.0)
            } else {
                monthly = sub.amount
            }
            return sum + CurrencyService.convert(amount: monthly, from: sub.currency, to: base)
        }
    }

    var subscriptionSharePercent: Int = 0

    func load() async {
        isLoading = true
        defer { Task { @MainActor in isLoading = false } }
        await MainActor.run {
            subscriptions = LocalDataStore.shared.subscriptionsFromTransactions()
            let totalSpent = LocalDataStore.shared.dashboardSummary().thisMonth.totalSpent
            subscriptionSharePercent = totalSpent > 0 ? Int(round(totalMonthly / totalSpent * 100)) : 0

            // Debug: dump saved GPT insights
            let allInsights = SubscriptionInsightStore.shared.loadAll()
            print("[SubsInsight] Stored insights: \(allInsights.count)")
            for ins in allInsights {
                print("[SubsInsight]  · \(ins.merchant): savings $\(String(format: "%.2f", ins.monthlySavingsPotential))/mo | tip: \(ins.tip) | fetched: \(ins.fetchedAt)")
            }
        }
    }
}
