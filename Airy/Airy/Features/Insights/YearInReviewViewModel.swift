//
//  YearInReviewViewModel.swift
//  Airy
//
//  Data aggregation for Year in Review: monthly data, category breakdown, delegates insight generation to engine.
//  Heavy compute (monthly aggregation, category aggregation) runs off main thread.
//

import SwiftUI

// MARK: - ViewModel

@Observable @MainActor
final class YearInReviewViewModel {

    // Period
    var selectedPeriod: String = ""      // year string or "all"
    var chartMode: YRChartMode = .all
    var selectedMonthIndex: Int? = nil

    // Toggle filters
    var showIncome = true
    var showExpense = true
    var excludeSubscriptions = false

    // Computed data
    var monthlyData: [YRMonthData] = []
    var totalIncome: Double = 0
    var totalExpense: Double = 0
    var totalNet: Double = 0
    var topCategories: [YRCategorySummary] = []
    var activeSections: [YRSectionGroup] = []
    var availableYears: [String] = []

    var isLoading = true

    private var allTransactions: [Transaction] = []
    private(set) var baseCurrency: String = "USD"

    private var loadGeneration = 0
    private var computeTask: Task<YRBackgroundResult?, Never>?

    func load() async {
        let perfStart = CFAbsoluteTimeGetCurrent()
        loadGeneration += 1
        let myGen = loadGeneration
        computeTask?.cancel()

        isLoading = true
        baseCurrency = BaseCurrencyStore.baseCurrency
        let currentYear = Calendar.current.component(.year, from: Date())
        selectedPeriod = "\(currentYear)"
        availableYears = (2015...currentYear).reversed().map { "\($0)" }
        fetchTransactionsForPeriod()

        guard myGen == loadGeneration else { return }
        await recompute()

        if myGen == loadGeneration { isLoading = false }
        let perfEnd = CFAbsoluteTimeGetCurrent()
        print("[Perf] YearInReviewVM.load() took \(String(format: "%.1f", (perfEnd - perfStart) * 1000))ms")
    }

    /// Switch period and re-fetch only the needed transactions.
    func changePeriod(_ period: String) async {
        loadGeneration += 1
        let myGen = loadGeneration
        computeTask?.cancel()

        selectedPeriod = period
        selectedMonthIndex = nil
        fetchTransactionsForPeriod()

        guard myGen == loadGeneration else { return }
        await recompute()
    }

    private func fetchTransactionsForPeriod() {
        let currentYear = Calendar.current.component(.year, from: Date())
        if selectedPeriod == "all" {
            allTransactions = LocalDataStore.shared.fetchTransactions(from: "2015-01-01", to: "\(currentYear)-12-31")
        } else if let year = Int(selectedPeriod) {
            // Fetch selected year + previous year (needed for insights comparison)
            allTransactions = LocalDataStore.shared.fetchTransactions(from: "\(year - 1)-01-01", to: "\(year)-12-31")
        }
    }

    func recompute() async {
        let perfStart = CFAbsoluteTimeGetCurrent()
        let myGen = loadGeneration

        let filtered = filterTransactionsForPeriod()
        let localeId = LanguageManager.shared.current.rawValue
        let base = baseCurrency
        let excludeSubs = excludeSubscriptions
        let selectedIdx = selectedMonthIndex
        let currentMonthlyData = monthlyData // for selectedMonthIndex filtering context

        computeTask?.cancel()
        let task = Task.detached { [filtered, localeId, base, excludeSubs, selectedIdx, currentMonthlyData] in
            if Task.isCancelled { return nil as YRBackgroundResult? }

            let monthly = Self.computeMonthlyDataPure(
                from: filtered, localeIdentifier: localeId, baseCurrency: base
            )

            if Task.isCancelled { return nil }

            // Top categories aggregation
            var txs = filtered.filter { $0.type.lowercased() != "income" }
            if excludeSubs { txs = txs.filter { $0.isSubscription != true } }

            // Use freshly computed monthlyData for month filter (not stale currentMonthlyData)
            if let idx = selectedIdx, idx < monthly.count {
                let mk = monthly[idx].monthKey
                txs = txs.filter { String($0.transactionDate.prefix(7)) == mk }
            }

            var byCat: [String: Double] = [:]
            for (i, tx) in txs.enumerated() {
                if i % 500 == 0, Task.isCancelled { return nil }
                byCat[tx.category, default: 0] += Self.amountInBasePure(tx, baseCurrency: base)
            }

            let total = byCat.values.reduce(0, +)
            let topCats = byCat.sorted { $0.value > $1.value }.prefix(4).map {
                TopCatAggregate(categoryId: $0.key, amount: $0.value, share: total > 0 ? $0.value / total : 0)
            }

            return YRBackgroundResult(monthlyData: monthly, topCatAggregates: topCats)
        }
        computeTask = task
        let result = await task.value

        guard myGen == loadGeneration else { return }
        guard let result else { return }

        // Commit monthly data + totals
        monthlyData = result.monthlyData
        computeTotals()

        // Map aggregates → YRCategorySummary (Color/icon on main)
        topCategories = result.topCatAggregates.map { cat in
            let name = CategoryIconHelper.displayName(categoryId: cat.categoryId)
            let icon = CategoryIconHelper.iconName(categoryId: cat.categoryId)
            let color = CategoryIconHelper.color(categoryId: cat.categoryId)
            return YRCategorySummary(id: cat.categoryId, name: name, amount: cat.amount, share: cat.share, iconName: icon, color: color)
        }

        // Insight generation on main (uses L() + CategoryIconHelper)
        let previousTransactions = fetchPreviousPeriodTransactions()
        let context = YRInsightEngine.Context(
            monthlyData: monthlyData,
            transactions: filterTransactionsForPeriod(),
            selectedPeriod: selectedPeriod,
            selectedMonthIndex: selectedMonthIndex,
            baseCurrency: baseCurrency,
            previousPeriodTransactions: previousTransactions
        )
        activeSections = YRInsightEngine.generate(from: context)

        let perfEnd = CFAbsoluteTimeGetCurrent()
        print("[Perf] YearInReviewVM.recompute() main=\(String(format: "%.1f", (perfEnd - perfStart) * 1000))ms")
    }

