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

        let thisMonthSpent = monthTotal(thisMonthKey)
        let lastMonthSpent = monthTotal(lastMonthKey)
        let monthDelta = lastMonthSpent > 0 ? ((thisMonthSpent - lastMonthSpent) / lastMonthSpent) * 100 : 0

        // Category breakdown for this & last month
        var thisByCat: [String: Double] = [:]
        var lastByCat: [String: Double] = [:]
        for tx in byMonth[thisMonthKey] ?? [] {
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

        // Top merchant per category (this month)
        var merchantByCat: [String: [String: Double]] = [:]
        for tx in byMonth[thisMonthKey] ?? [] {
            let m = tx.merchant ?? "Unknown"
            merchantByCat[tx.category, default: [:]][m, default: 0] += amountInBase(tx)
        }
        var topMerchantByCategory: [String: MerchantStat] = [:]
        for (cat, merchants) in merchantByCat {
            if let top = merchants.max(by: { $0.value < $1.value }) {
                topMerchantByCategory[cat] = MerchantStat(merchant: top.key, totalSpent: top.value)
            }
        }

        // Weekly spending
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

        // Daily average & projections
        let dayOfMonth = cal.component(.day, from: now)
        let daysInMonth = cal.range(of: .day, in: .month, for: now)?.count ?? 30
        let dailyAvg = dayOfMonth > 0 ? thisMonthSpent / Double(dayOfMonth) : 0
        let projectedSpend = dailyAvg * Double(daysInMonth)

        // Income & safe-to-spend
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
        let safeToSpend = thisMonthIncome > 0
            ? max(thisMonthIncome - thisMonthSpent - committedRemaining, 0)
            : 0

        // Merchant anomalies (compare this month vs avg of 3 prior months)
        var merchantAnomalies: [MerchantAnomaly] = []
        let priorMonthKeys = (1...3).compactMap { offset -> String? in
            guard let d = cal.date(byAdding: .month, value: -offset, to: now) else { return nil }
            return monthKey(for: d)
        }
        var merchantThisMonth: [String: (total: Double, category: String)] = [:]
        for tx in byMonth[thisMonthKey] ?? [] {
            let m = tx.merchant ?? "Unknown"
            let existing = merchantThisMonth[m]
            merchantThisMonth[m] = (total: (existing?.total ?? 0) + amountInBase(tx), category: existing?.category ?? tx.category)
        }
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

        // Weekday vs weekend average (exclude subscriptions — they're recurring, not behavioral)
        var weekdayTotal: Double = 0; var weekdayDays = Set<String>()
        var weekendTotal: Double = 0; var weekendDays = Set<String>()
        for tx in (byMonth[thisMonthKey] ?? []) where tx.isSubscription != true {
            let dateStr = String(tx.transactionDate.prefix(10))
            if let d = dateFmt.date(from: dateStr) {
                let wd = cal.component(.weekday, from: d) // 1=Sun, 7=Sat
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

        // Monthly history (12 months)
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

        // Subscription trend (6 months)
        var subMonthlyTotals: [(monthKey: String, total: Double)] = []
        for offset in stride(from: 5, through: 0, by: -1) {
            guard let d = cal.date(byAdding: .month, value: -offset, to: now) else { continue }
            let mk = monthKey(for: d)
            let subTotal = (byMonth[mk] ?? []).filter { $0.isSubscription == true }.reduce(0.0) { $0 + amountInBase($1) }
            // Also add subscription templates that weren't counted as expenses
            let templateTotal = allExpenses.filter { tx in
                tx.isSubscription == true && String(tx.transactionDate.prefix(7)) == mk && shouldCount(tx)
            }.reduce(0.0) { $0 + amountInBase($1) }
            subMonthlyTotals.append((monthKey: mk, total: subTotal + templateTotal))
        }
        let subDelta = subMonthlyTotals.count >= 2
            ? (subMonthlyTotals.last?.total ?? 0) - (subMonthlyTotals.first?.total ?? 0)
            : 0
        let thirtyDaysAgo = dateFmt.string(from: cal.date(byAdding: .day, value: -30, to: now) ?? now)
        let newTrials = subs.filter { sub in
            guard let tid = sub.templateTransactionId else { return false }
            return allExpenses.first { $0.id == tid }?.transactionDate ?? "" >= thirtyDaysAgo
        }.count

        let totalTxCount = (byMonth[thisMonthKey] ?? []).count + (byMonth[lastMonthKey] ?? []).count

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
                monthlyTotals: subMonthlyTotals,
                deltaAmount: subDelta,
                newTrialsCount: newTrials
            ),
            totalTransactionCount: totalTxCount,
            computedAt: now
        )
    }

    // MARK: - Text Generation

    func generateSummaryText(_ s: SpendingSnapshot) -> String {
        guard s.totalTransactionCount >= 5 else {
            return "Keep tracking to unlock personalized insights."
        }

        var candidates: [(priority: Double, text: String)] = []
        let fmt = currencyFormatter()

        // Weekly pacing
        if s.lastWeekSpent > 0 {
            let pct = Int(abs(s.weekDeltaPercent).rounded())
            if s.weekDeltaPercent < -5 {
                candidates.append((abs(s.weekDeltaPercent), "Spending is down \(pct)% this week."))
            } else if s.weekDeltaPercent > 10 {
                candidates.append((s.weekDeltaPercent, "Spending is up \(pct)% this week."))
            }
        }

        // Monthly pacing
        if s.lastMonthSpent > 0 {
            let pct = Int(abs(s.monthDeltaPercent).rounded())
            if s.monthDeltaPercent < -5 {
                candidates.append((abs(s.monthDeltaPercent) * 0.8, "You spent \(pct)% less this month."))
            } else if s.monthDeltaPercent > 10 {
                candidates.append((s.monthDeltaPercent * 0.8, "Spending is up \(pct)% vs last month."))
            }
        }

        // Projected savings
        if s.projectedMonthlySavings > 50 && s.thisMonthIncome > 0 {
            candidates.append((40, "You're on track to save \(fmt.string(from: NSNumber(value: s.projectedMonthlySavings)) ?? "$0") this month."))
        }

        // Safe to spend (weekends)
        let weekday = cal.component(.weekday, from: Date())
        if (weekday >= 6 || weekday == 1) && s.safeToSpend > 0 {
            candidates.append((35, "You have roughly \(fmt.string(from: NSNumber(value: s.safeToSpend)) ?? "$0") safe to spend this weekend."))
        }

        // Top category shift
        let significantDeltas = s.categoryDeltas.filter { abs($0.deltaPercent) > 10 && $0.lastMonth > 0 }
        if let top = significantDeltas.first {
            let dir = top.deltaPercent < 0 ? "down" : "up"
            let pct = Int(abs(top.deltaPercent).rounded())
            candidates.append((abs(top.deltaPercent) * 0.7, "\(top.name) is \(dir) \(pct)%."))
        }

        // Two significant category shifts
        if significantDeltas.count >= 2 {
            let a = significantDeltas[0]
            let b = significantDeltas[1]
            let aDir = a.deltaPercent < 0 ? "down" : "up"
            let bDir = b.deltaPercent < 0 ? "down" : "slightly higher"
            candidates.append((abs(a.deltaPercent) * 0.6,
                "\(a.name) is \(aDir) \(Int(abs(a.deltaPercent)))%, but \(b.name.lowercased()) costs are \(bDir) than usual."))
        }

        // Weekend vs weekday pattern
        if s.weekendAvgSpend > 0 && s.weekdayAvgSpend > 0 && s.weekendAvgSpend > s.weekdayAvgSpend * 1.5 {
            candidates.append((25, "You tend to spend more on weekends — \(fmt.string(from: NSNumber(value: s.weekendAvgSpend)) ?? "$0")/day vs \(fmt.string(from: NSNumber(value: s.weekdayAvgSpend)) ?? "$0") on weekdays."))
        }

        // Top merchant insight
        if let topCatDelta = significantDeltas.first(where: { abs($0.deltaPercent) > 15 }),
           let topMerch = s.topMerchantByCategory[topCatDelta.id] {
            candidates.append((20, "\(topCatDelta.name) is tracking higher than usual, mostly at \(topMerch.merchant)."))
        }

        // Stable spending
        if s.lastMonthSpent > 0 && abs(s.monthDeltaPercent) < 5 {
            candidates.append((5, "Your spending is steady this month."))
        }

        // Sort by priority, pick top 2
        candidates.sort { $0.priority > $1.priority }

        if candidates.isEmpty {
            return s.thisMonthSpent > 0
                ? "Your spending is in line with last month."
                : "Start adding transactions to see insights."
        }

        // Pick best primary + compatible secondary
        let primary = candidates[0].text
        let secondary = candidates.dropFirst().first(where: { !textOverlaps(primary, $0.text) })?.text

        if let secondary {
            return "\(primary) \(secondary)"
        }
        return primary
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
        let aWords = Set(a.lowercased().split(separator: " ").map(String.init))
        let bWords = Set(b.lowercased().split(separator: " ").map(String.init))
        let shared = aWords.intersection(bWords).subtracting(["is", "a", "the", "your", "you", "this", "than"])
        return shared.count > 3
    }
}
