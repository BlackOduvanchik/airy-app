//
//  SpendingInsightsEngine.swift
//  Airy
//
//  Pure local calculation engine. Fetches all transactions once,
//  computes every metric for InsightsView and DashboardView.
//

import Foundation
import SwiftUI

@MainActor
final class SpendingInsightsEngine {
    static let shared = SpendingInsightsEngine()
    private init() {}

    private let cal = Calendar.current
    private lazy var dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f
    }()

    // MARK: - Compute

    func compute() -> SpendingSnapshot {
        let now = Date()
        let base = BaseCurrencyStore.baseCurrency
        let allExpenses = LocalDataStore.shared.fetchAllExpenseTransactions(months: 13)

        let thisMonthKey = monthKey(for: now)
        let lastMonthDate = cal.date(byAdding: .month, value: -1, to: now) ?? now
        let lastMonthKey = monthKey(for: lastMonthDate)

        // Prior month keys (used across many blocks)
        let priorMonthKeys = (1...3).compactMap { offset -> String? in
            guard let d = cal.date(byAdding: .month, value: -offset, to: now) else { return nil }
            return monthKey(for: d)
        }

        // Build set of (monthKey|merchant) that have a real expense, to deduplicate subscription templates
        let expenseMonthMerchant: Set<String> = {
            var set = Set<String>()
            for tx in allExpenses where tx.isSubscription != true {
                let k = String(tx.transactionDate.prefix(7))
                set.insert("\(k)|\(tx.merchant ?? "")")
            }
            return set
        }()

        func shouldCount(_ tx: LocalTransaction) -> Bool {
            if tx.isSubscription == true {
                let k = String(tx.transactionDate.prefix(7))
                return !expenseMonthMerchant.contains("\(k)|\(tx.merchant ?? "")")
            }
            return true
        }

        func amountInBase(_ tx: LocalTransaction) -> Double {
            CurrencyService.amountInBase(
                amountOriginal: abs(tx.amountOriginal),
                currencyOriginal: tx.currencyOriginal,
                amountBase: tx.amountBase,
                baseCurrency: tx.baseCurrency
            )
        }

        // Group by month
        var byMonth: [String: [LocalTransaction]] = [:]
        for tx in allExpenses where shouldCount(tx) {
            let k = String(tx.transactionDate.prefix(7))
            byMonth[k, default: []].append(tx)
        }

        // Month totals
        func monthTotal(_ key: String) -> Double {
            (byMonth[key] ?? []).reduce(0) { $0 + amountInBase($1) }
        }

        let thisMonthTxs = byMonth[thisMonthKey] ?? []
        let thisMonthSpent = monthTotal(thisMonthKey)
        let lastMonthSpent = monthTotal(lastMonthKey)
        let monthDelta = lastMonthSpent > 0 ? ((thisMonthSpent - lastMonthSpent) / lastMonthSpent) * 100 : 0

        // Calendar
        let dayOfMonth = cal.component(.day, from: now)
        let daysInMonth = cal.range(of: .day, in: .month, for: now)?.count ?? 30

        // MARK: Block A — Pace

        let prior3Totals = priorMonthKeys.map { monthTotal($0) }
        let last3MonthAvgSpend = prior3Totals.isEmpty ? 0 : prior3Totals.reduce(0, +) / Double(prior3Totals.count)
        let expectedByToday = last3MonthAvgSpend > 0 ? (last3MonthAvgSpend / Double(daysInMonth)) * Double(dayOfMonth) : 0
        let spendPaceRatio = expectedByToday > 0 ? thisMonthSpent / expectedByToday : 1.0

        // MARK: Block B — First/second half

        var firstHalfSpend: Double = 0
        var secondHalfSpend: Double = 0
        let lastDayCutoff = max(dayOfMonth - 7, 0)
        for tx in thisMonthTxs {
            if let day = dayComponent(from: tx.transactionDate) {
                let amt = amountInBase(tx)
                if day <= 7 { firstHalfSpend += amt }
                if day > lastDayCutoff { secondHalfSpend += amt }
            }
        }

        // MARK: Category breakdown for this & last month

        var thisByCat: [String: Double] = [:]
        var lastByCat: [String: Double] = [:]
        for tx in thisMonthTxs {
            thisByCat[tx.category, default: 0] += amountInBase(tx)
        }
        for tx in byMonth[lastMonthKey] ?? [] {
            lastByCat[tx.category, default: 0] += amountInBase(tx)
        }

        let allCatIds = Set(thisByCat.keys).union(lastByCat.keys)
        let categoryDeltas: [CategoryDelta] = allCatIds.compactMap { catId in
            let thisAmt = thisByCat[catId] ?? 0
            let lastAmt = lastByCat[catId] ?? 0
            guard thisAmt > 0 || lastAmt > 0 else { return nil }
            let delta = lastAmt > 0 ? ((thisAmt - lastAmt) / lastAmt) * 100 : (thisAmt > 0 ? 100 : 0)
            let name = CategoryIconHelper.displayName(categoryId: catId)
            let emoji = emojiForCategory(catId)
            return CategoryDelta(id: catId, name: name, emoji: emoji, thisMonth: thisAmt, lastMonth: lastAmt, deltaPercent: delta)
        }.sorted { abs($0.deltaPercent) > abs($1.deltaPercent) }

        // MARK: Top merchant per category (this month)

        var merchantByCat: [String: [String: Double]] = [:]
        for tx in thisMonthTxs {
            let m = tx.merchant ?? "Unknown"
            merchantByCat[tx.category, default: [:]][m, default: 0] += amountInBase(tx)
        }
        var topMerchantByCategory: [String: MerchantStat] = [:]
        for (cat, merchants) in merchantByCat {
            if let top = merchants.max(by: { $0.value < $1.value }) {
                topMerchantByCategory[cat] = MerchantStat(merchant: top.key, totalSpent: top.value)
            }
        }

        // MARK: Block C — Concentration

        let sortedCats = thisByCat.sorted { $0.value > $1.value }
        let topCategoryShare = thisMonthSpent > 0 ? (sortedCats.first?.value ?? 0) / thisMonthSpent : 0
        let topCategoryName = sortedCats.first.map { CategoryIconHelper.displayName(categoryId: $0.key) }
        let top2Sum = sortedCats.prefix(2).reduce(0.0) { $0 + $1.value }
        let top2CategoriesShare = thisMonthSpent > 0 ? top2Sum / thisMonthSpent : 0

        var merchantThisMonth: [String: (total: Double, category: String)] = [:]
        for tx in thisMonthTxs {
            let m = tx.merchant ?? "Unknown"
            let existing = merchantThisMonth[m]
            merchantThisMonth[m] = (total: (existing?.total ?? 0) + amountInBase(tx), category: existing?.category ?? tx.category)
        }
        let sortedMerchants = merchantThisMonth.sorted { $0.value.total > $1.value.total }
        let topMerchantShareTotal = thisMonthSpent > 0 ? (sortedMerchants.first?.value.total ?? 0) / thisMonthSpent : 0
        let topMerchantNameTotal = sortedMerchants.first?.key

        var topMerchantShareInCategory: [String: MerchantConcentration] = [:]
        for (cat, merchants) in merchantByCat {
            let catTotal = thisByCat[cat] ?? 0
            if catTotal > 0, let top = merchants.max(by: { $0.value < $1.value }) {
                topMerchantShareInCategory[cat] = MerchantConcentration(merchant: top.key, share: top.value / catTotal)
            }
        }

        // MARK: Block D — Frequency

        let txCountThisMonth = thisMonthTxs.count
        let prior3Counts = priorMonthKeys.map { (byMonth[$0] ?? []).count }
        let txCountLast3MonthAvg = prior3Counts.isEmpty ? 0 : Double(prior3Counts.reduce(0, +)) / Double(prior3Counts.count)

        var merchantFreqs: [String: Int] = [:]
        for tx in thisMonthTxs {
            merchantFreqs[tx.merchant ?? "Unknown", default: 0] += 1
        }
        let topFreqMerchant = merchantFreqs.max(by: { $0.value < $1.value })

        // Category tx counts (this month vs avg prior 3)
        var catTxCountsThis: [String: Int] = [:]
        for tx in thisMonthTxs { catTxCountsThis[tx.category, default: 0] += 1 }
        var categoryTxCounts: [String: CategoryTxCount] = [:]
        for (cat, cnt) in catTxCountsThis {
            let priorCounts = priorMonthKeys.map { mk in
                (byMonth[mk] ?? []).filter { $0.category == cat }.count
            }
            let avg = priorCounts.isEmpty ? 0 : Double(priorCounts.reduce(0, +)) / Double(priorCounts.count)
            categoryTxCounts[cat] = CategoryTxCount(thisMonth: cnt, avg3Month: avg)
        }

        // MARK: Block E — Ticket size

        let thisMonthAmounts = thisMonthTxs.map { amountInBase($0) }.sorted()
        let medianTicketThis = median(thisMonthAmounts)
        let avgTicketThis = txCountThisMonth > 0 ? thisMonthSpent / Double(txCountThisMonth) : 0
        let smallTxCount = thisMonthAmounts.filter { $0 < medianTicketThis }.count
        let smallTxShare = txCountThisMonth > 0 ? Double(smallTxCount) / Double(txCountThisMonth) : 0

        var prior3Amounts: [Double] = []
        for mk in priorMonthKeys {
            for tx in byMonth[mk] ?? [] { prior3Amounts.append(amountInBase(tx)) }
        }
        prior3Amounts.sort()
        let medianTicketPrior = median(prior3Amounts)
        let prior3TxCount = prior3Amounts.count
        let prior3TotalSpend = prior3Amounts.reduce(0, +)
        let avgTicketPrior = prior3TxCount > 0 ? prior3TotalSpend / Double(prior3TxCount) : 0

        // MARK: Weekly spending

        let (thisWeekStart, thisWeekEnd) = weekBounds(for: now)
        let lastWeekStart = cal.date(byAdding: .day, value: -7, to: thisWeekStart) ?? thisWeekStart
        let lastWeekEnd = cal.date(byAdding: .day, value: -7, to: thisWeekEnd) ?? thisWeekEnd

        let thisWeekStr = dateFmt.string(from: thisWeekStart)
        let thisWeekEndStr = dateFmt.string(from: thisWeekEnd)
        let lastWeekStr = dateFmt.string(from: lastWeekStart)
        let lastWeekEndStr = dateFmt.string(from: lastWeekEnd)

        var thisWeekSpent: Double = 0
        var lastWeekSpent: Double = 0
        for tx in allExpenses where shouldCount(tx) {
            let d = String(tx.transactionDate.prefix(10))
            if d >= thisWeekStr && d <= thisWeekEndStr {
                thisWeekSpent += amountInBase(tx)
            } else if d >= lastWeekStr && d <= lastWeekEndStr {
                lastWeekSpent += amountInBase(tx)
            }
        }
        let weekDelta = lastWeekSpent > 0 ? ((thisWeekSpent - lastWeekSpent) / lastWeekSpent) * 100 : 0

        // MARK: Daily average & projections

        let dailyAvg = dayOfMonth > 0 ? thisMonthSpent / Double(dayOfMonth) : 0
        let projectedSpend = dailyAvg * Double(daysInMonth)

        // MARK: Income & safe-to-spend

        let thisMonthIncome = LocalDataStore.shared.fetchIncomeForMonth(monthKey: thisMonthKey)
        let projectedSavings = thisMonthIncome > 0 ? thisMonthIncome - projectedSpend : 0

        let subs = LocalDataStore.shared.subscriptionsFromTransactions()
        let subscriptionMonthly = subs.reduce(0.0) { sum, sub in
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
        let remainingDays = max(daysInMonth - dayOfMonth, 0)
        let committedRemaining = subscriptionMonthly * (Double(remainingDays) / Double(daysInMonth))
        let safeToSpendRaw = thisMonthIncome > 0 ? thisMonthIncome - thisMonthSpent - committedRemaining : 0
        let safeToSpend = max(safeToSpendRaw, 0)

        // MARK: Block F — Subscriptions extended

        let committedToIncomeRatio = thisMonthIncome > 0 ? subscriptionMonthly / thisMonthIncome : 0

        var upcomingBillsNext7Days: Double = 0
        let next7Date = dateFmt.string(from: cal.date(byAdding: .day, value: 7, to: now) ?? now)
        let todayStr = dateFmt.string(from: now)
        for sub in subs {
            guard let nbd = sub.nextBillingDate, !nbd.isEmpty else { continue }
            let dateStr = String(nbd.prefix(10))
            if dateStr >= todayStr && dateStr <= next7Date {
                upcomingBillsNext7Days += CurrencyService.convert(amount: sub.amount, from: sub.currency, to: base)
            }
        }

        // MARK: Merchant anomalies

        var merchantAnomalies: [MerchantAnomaly] = []
        for (merchant, info) in merchantThisMonth {
            var priorTotals: [Double] = []
            for mk in priorMonthKeys {
                let total = (byMonth[mk] ?? []).filter { ($0.merchant ?? "Unknown") == merchant }.reduce(0.0) { $0 + amountInBase($1) }
                priorTotals.append(total)
            }
            let nonZero = priorTotals.filter { $0 > 0 }
            guard nonZero.count >= 2 else { continue }
            let avg = nonZero.reduce(0, +) / Double(nonZero.count)
            guard avg > 0 else { continue }
            let ratio = info.total / avg
            if ratio >= 1.8 {
                let catName = CategoryIconHelper.displayName(categoryId: info.category)
                merchantAnomalies.append(MerchantAnomaly(
                    id: merchant, merchant: merchant, category: info.category, categoryName: catName,
                    currentSpent: info.total, averageSpent: avg, ratio: ratio
                ))
            }
        }
        merchantAnomalies.sort { $0.ratio > $1.ratio }
        let anomalyCount = merchantAnomalies.count

        // MARK: Block G — New merchants, repeated merchant streak

        let priorMerchants: Set<String> = {
            var s = Set<String>()
            for mk in priorMonthKeys {
                for tx in byMonth[mk] ?? [] { s.insert(tx.merchant ?? "Unknown") }
            }
            return s
        }()
        let thisMerchants = Set(merchantThisMonth.keys)
        let newMerchantCount = thisMerchants.subtracting(priorMerchants).subtracting(["Unknown"]).count

        // Repeated merchant streak: for each merchant, find max consecutive days
        var merchantDates: [String: [String]] = [:]
        for tx in thisMonthTxs {
            let m = tx.merchant ?? "Unknown"
            let d = String(tx.transactionDate.prefix(10))
            merchantDates[m, default: []].append(d)
        }
        var bestStreak: MerchantStreak? = nil
        for (merchant, dates) in merchantDates where merchant != "Unknown" {
            let unique = Array(Set(dates)).sorted()
            let streak = consecutiveDayStreak(dates: unique)
            if streak >= 3 {
                if bestStreak == nil || streak > bestStreak!.days {
                    bestStreak = MerchantStreak(merchant: merchant, days: streak)
                }
            }
        }

        // MARK: Block H — Positive / savings helpers

        let lastMonthIncome = LocalDataStore.shared.fetchIncomeForMonth(monthKey: lastMonthKey)
        let lastMonthSavings = lastMonthIncome > 0 ? lastMonthIncome - lastMonthSpent : 0

        // Average weekly spend over 8 weeks
        let eightWeeksAgoStr = dateFmt.string(from: cal.date(byAdding: .day, value: -56, to: now) ?? now)
        var eightWeekTotal: Double = 0
        for tx in allExpenses where shouldCount(tx) {
            let d = String(tx.transactionDate.prefix(10))
            if d >= eightWeeksAgoStr && d < todayStr {
                eightWeekTotal += amountInBase(tx)
            }
        }
        let avgWeeklySpend8Weeks = eightWeekTotal / 8.0

        // Recurring cost delta
        let currentSubTotal = subMonthlyTotals(byMonth: byMonth, thisMonthKey: thisMonthKey, allExpenses: allExpenses, shouldCount: shouldCount, amountInBase: amountInBase)
        let priorSubTotals = priorMonthKeys.map { mk in
            subMonthlyTotals(byMonth: byMonth, thisMonthKey: mk, allExpenses: allExpenses, shouldCount: shouldCount, amountInBase: amountInBase)
        }
        let avgPriorSub = priorSubTotals.isEmpty ? 0 : priorSubTotals.reduce(0, +) / Double(priorSubTotals.count)
        let recurringCostDeltaPercent = avgPriorSub > 0 ? ((currentSubTotal - avgPriorSub) / avgPriorSub) * 100 : 0

        // MARK: Weekday vs weekend average

        var weekdayTotal: Double = 0; var weekdayDays = Set<String>()
        var weekendTotal: Double = 0; var weekendDays = Set<String>()
        for tx in thisMonthTxs where tx.isSubscription != true {
            let dateStr = String(tx.transactionDate.prefix(10))
            if let d = dateFmt.date(from: dateStr) {
                let wd = cal.component(.weekday, from: d)
                let amt = amountInBase(tx)
                if wd == 1 || wd == 7 {
                    weekendTotal += amt; weekendDays.insert(dateStr)
                } else {
                    weekdayTotal += amt; weekdayDays.insert(dateStr)
                }
            }
        }
        let weekdayAvg = weekdayDays.count > 0 ? weekdayTotal / Double(weekdayDays.count) : 0
        let weekendAvg = weekendDays.count > 0 ? weekendTotal / Double(weekendDays.count) : 0

        // MARK: Monthly history (12 months)

        let shortLabels = ["J","F","M","A","M","J","J","A","S","O","N","D"]
        var monthlyHistory: [MonthlySpendPoint] = []
        for offset in stride(from: 11, through: 0, by: -1) {
            guard let d = cal.date(byAdding: .month, value: -offset, to: now) else { continue }
            let mk = monthKey(for: d)
            let m = cal.component(.month, from: d)
            let total = monthTotal(mk)
            monthlyHistory.append(MonthlySpendPoint(
                id: mk, monthKey: mk, shortLabel: shortLabels[m - 1],
                total: total, isCurrent: mk == thisMonthKey
            ))
        }

        // MARK: Subscription trend (6 months)

        var subMonthlyTotalsList: [MonthlySubTotal] = []
        for offset in stride(from: 5, through: 0, by: -1) {
            guard let d = cal.date(byAdding: .month, value: -offset, to: now) else { continue }
            let mk = monthKey(for: d)
            let total = subMonthlyTotals(byMonth: byMonth, thisMonthKey: mk, allExpenses: allExpenses, shouldCount: shouldCount, amountInBase: amountInBase)
            subMonthlyTotalsList.append(MonthlySubTotal(monthKey: mk, total: total))
        }
        let subDelta = subMonthlyTotalsList.count >= 2
            ? (subMonthlyTotalsList.last?.total ?? 0) - (subMonthlyTotalsList.first?.total ?? 0)
            : 0
        let thirtyDaysAgo = dateFmt.string(from: cal.date(byAdding: .day, value: -30, to: now) ?? now)
        let newTrials = subs.filter { sub in
            guard let tid = sub.templateTransactionId else { return false }
            return allExpenses.first { $0.id == tid }?.transactionDate ?? "" >= thirtyDaysAgo
        }.count

        let totalTxCount = thisMonthTxs.count + (byMonth[lastMonthKey] ?? []).count

        // MARK: Weekly cumulative spend (for trend chart)

        let weekBounds = [7, 14, 21, daysInMonth]

        func weeklyCumulative(txs: [LocalTransaction]) -> [Double] {
            var cumulative = 0.0
            var result: [Double] = []
            var txIdx = 0
            let sorted = txs.sorted { ($0.transactionDate) < ($1.transactionDate) }
            for bound in weekBounds {
                while txIdx < sorted.count, let day = dayComponent(from: sorted[txIdx].transactionDate), day <= bound {
                    cumulative += amountInBase(sorted[txIdx])
                    txIdx += 1
                }
                result.append(cumulative)
            }
            return result
        }

        let weeklySpendThisMonth = weeklyCumulative(txs: thisMonthTxs)
        let weeklySpendLastMonth = weeklyCumulative(txs: byMonth[lastMonthKey] ?? [])

        // MARK: - Build Snapshot

        return SpendingSnapshot(
            thisMonthSpent: thisMonthSpent,
            lastMonthSpent: lastMonthSpent,
            monthDeltaPercent: monthDelta,
            thisWeekSpent: thisWeekSpent,
            lastWeekSpent: lastWeekSpent,
            weekDeltaPercent: weekDelta,
            thisMonthIncome: thisMonthIncome,
            categoryDeltas: categoryDeltas,
            dailyAverageThisMonth: dailyAvg,
            projectedMonthlySpend: projectedSpend,
            projectedMonthlySavings: projectedSavings,
            safeToSpend: safeToSpend,
            topMerchantByCategory: topMerchantByCategory,
            merchantAnomalies: Array(merchantAnomalies.prefix(3)),
            weekdayAvgSpend: weekdayAvg,
            weekendAvgSpend: weekendAvg,
            monthlyHistory: monthlyHistory,
            subscriptionTrend: SubscriptionTrendData(
                monthlyTotals: subMonthlyTotalsList,
                deltaAmount: subDelta,
                newSubsCount: newTrials
            ),
            totalTransactionCount: totalTxCount,
            computedAt: now,
            // Pace
            last3MonthAvgSpend: last3MonthAvgSpend,
            spendPaceRatio: spendPaceRatio,
            firstHalfSpend: firstHalfSpend,
            secondHalfSpend: secondHalfSpend,
            // Concentration
            topCategoryShare: topCategoryShare,
            topCategoryName: topCategoryName,
            top2CategoriesShare: top2CategoriesShare,
            topMerchantShareTotal: topMerchantShareTotal,
            topMerchantNameTotal: topMerchantNameTotal,
            topMerchantShareInCategory: topMerchantShareInCategory,
            // Frequency
            txCountThisMonth: txCountThisMonth,
            txCountLast3MonthAvg: txCountLast3MonthAvg,
            topFrequentMerchant: topFreqMerchant?.key,
            topFrequentMerchantCount: topFreqMerchant?.value ?? 0,
            categoryTxCounts: categoryTxCounts,
            // Ticket size
            smallTxShare: smallTxShare,
            smallTxCount: smallTxCount,
            avgTicketThisMonth: avgTicketThis,
            avgTicketLast3Month: avgTicketPrior,
            medianTicketThisMonth: medianTicketThis,
            medianTicketLast3Month: medianTicketPrior,
            // Subscriptions extended
            committedToIncomeRatio: committedToIncomeRatio,
            upcomingBillsNext7Days: upcomingBillsNext7Days,
            subscriptionMonthlyTotal: subscriptionMonthly,
            recurringCostDeltaPercent: recurringCostDeltaPercent,
            // Risk / anomaly
            anomalyCount: anomalyCount,
            newMerchantCount: newMerchantCount,
            repeatedMerchantStreak: bestStreak,
            safeToSpendRaw: safeToSpendRaw,
            avgWeeklySpend8Weeks: avgWeeklySpend8Weeks,
            // Positive
            lastMonthSavings: lastMonthSavings,
            // Calendar
            dayOfMonth: dayOfMonth,
            daysInMonth: daysInMonth,
            // Weekly cumulative
            weeklySpendThisMonth: weeklySpendThisMonth,
            weeklySpendLastMonth: weeklySpendLastMonth
        )
    }

    // MARK: - Text Generation

    /// Wraps a value in markdown bold markers for rendering in Text(.init(...))
    private func B(_ s: String) -> String { "**\(s)**" }

    func generateSummaryText(_ s: SpendingSnapshot, offset: Int = 0) -> String {
        // Graduated fallbacks
        if s.txCountThisMonth == 0 && s.totalTransactionCount == 0 {
            return L("insight_no_spending")
        }
        if s.txCountThisMonth <= 4 {
            if s.dayOfMonth <= 7 {
                return L("insight_early_month")
            }
            if s.subscriptionTrend.monthlyTotals.contains(where: { $0.total > 0 }) {
                return L("insight_mostly_subs")
            }
            return L("insight_few_tx")
        }

        var candidates: [InsightCandidate] = []
        let fmt = currencyFormatter()
        let significantDeltas = s.categoryDeltas.filter { abs($0.deltaPercent) > 10 && $0.lastMonth > 0 }
        let weekday = cal.component(.weekday, from: Date())

        // ──────────────────────────────────────
        // GROUP 1: Month Pace (tag: "pace")
        // ──────────────────────────────────────

        if s.last3MonthAvgSpend > 0 {
            if s.spendPaceRatio > 1.15 {
                candidates.append(InsightCandidate(priority: 32, text: L("insight_pace_faster"), tag: "pace"))
            } else if s.spendPaceRatio < 0.85 {
                candidates.append(InsightCandidate(priority: 30, text: L("insight_pace_slower"), tag: "pace"))
            }
        }

        if s.dayOfMonth >= 7 && s.firstHalfSpend > 0 {
            let projected7 = (s.firstHalfSpend / 7) * Double(s.daysInMonth)
            if s.firstHalfSpend > projected7 * 0.40 {
                candidates.append(InsightCandidate(priority: 22, text: L("insight_front_loaded"), tag: "pace"))
            }
        }

        if s.dayOfMonth >= 14 && s.firstHalfSpend > 0 && s.secondHalfSpend > s.firstHalfSpend * 1.4 {
            candidates.append(InsightCandidate(priority: 24, text: L("insight_recent_spike"), tag: "pace"))
        }

        // Weekly pacing
        if s.lastWeekSpent > 0 {
            let pct = Int(abs(s.weekDeltaPercent).rounded())
            if s.weekDeltaPercent < -5 {
                candidates.append(InsightCandidate(priority: abs(s.weekDeltaPercent), text: L("insight_week_down", B("\(pct)")), tag: "pace"))
            } else if s.weekDeltaPercent > 10 {
                candidates.append(InsightCandidate(priority: s.weekDeltaPercent, text: L("insight_week_up", B("\(pct)")), tag: "pace"))
            }
        }

        // Monthly pacing
        if s.lastMonthSpent > 0 {
            let pct = Int(abs(s.monthDeltaPercent).rounded())
            if s.monthDeltaPercent < -5 {
                candidates.append(InsightCandidate(priority: abs(s.monthDeltaPercent) * 0.8, text: L("insight_month_down", B("\(pct)")), tag: "pace"))
            } else if s.monthDeltaPercent > 10 {
                candidates.append(InsightCandidate(priority: s.monthDeltaPercent * 0.8, text: L("insight_month_up", B("\(pct)")), tag: "pace"))
            }
        }

        // ──────────────────────────────────────
        // GROUP 2: Concentration (tag: "concentration")
        // ──────────────────────────────────────

        if s.topCategoryShare > 0.45, let name = s.topCategoryName {
            candidates.append(InsightCandidate(priority: 28, text: L("insight_concentration_cat", B(name)), tag: "concentration"))
        }

        if s.top2CategoriesShare > 0.7 && s.topCategoryShare <= 0.45 {
            candidates.append(InsightCandidate(priority: 24, text: L("insight_two_cats"), tag: "concentration"))
        }

        for (catId, conc) in s.topMerchantShareInCategory {
            if conc.share > 0.6 && conc.merchant != "Unknown" {
                let catName = CategoryIconHelper.displayName(categoryId: catId)
                candidates.append(InsightCandidate(priority: 20, text: L("insight_cat_merchant", B(catName), B(conc.merchant)), tag: "concentration"))
                break
            }
        }

        if s.topMerchantShareTotal > 0.25, let name = s.topMerchantNameTotal, name != "Unknown" {
            let pct = Int((s.topMerchantShareTotal * 100).rounded())
            candidates.append(InsightCandidate(priority: 18, text: L("insight_one_merchant", B(name), B("\(pct)")), tag: "concentration"))
        }

        // ──────────────────────────────────────
        // GROUP 3: Frequency (tag: "habit")
        // ──────────────────────────────────────

        if s.txCountLast3MonthAvg > 0 {
            let ratio = Double(s.txCountThisMonth) / s.txCountLast3MonthAvg
            let avg3 = Int(s.txCountLast3MonthAvg.rounded())
            if ratio > 1.25 {
                candidates.append(InsightCandidate(priority: 22, text: L("insight_more_frequent", B("\(s.txCountThisMonth)"), B("\(avg3)")), tag: "habit"))
            } else if ratio < 0.8 {
                candidates.append(InsightCandidate(priority: 18, text: L("insight_less_frequent", B("\(s.txCountThisMonth)"), B("\(avg3)")), tag: "habit"))
            }
        }

        if s.topFrequentMerchantCount >= 5, let merchant = s.topFrequentMerchant, merchant != "Unknown" {
            candidates.append(InsightCandidate(priority: 20, text: L("insight_returning", B(merchant)), tag: "habit"))
        }

        // Category frequency spike with small amounts
        for (catId, txCount) in s.categoryTxCounts {
            if txCount.avg3Month > 2 && Double(txCount.thisMonth) > txCount.avg3Month * 1.5 {
                if let conc = s.topMerchantShareInCategory[catId] {
                    let catName = CategoryIconHelper.displayName(categoryId: catId)
                    if conc.share < 0.8 {
                        candidates.append(InsightCandidate(priority: 24, text: L("insight_small_adding", B(catName)), tag: "habit"))
                        break
                    }
                }
            }
        }

        // ──────────────────────────────────────
        // GROUP 4: Small Purchases (tag: "habit")
        // ──────────────────────────────────────

        if s.smallTxShare > 0.35 && s.smallTxCount >= 5 {
            let pct = Int((s.smallTxShare * 100).rounded())
            let avgSmall = fmt.string(from: NSNumber(value: s.avgTicketThisMonth)) ?? "$0"
            let topSmallMerchant = s.topFrequentMerchant ?? ""
            if !topSmallMerchant.isEmpty && topSmallMerchant != "Unknown" {
                candidates.append(InsightCandidate(priority: 26, text: L("insight_small_share", B("\(pct)"), B(topSmallMerchant), B(avgSmall)), tag: "habit"))
            } else {
                candidates.append(InsightCandidate(priority: 26, text: L("insight_small_share_no_merchant", B("\(pct)"), B(avgSmall)), tag: "habit"))
            }
        }

        if s.avgTicketLast3Month > 0 && s.avgTicketThisMonth < s.avgTicketLast3Month * 0.85 && s.thisMonthSpent > s.last3MonthAvgSpend {
            let avgNow = fmt.string(from: NSNumber(value: s.avgTicketThisMonth)) ?? "$0"
            let avgBefore = fmt.string(from: NSNumber(value: s.avgTicketLast3Month)) ?? "$0"
            candidates.append(InsightCandidate(priority: 28, text: L("insight_small_more", B(avgNow), B(avgBefore)), tag: "habit"))
        }

        if s.avgTicketLast3Month > 0 && s.avgTicketThisMonth > s.avgTicketLast3Month * 1.15 && s.txCountLast3MonthAvg > 0 {
            let countRatio = Double(s.txCountThisMonth) / s.txCountLast3MonthAvg
            if countRatio > 0.85 && countRatio < 1.15 {
                let avgNow = fmt.string(from: NSNumber(value: s.avgTicketThisMonth)) ?? "$0"
                let avgBefore = fmt.string(from: NSNumber(value: s.avgTicketLast3Month)) ?? "$0"
                candidates.append(InsightCandidate(priority: 21, text: L("insight_avg_higher", B(avgNow), B(avgBefore)), tag: "habit"))
            }
        }

        if s.medianTicketLast3Month > 0 && s.medianTicketThisMonth > s.medianTicketLast3Month * 1.2 {
            let medNow = fmt.string(from: NSNumber(value: s.medianTicketThisMonth)) ?? "$0"
            let medBefore = fmt.string(from: NSNumber(value: s.medianTicketLast3Month)) ?? "$0"
            candidates.append(InsightCandidate(priority: 20, text: L("insight_avg_increased", B(medNow), B(medBefore)), tag: "habit"))
        }

        // ──────────────────────────────────────
        // GROUP 5: Subscriptions (tag: "subscriptions")
        // ──────────────────────────────────────

        if s.committedToIncomeRatio > 0.15 && s.thisMonthIncome > 0 {
            candidates.append(InsightCandidate(priority: 27, text: L("insight_sub_share"), tag: "subscriptions"))
        }

        if s.subscriptionTrend.newSubsCount > 0 {
            let n = s.subscriptionTrend.newSubsCount
            candidates.append(InsightCandidate(priority: 29, text: L("insight_new_subs", B("\(n)"), n == 1 ? "" : "s"), tag: "subscriptions"))
        }

        if s.upcomingBillsNext7Days > 0 && s.safeToSpend > 0 && s.upcomingBillsNext7Days > s.safeToSpend {
            candidates.append(InsightCandidate(priority: 31, text: L("insight_upcoming_bills"), tag: "subscriptions"))
        }

        if s.recurringCostDeltaPercent > 10 {
            candidates.append(InsightCandidate(priority: 23, text: L("insight_recurring_higher"), tag: "subscriptions"))
        }

        // ──────────────────────────────────────
        // GROUP 6: Risk (tag: "risk")
        // ──────────────────────────────────────

        if s.thisMonthIncome > 0 && s.projectedMonthlySpend > s.thisMonthIncome {
            candidates.append(InsightCandidate(priority: 45, text: L("insight_exceed_income"), tag: "risk"))
        }

        if s.thisMonthIncome > 0 && s.safeToSpendRaw < 0 {
            candidates.append(InsightCandidate(priority: 44, text: L("insight_over_safe"), tag: "risk"))
        }

        if s.anomalyCount >= 2 {
            let topAnomalies = s.merchantAnomalies.prefix(2).map { B($0.merchant) }
            let names = topAnomalies.joined(separator: ", ")
            let topAmount = fmt.string(from: NSNumber(value: s.merchantAnomalies.first?.currentSpent ?? 0)) ?? "$0"
            candidates.append(InsightCandidate(priority: 26, text: L("insight_outliers", names, B(topAmount)), tag: "risk"))
        }

        // Category up > 25% with merchant anomaly
        if let topUp = significantDeltas.first(where: { $0.deltaPercent > 25 }),
           let anomaly = s.merchantAnomalies.first(where: { $0.category == topUp.id }) {
            candidates.append(InsightCandidate(priority: 34, text: L("insight_spike", B(topUp.name), B(anomaly.merchant)), tag: "risk"))
        }

        if s.avgWeeklySpend8Weeks > 0 && s.thisWeekSpent > s.avgWeeklySpend8Weeks * 1.4 {
            candidates.append(InsightCandidate(priority: 30, text: L("insight_expensive_week"), tag: "risk"))
        }

        // ──────────────────────────────────────
        // GROUP 7: Positive (tag: "stability")
        // ──────────────────────────────────────

        if s.lastMonthSavings > 0 && s.projectedMonthlySavings > s.lastMonthSavings * 1.2 {
            candidates.append(InsightCandidate(priority: 34, text: L("insight_save_more"), tag: "stability"))
        }

        if let topDown = s.categoryDeltas.first(where: { $0.deltaPercent < -15 && $0.lastMonth > 0 }) {
            candidates.append(InsightCandidate(priority: 25, text: L("insight_cooled_off", B(topDown.name)), tag: "stability"))
        }

        if s.anomalyCount == 0 && s.lastMonthSpent > 0 && abs(s.monthDeltaPercent) < 5 {
            candidates.append(InsightCandidate(priority: 18, text: L("insight_controlled"), tag: "stability"))
        }

        if abs(s.recurringCostDeltaPercent) <= 2 && s.monthDeltaPercent < -5 {
            candidates.append(InsightCandidate(priority: 20, text: L("insight_fixed_steady"), tag: "stability"))
        }

        if s.safeToSpend > 0 && s.spendPaceRatio < 0.9 && s.thisMonthIncome > 0 {
            candidates.append(InsightCandidate(priority: 33, text: L("insight_room_left"), tag: "stability"))
        }

        // Projected savings
        if s.projectedMonthlySavings > 50 && s.thisMonthIncome > 0 {
            candidates.append(InsightCandidate(priority: 40, text: L("insight_on_track", B(fmt.string(from: NSNumber(value: s.projectedMonthlySavings)) ?? "$0")), tag: "stability"))
        }

        // Stable spending (low priority fallback)
        if s.lastMonthSpent > 0 && abs(s.monthDeltaPercent) < 5 {
            candidates.append(InsightCandidate(priority: 5, text: L("insight_steady"), tag: "stability"))
        }

        // ──────────────────────────────────────
        // GROUP 8: Calendar (tag: "calendar")
        // ──────────────────────────────────────

        if s.dayOfMonth <= 7 && s.spendPaceRatio > 1.1 && s.last3MonthAvgSpend > 0 {
            candidates.append(InsightCandidate(priority: 17, text: L("insight_expensive_start"), tag: "calendar"))
        }

        if s.dayOfMonth >= s.daysInMonth - 5 && s.last3MonthAvgSpend > 0 && abs(s.spendPaceRatio - 1.0) < 0.1 {
            candidates.append(InsightCandidate(priority: 16, text: L("insight_ending_usual"), tag: "calendar"))
        }

        if s.weekendAvgSpend > s.weekdayAvgSpend * 1.3 && s.weekdayAvgSpend > 0 && (weekday >= 6 || weekday == 1) {
            candidates.append(InsightCandidate(priority: 22, text: L("insight_weekends_expensive"), tag: "calendar"))
        }

        // Safe to spend (weekends)
        if (weekday >= 6 || weekday == 1) && s.safeToSpend > 0 {
            candidates.append(InsightCandidate(priority: 35, text: L("insight_safe_weekend", B(fmt.string(from: NSNumber(value: s.safeToSpend)) ?? "$0")), tag: "calendar"))
        }

        // Weekend vs weekday pattern (non-calendar-specific)
        if s.weekendAvgSpend > 0 && s.weekdayAvgSpend > 0 && s.weekendAvgSpend > s.weekdayAvgSpend * 1.5 {
            candidates.append(InsightCandidate(priority: 25, text: L("insight_weekend_vs_weekday", B(fmt.string(from: NSNumber(value: s.weekendAvgSpend)) ?? "$0"), B(fmt.string(from: NSNumber(value: s.weekdayAvgSpend)) ?? "$0")), tag: "habit"))
        }

        // ──────────────────────────────────────
        // GROUP 9: Category Comparison (tag: "category")
        // ──────────────────────────────────────

        let catsDown = s.categoryDeltas.filter { $0.deltaPercent < -15 && $0.lastMonth > 0 }
        let catsUp = s.categoryDeltas.filter { $0.deltaPercent > 15 && $0.lastMonth > 0 }

        if let down = catsDown.first, let up = catsUp.first {
            candidates.append(InsightCandidate(priority: 24, text: L("insight_less_more", B(down.name), B(up.name)), tag: "category"))
        }

        if significantDeltas.count >= 2 {
            let growing = significantDeltas.filter { $0.deltaPercent > 0 }.first
            let shrinking = significantDeltas.filter { $0.deltaPercent < 0 }.first
            if let g = growing, let sh = shrinking {
                candidates.append(InsightCandidate(priority: 23, text: L("insight_rose_cooled", B(g.name), B(sh.name)), tag: "category"))
            }
        }

        // Top category shift
        if let top = significantDeltas.first {
            let dir = top.deltaPercent < 0 ? L("direction_down") : L("direction_up")
            let pct = Int(abs(top.deltaPercent).rounded())
            candidates.append(InsightCandidate(priority: abs(top.deltaPercent) * 0.7, text: L("insight_cat_direction", B(top.name), dir, B("\(pct)")), tag: "category"))
        }

        // Two category shifts combined (only when they move in opposite directions)
        if significantDeltas.count >= 2 {
            let a = significantDeltas[0]
            let b = significantDeltas[1]
            if (a.deltaPercent > 0) != (b.deltaPercent > 0) {
                let aDir = a.deltaPercent < 0 ? L("direction_down") : L("direction_up")
                let bDir = b.deltaPercent < 0 ? L("direction_slightly_lower") : L("direction_slightly_higher")
                candidates.append(InsightCandidate(priority: abs(a.deltaPercent) * 0.6,
                    text: L("insight_cat_direction_but", B(a.name), aDir, B("\(Int(abs(a.deltaPercent)))"), B(b.name.lowercased()), bDir), tag: "category"))
            }
        }

        if s.categoryDeltas.count >= 3 {
            let top3 = Array(s.categoryDeltas.prefix(3))
            if top3.allSatisfy({ abs($0.deltaPercent) < 10 || $0.lastMonth == 0 }) && s.lastMonthSpent > 0 {
                candidates.append(InsightCandidate(priority: 14, text: L("insight_cats_in_line"), tag: "category"))
            }
        }

        // ──────────────────────────────────────
        // GROUP 10: Merchant-specific (tag: "merchant")
        // ──────────────────────────────────────

        if let streak = s.repeatedMerchantStreak, streak.days >= 3 {
            candidates.append(InsightCandidate(priority: 18, text: L("insight_merchant_often", B(streak.merchant)), tag: "merchant"))
        }

        // Top merchant in shifted category
        if let topCatDelta = significantDeltas.first(where: { abs($0.deltaPercent) > 15 }),
           let topMerch = s.topMerchantByCategory[topCatDelta.id] {
            candidates.append(InsightCandidate(priority: 20, text: L("insight_cat_higher_merchant", B(topCatDelta.name), B(topMerch.merchant)), tag: "merchant"))
        }

        if s.newMerchantCount > 0 {
            candidates.append(InsightCandidate(priority: 17, text: L("insight_new_merchant"), tag: "merchant"))
        }

        // ──────────────────────────────────────
        // Tag-based selection with time-of-day rotation
        // ──────────────────────────────────────

        candidates.sort { $0.priority > $1.priority }

        if candidates.isEmpty {
            return s.thisMonthSpent > 0
                ? L("insight_in_line")
                : L("insight_start_adding")
        }

        // Rotate 3× daily: slot 0 (00-08), 1 (08-16), 2 (16-24)
        // Combined with day-of-month so each slot+day is unique
        let hour = cal.component(.hour, from: Date())
        let slot = hour / 8                         // 0, 1, or 2
        let rotationSeed = s.dayOfMonth * 3 + slot + offset  // unique per slot per day per caller

        // Build valid (primary, secondary) pairs from top candidates
        // then pick pair based on rotationSeed
        var pairs: [(InsightCandidate, InsightCandidate?)] = []
        for (i, candidate) in candidates.enumerated() {
            let secondary = candidates.dropFirst(i + 1).first {
                $0.tag != candidate.tag && !textOverlaps(candidate.text, $0.text)
            }
            pairs.append((candidate, secondary))
            if pairs.count >= 6 { break } // enough variety
        }

        let idx = rotationSeed % pairs.count
        let (primary, secondary) = pairs[idx]

        if let secondary {
            return "\(primary.text) \(secondary.text)"
        }
        return primary.text
    }

    // MARK: - Helpers

    private func monthKey(for date: Date) -> String {
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        return String(format: "%04d-%02d", y, m)
    }

    private func weekBounds(for date: Date) -> (start: Date, end: Date) {
        let weekday = cal.component(.weekday, from: date) // 1=Sun
        let mondayOffset = weekday == 1 ? -6 : (2 - weekday)
        let monday = cal.date(byAdding: .day, value: mondayOffset, to: cal.startOfDay(for: date)) ?? date
        let sunday = cal.date(byAdding: .day, value: 6, to: monday) ?? date
        return (monday, sunday)
    }

    private func emojiForCategory(_ catId: String) -> String {
        let c = catId.lowercased()
        if c.contains("food") || c.contains("dining") || c.contains("grocer") { return "🍱" }
        if c.contains("transport") || c.contains("transit") { return "🚗" }
        if c.contains("housing") || c.contains("rent") { return "🏠" }
        if c.contains("shopping") { return "🛍️" }
        if c.contains("health") { return "💊" }
        if c.contains("bill") || c.contains("util") { return "📄" }
        if c.contains("travel") { return "✈️" }
        if c.contains("entertain") { return "🎬" }
        if c.contains("sub") { return "📺" }
        if c.contains("education") { return "📚" }
        return "📊"
    }

    private func currencyFormatter() -> NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = BaseCurrencyStore.baseCurrency
        f.maximumFractionDigits = 0
        f.minimumFractionDigits = 0
        return f
    }

    private func textOverlaps(_ a: String, _ b: String) -> Bool {
        let strip = { (s: String) in s.replacingOccurrences(of: "**", with: "") }
        let aWords = Set(strip(a).lowercased().split(separator: " ").map(String.init))
        let bWords = Set(strip(b).lowercased().split(separator: " ").map(String.init))
        let shared = aWords.intersection(bWords).subtracting(["is", "a", "the", "your", "you", "this", "than", "of", "to", "in", "more"])
        return shared.count > 3
    }

    private func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    private func dayComponent(from dateString: String) -> Int? {
        let prefix = dateString.prefix(10) // "yyyy-MM-dd"
        guard prefix.count == 10 else { return nil }
        let parts = prefix.split(separator: "-")
        guard parts.count == 3 else { return nil }
        return Int(parts[2])
    }

    private func consecutiveDayStreak(dates: [String]) -> Int {
        guard dates.count >= 2 else { return dates.count }
        var maxStreak = 1
        var current = 1
        for i in 1..<dates.count {
            if let prev = dateFmt.date(from: dates[i - 1]),
               let curr = dateFmt.date(from: dates[i]),
               let diff = cal.dateComponents([.day], from: prev, to: curr).day,
               diff == 1 {
                current += 1
                maxStreak = max(maxStreak, current)
            } else {
                current = 1
            }
        }
        return maxStreak
    }

    private func subMonthlyTotals(
        byMonth: [String: [LocalTransaction]],
        thisMonthKey: String,
        allExpenses: [LocalTransaction],
        shouldCount: (LocalTransaction) -> Bool,
        amountInBase: (LocalTransaction) -> Double
    ) -> Double {
        (byMonth[thisMonthKey] ?? [])
            .filter { $0.isSubscription == true }
            .reduce(0.0) { $0 + amountInBase($1) }
    }
}
