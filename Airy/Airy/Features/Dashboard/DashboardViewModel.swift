//
//  DashboardViewModel.swift
//  Airy
//
//  Local-only: aggregate from SwiftData. Heavy compute runs off main thread.
//

import SwiftUI

/// Background compute result — all pure data, no Color/L() references.
private struct DashboardComputeResult: Sendable {
    let snapshot: SpendingSnapshot
    let filteredSubs: [Subscription]
}

@Observable @MainActor
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

    private var loadGeneration = 0
    private var computeTask: Task<DashboardComputeResult?, Never>?

    // MARK: - Subscription check throttle

    private static var lastSubCheck: Date?
    private static var forceSubCheck = false

    static func invalidateSubCheck() { forceSubCheck = true }

    private init() {}

    // MARK: - Load

    func load() async {
        let mainStart = CFAbsoluteTimeGetCurrent()
        loadGeneration += 1
        let myGen = loadGeneration
        computeTask?.cancel()

        if thisMonth == nil { isLoading = true }

        let now = Date()
        let cal = Calendar.current

        // Throttled subscription processing
        if Self.forceSubCheck || Self.lastSubCheck == nil
            || now.timeIntervalSince(Self.lastSubCheck!) > 300 {
            LocalDataStore.shared.processDueSubscriptions()
            Self.lastSubCheck = now
            Self.forceSubCheck = false
        }

        // Main-thread fetches (SwiftData main context)
        let (this, prev, delta) = LocalDataStore.shared.dashboardSummary()
        let recent = LocalDataStore.shared.fetchTransactions(limit: 5)
        let subs = LocalDataStore.shared.subscriptionsFromTransactions()
        let baseCurrency = BaseCurrencyStore.baseCurrency

        let thisMonthKey = {
            let y = cal.component(.year, from: now)
            let m = cal.component(.month, from: now)
            return String(format: "%04d-%02d", y, m)
        }()
        let lastMonthDate = cal.date(byAdding: .month, value: -1, to: now) ?? now
        let lastMonthKey = {
            let y = cal.component(.year, from: lastMonthDate)
            let m = cal.component(.month, from: lastMonthDate)
            return String(format: "%04d-%02d", y, m)
        }()
        let thisIncome = LocalDataStore.shared.fetchIncomeForMonth(monthKey: thisMonthKey)
        let lastIncome = LocalDataStore.shared.fetchIncomeForMonth(monthKey: lastMonthKey)

        let preBg = CFAbsoluteTimeGetCurrent()
        guard myGen == loadGeneration else { return }

        // Background expense fetch (own ModelContext)
        let expenses = await LocalDataStore.fetchExpenseDTOsBackground(months: 13)
        guard myGen == loadGeneration else { return }

        // Category names from ALL expenses (not just recent 5)
        let allCatIds = Set(expenses.map { $0.category })
        let catNames = Dictionary(uniqueKeysWithValues:
            allCatIds.map { ($0, CategoryIconHelper.displayName(categoryId: $0)) })

        // Heavy compute in background
        let task = Task.detached { [subs, baseCurrency, thisIncome, lastIncome, catNames, now] in
            for (i, _) in subs.enumerated() where i % 500 == 0 {
                if Task.isCancelled { return nil as DashboardComputeResult? }
            }

            let snapshot = SpendingInsightsEngine.computePure(
                expenses: expenses,
                baseCurrency: baseCurrency,
                thisMonthIncome: thisIncome,
                lastMonthIncome: lastIncome,
                subscriptions: subs,
                categoryNames: catNames,
                now: now
            )

            let filteredSubs = Array(
                subs
                    .filter { $0.nextBillingDate != nil && !($0.nextBillingDate?.isEmpty ?? true) }
                    .sorted { (a, b) in
                        guard let da = a.nextBillingDate, let db = b.nextBillingDate else { return false }
                        return da.compare(db) == .orderedAscending
                    }
                    .prefix(5)
            )

            return DashboardComputeResult(snapshot: snapshot, filteredSubs: filteredSubs)
        }
        computeTask = task
        let result = await task.value
        let postBg = CFAbsoluteTimeGetCurrent()

        guard myGen == loadGeneration else { return }
        guard let result else { return } // nil = cancelled

        // Commit — already on main
        thisMonth = this
        previousMonthSpent = prev
        deltaPercent = delta
        recentTransactions = recent
        upcomingSubscriptions = result.filteredSubs
        aiSummaryLine = SpendingInsightsEngine.generateSummaryText(result.snapshot)
        isLoading = false

        let end = CFAbsoluteTimeGetCurrent()
        let mainMs = ((preBg - mainStart) + (end - postBg)) * 1000
        let bgMs = (postBg - preBg) * 1000
        print("[Perf] DashboardVM.load() main=\(String(format: "%.1f", mainMs))ms bg=\(String(format: "%.1f", bgMs))ms")
    }
}