    // MARK: - Filtering

    private func filterTransactionsForPeriod() -> [Transaction] {
        if selectedPeriod == "all" { return allTransactions }
        return allTransactions.filter { $0.transactionDate.hasPrefix(selectedPeriod) }
    }

    private func fetchPreviousPeriodTransactions() -> [Transaction]? {
        guard selectedPeriod != "all", let year = Int(selectedPeriod) else { return nil }
        let prevYear = "\(year - 1)"
        let prevTxs = allTransactions.filter { $0.transactionDate.hasPrefix(prevYear) }
        return prevTxs.isEmpty ? nil : prevTxs
    }

    private func effectiveMonthData() -> [YRMonthData] {
        monthlyData.map { m in
            var income = showIncome ? m.income : 0
            var expense = showExpense ? m.expense : 0
            if excludeSubscriptions {
                income -= m.subscriptionIncome
                expense -= m.subscriptionExpense
            }
            return YRMonthData(
                id: m.id, monthKey: m.monthKey, label: m.label, fullLabel: m.fullLabel,
                income: max(0, income), expense: max(0, expense),
                subscriptionExpense: m.subscriptionExpense,
                subscriptionIncome: m.subscriptionIncome
            )
        }
    }

    var displayedMonthlyData: [YRMonthData] { effectiveMonthData() }

    // MARK: - Totals

    private func computeTotals() {
        let data = effectiveMonthData()
        if let idx = selectedMonthIndex, idx < data.count {
            totalIncome = data[idx].income
            totalExpense = data[idx].expense
        } else {
            totalIncome = data.reduce(0) { $0 + $1.income }
            totalExpense = data.reduce(0) { $0 + $1.expense }
        }
        totalNet = totalIncome - totalExpense
    }

    // MARK: - Pure statics (safe for background)

    private static func amountInBasePure(_ tx: Transaction, baseCurrency: String) -> Double {
        if tx.baseCurrency.uppercased() == baseCurrency { return abs(tx.amountBase) }
        return CurrencyService.convert(amount: abs(tx.amountOriginal), from: tx.currencyOriginal, to: baseCurrency)
    }

    private static func computeMonthlyDataPure(
        from transactions: [Transaction],
        localeIdentifier: String,
        baseCurrency: String
    ) -> [YRMonthData] {
        var grouped: [String: (income: Double, expense: Double, subExp: Double, subInc: Double)] = [:]

        for tx in transactions {
            let key = String(tx.transactionDate.prefix(7))
            let amt = amountInBasePure(tx, baseCurrency: baseCurrency)
            let isIncome = tx.type.lowercased() == "income"
            let isSub = tx.isSubscription == true

            var entry = grouped[key, default: (0, 0, 0, 0)]
            if isIncome {
                entry.income += amt
                if isSub { entry.subInc += amt }
            } else {
                entry.expense += amt
                if isSub { entry.subExp += amt }
            }
            grouped[key] = entry
        }

        let appLocale = Locale(identifier: localeIdentifier)
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM"
        let shortDf = DateFormatter()
        shortDf.dateFormat = "MMM"
        shortDf.locale = appLocale
        let fullDf = DateFormatter()
        fullDf.dateFormat = "LLLL"   // standalone full month name
        fullDf.locale = appLocale

        return grouped.keys.sorted().map { key in
            let v = grouped[key]!
            let short: String
            let full: String
            if let d = df.date(from: key) {
                short = shortDf.string(from: d)
                full = fullDf.string(from: d).capitalized
            } else {
                short = key; full = key
            }
            return YRMonthData(id: key, monthKey: key, label: short, fullLabel: full,
                               income: v.income, expense: v.expense,
                               subscriptionExpense: v.subExp, subscriptionIncome: v.subInc)
        }
    }

    // MARK: - Amount helper (static, @MainActor — reads UserDefaults via CurrencyService)

    static func amountInBase(_ tx: Transaction) -> Double {
        CurrencyService.amountInBase(amountOriginal: abs(tx.amountOriginal), currencyOriginal: tx.currencyOriginal, amountBase: tx.amountBase, baseCurrency: tx.baseCurrency)
    }
}
