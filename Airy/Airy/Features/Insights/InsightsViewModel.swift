//
//  InsightsViewModel.swift
//  Airy
//
//  Local-only: compute from SwiftData via SpendingInsightsEngine.
//  Heavy compute runs off main thread via computePure + fetchExpenseDTOsBackground.
//

import SwiftUI

@Observable @MainActor
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

    var summaryMentionsSubscriptions: Bool {
        let s = summaryText.lowercased()
        return s.contains("subscri") || s.contains("подпис") || s.contains("recurring")
            || s.contains("регулярн") || s.contains("abonnement") || s.contains("suscripci")
    }

    func load() async {
        isLoading = true

        // Gather inputs on main
        let baseCurrency = BaseCurrencyStore.baseCurrency
        let now = Date()
        let cal = Calendar.current
        let thisMonthKey = String(format: "%04d-%02d", cal.component(.year, from: now), cal.component(.month, from: now))
        let lastMonthDate = cal.date(byAdding: .month, value: -1, to: now) ?? now
        let lastMonthKey = String(format: "%04d-%02d", cal.component(.year, from: lastMonthDate), cal.component(.month, from: lastMonthDate))
        let thisIncome = LocalDataStore.shared.fetchIncomeForMonth(monthKey: thisMonthKey)
        let lastIncome = LocalDataStore.shared.fetchIncomeForMonth(monthKey: lastMonthKey)
        let subs = LocalDataStore.shared.subscriptionsFromTransactions()

        // Background expense fetch
        let expenses = await LocalDataStore.fetchExpenseDTOsBackground(months: 13)

        // Category names from all expenses
        let allCatIds = Set(expenses.map { $0.category })
        let catNames = Dictionary(uniqueKeysWithValues:
            allCatIds.map { ($0, CategoryIconHelper.displayName(categoryId: $0)) })

        // Background compute
        let s = await Task.detached { [baseCurrency, thisIncome, lastIncome, subs, catNames, now] in
            SpendingInsightsEngine.computePure(
                expenses: expenses,
                baseCurrency: baseCurrency,
                thisMonthIncome: thisIncome,
                lastMonthIncome: lastIncome,
                subscriptions: subs,
                categoryNames: catNames,
                now: now
            )
        }.value

        // Commit on main
        snapshot = s
        summaryText = SpendingInsightsEngine.generateSummaryText(s, offset: 1)
        isLoading = false
    }
}
