//
//  YearInReviewViewModel.swift
//  Airy
//
//  Data aggregation for Year in Review: monthly data, category breakdown, delegates insight generation to engine.
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

    func load() async {
        isLoading = true
        baseCurrency = BaseCurrencyStore.baseCurrency
        let currentYear = Calendar.current.component(.year, from: Date())
        selectedPeriod = "\(currentYear)"
        availableYears = (2015...currentYear).reversed().map { "\($0)" }
        allTransactions = LocalDataStore.shared.fetchTransactions(from: "2015-01-01", to: "\(currentYear)-12-31")
        recompute()
        isLoading = false
    }

    func recompute() {
        let filtered = filterTransactionsForPeriod()
        monthlyData = computeMonthlyData(from: filtered)
        computeTotals()
        computeTopCategories(from: filtered)

        let previousTransactions = fetchPreviousPeriodTransactions()
        let context = YRInsightEngine.Context(
            monthlyData: monthlyData,
            transactions: filtered,
            selectedPeriod: selectedPeriod,
            selectedMonthIndex: selectedMonthIndex,
            baseCurrency: baseCurrency,
            previousPeriodTransactions: previousTransactions
        )
        activeSections = YRInsightEngine.generate(from: context)
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

    // MARK: - Monthly aggregation

    private func computeMonthlyData(from transactions: [Transaction]) -> [YRMonthData] {
        var grouped: [String: (income: Double, expense: Double, subExp: Double, subInc: Double)] = [:]

        for tx in transactions {
            let key = String(tx.transactionDate.prefix(7))
            let amt = Self.amountInBase(tx)
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

        let appLocale = Locale(identifier: LanguageManager.shared.current.rawValue)
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

    // MARK: - Totals

    private func computeTotals() {
        let data = effectiveMonthData()
        totalIncome = data.reduce(0) { $0 + $1.income }
        totalExpense = data.reduce(0) { $0 + $1.expense }
        totalNet = totalIncome - totalExpense
    }

    // MARK: - Top Categories

    private func computeTopCategories(from transactions: [Transaction]) {
        var txs = transactions.filter { $0.type.lowercased() != "income" }
        if excludeSubscriptions { txs = txs.filter { $0.isSubscription != true } }

        if let idx = selectedMonthIndex, idx < monthlyData.count {
            let mk = monthlyData[idx].monthKey
            txs = txs.filter { String($0.transactionDate.prefix(7)) == mk }
        }

        var byCat: [String: Double] = [:]
        for tx in txs { byCat[tx.category, default: 0] += Self.amountInBase(tx) }

        let total = byCat.values.reduce(0, +)
        let sorted = byCat.sorted { $0.value > $1.value }.prefix(4)

        topCategories = sorted.map { cat in
            let name = CategoryIconHelper.displayName(categoryId: cat.key)
            let icon = CategoryIconHelper.iconName(categoryId: cat.key)
            let color = CategoryIconHelper.color(categoryId: cat.key)
            let share = total > 0 ? cat.value / total : 0
            return YRCategorySummary(id: cat.key, name: name, amount: cat.value, share: share, iconName: icon, color: color)
        }
    }

    // MARK: - Amount helper (static for engine reuse)

    static func amountInBase(_ tx: Transaction) -> Double {
        CurrencyService.amountInBase(amountOriginal: abs(tx.amountOriginal), currencyOriginal: tx.currencyOriginal, amountBase: tx.amountBase, baseCurrency: tx.baseCurrency)
    }
}
