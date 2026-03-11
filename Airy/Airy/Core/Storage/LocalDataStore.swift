//
//  LocalDataStore.swift
//  Airy
//
//  Local-only data: SwiftData CRUD, analytics, insights. No backend.
//

import Foundation
import SwiftData

@MainActor
final class LocalDataStore {
    static let shared = LocalDataStore()

    var modelContainer: ModelContainer?

    init() {}

    func configure(container: ModelContainer) {
        modelContainer = container
    }

    var context: ModelContext? { modelContainer?.mainContext }

    // MARK: - Transactions

    func fetchTransactions(limit: Int = 100, month: String? = nil, year: String? = nil) -> [Transaction] {
        guard let ctx = context else { return [] }
        var descriptor = FetchDescriptor<LocalTransaction>(
            sortBy: [SortDescriptor(\.transactionDate, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        if let m = month, let y = year, let yy = Int(y), let mm = Int(m), mm >= 1, mm <= 12 {
            let startDate = "\(y)-\(m)-01"
            let (endYear, endMonth): (String, String) = mm == 12
                ? (String(yy + 1), "01")
                : (y, String(format: "%02d", mm + 1))
            let endDate = "\(endYear)-\(endMonth)-01"
            descriptor.predicate = #Predicate<LocalTransaction> { tx in
                tx.transactionDate >= startDate && tx.transactionDate < endDate
            }
        }
        guard let list = try? ctx.fetch(descriptor) else { return [] }
        return list.map { $0.toTransaction() }
    }

    func createTransaction(_ body: CreateTransactionBody) throws -> Transaction {
        guard let ctx = context else { throw LocalStoreError.noContext }
        let tx = LocalTransaction(
            type: body.type,
            amountOriginal: body.amountOriginal,
            currencyOriginal: body.currencyOriginal,
            amountBase: body.amountBase,
            baseCurrency: body.baseCurrency,
            merchant: body.merchant,
            title: body.title,
            transactionDate: body.transactionDate,
            transactionTime: body.transactionTime,
            category: body.category,
            subcategory: body.subcategory,
            isSubscription: body.isSubscription,
            sourceType: body.sourceType ?? "manual"
        )
        ctx.insert(tx)
        try ctx.save()
        return tx.toTransaction()
    }

    func updateTransaction(id: String, body: UpdateTransactionBody) throws -> Transaction {
        guard let ctx = context else { throw LocalStoreError.noContext }
        var descriptor = FetchDescriptor<LocalTransaction>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let tx = try ctx.fetch(descriptor).first else { throw LocalStoreError.notFound }
        if let v = body.amountOriginal { tx.amountOriginal = v }
        if let v = body.amountBase { tx.amountBase = v }
        if let v = body.merchant { tx.merchant = v }
        if let v = body.category { tx.category = v }
        if let v = body.subcategory { tx.subcategory = v }
        if let v = body.transactionDate { tx.transactionDate = v }
        if let v = body.comment { tx.title = v }
        tx.updatedAt = Date()
        try ctx.save()
        return tx.toTransaction()
    }

    func deleteTransaction(id: String) throws {
        guard let ctx = context else { throw LocalStoreError.noContext }
        var descriptor = FetchDescriptor<LocalTransaction>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let tx = try ctx.fetch(descriptor).first else { throw LocalStoreError.notFound }
        ctx.delete(tx)
        try ctx.save()
    }

    // MARK: - Pending

    func fetchPendingTransactions() -> [PendingTransaction] {
        guard let ctx = context else { return [] }
        let descriptor = FetchDescriptor<LocalPendingTransaction>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        guard let list = try? ctx.fetch(descriptor) else { return [] }
        return list.map { $0.toPendingTransaction() }
    }

    func addPendingTransaction(payload: PendingTransactionPayload, ocrText: String?, sourceImageHash: String?) {
        guard let ctx = context else { return }
        let pending = LocalPendingTransaction(
            payload: payload,
            ocrText: ocrText,
            sourceImageHash: sourceImageHash
        )
        ctx.insert(pending)
        try? ctx.save()
    }

    func confirmPending(id: String, overrides: ConfirmPendingOverrides?) -> Bool {
        guard let ctx = context else { return false }
        var descriptor = FetchDescriptor<LocalPendingTransaction>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let pending = try? ctx.fetch(descriptor).first,
              let payload = pending.decodedPayload else { return false }
        let merged = mergePayloadWithOverrides(payload, overrides)
        let tx = LocalTransaction(
            type: merged.type ?? "expense",
            amountOriginal: merged.amountOriginal ?? 0,
            currencyOriginal: merged.currencyOriginal ?? "USD",
            amountBase: merged.amountBase ?? merged.amountOriginal ?? 0,
            baseCurrency: merged.baseCurrency ?? "USD",
            merchant: merged.merchant,
            transactionDate: merged.transactionDate ?? ISO8601DateFormatter().string(from: Date()).prefix(10).description,
            transactionTime: merged.transactionTime,
            category: merged.category ?? "other",
            subcategory: merged.subcategory,
            sourceType: "screenshot",
            sourceImageHash: pending.sourceImageHash
        )
        ctx.insert(tx)
        ctx.delete(pending)
        try? ctx.save()
        return true
    }

    func rejectPending(id: String) {
        guard let ctx = context else { return }
        var descriptor = FetchDescriptor<LocalPendingTransaction>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let pending = try? ctx.fetch(descriptor).first else { return }
        ctx.delete(pending)
        try? ctx.save()
    }

    private func mergePayloadWithOverrides(_ p: PendingTransactionPayload, _ o: ConfirmPendingOverrides?) -> PendingTransactionPayload {
        guard let o = o, !o.isEmpty else { return p }
        return PendingTransactionPayload(
            type: o.type ?? p.type,
            amountOriginal: o.amountOriginal ?? p.amountOriginal,
            currencyOriginal: o.currencyOriginal ?? p.currencyOriginal,
            amountBase: o.amountBase ?? p.amountBase,
            baseCurrency: o.baseCurrency ?? p.baseCurrency,
            merchant: o.merchant ?? p.merchant,
            title: p.title,
            transactionDate: o.transactionDate ?? p.transactionDate,
            transactionTime: o.transactionTime ?? p.transactionTime,
            category: o.category ?? p.category,
            subcategory: o.subcategory ?? p.subcategory
        )
    }

    // MARK: - Analytics (local)

    func dashboardSummary() -> (thisMonth: MonthSummary, previousMonthSpent: Double, deltaPercent: Double) {
        let all = fetchTransactions(limit: 500)
        let cal = Calendar.current
        let now = Date()
        let thisMonthKey = monthKey(for: now)
        let lastMonth = cal.date(byAdding: .month, value: -1, to: now) ?? now
        let lastMonthKey = monthKey(for: lastMonth)

        var thisSpent: Double = 0
        var thisIncome: Double = 0
        var thisByCategory: [String: Double] = [:]
        var lastSpent: Double = 0

        for tx in all {
            let key = String(tx.transactionDate.prefix(7))
            if key == thisMonthKey {
                if tx.type.lowercased() == "income" {
                    thisIncome += tx.amountOriginal
                } else {
                    thisSpent += tx.amountOriginal
                    thisByCategory[tx.category, default: 0] += tx.amountOriginal
                }
            } else if key == lastMonthKey, tx.type.lowercased() != "income" {
                lastSpent += tx.amountOriginal
            }
        }

        let delta = lastSpent > 0 ? ((thisSpent - lastSpent) / lastSpent) * 100 : 0
        let thisMonth = MonthSummary(
            totalSpent: thisSpent,
            totalIncome: thisIncome,
            byCategory: thisByCategory.isEmpty ? nil : thisByCategory,
            transactionCount: nil
        )
        return (thisMonth, lastSpent, delta)
    }

    func subscriptionsFromTransactions() -> [Subscription] {
        let all = fetchTransactions(limit: 500)
        let subs = all.filter { $0.isSubscription == true }
        var byMerchant: [String: (amount: Double, currency: String, dates: [String])] = [:]
        for tx in subs {
            let m = tx.merchant ?? "Unknown"
            var entry = byMerchant[m] ?? (0, "USD", [String]())
            entry.0 += tx.amountOriginal
            entry.1 = tx.currencyOriginal
            entry.2.append(tx.transactionDate)
            byMerchant[m] = entry
        }
        return byMerchant.enumerated().map { i, kv in
            let (merchant, (amount, currency, dates)) = kv
            let sorted = dates.sorted().reversed()
            let nextDate = sorted.first
            return Subscription(
                id: "sub-\(i)-\(merchant)",
                merchant: merchant,
                amount: amount / max(1, Double(dates.count)),
                currency: currency,
                interval: "monthly",
                nextBillingDate: nextDate,
                status: "active"
            )
        }
    }

    func monthlySummary(month: String?) -> (summary: String, deltaPercent: Double) {
        let (_, _, delta) = dashboardSummary()
        let s: String
        if delta < 0 {
            s = "Spending is down \(Int(abs(delta)))% vs last month. Keep it up."
        } else if delta > 0 {
            s = "Spending is up \(Int(delta))% vs last month. Review your habits."
        } else {
            s = "Your spending is in line with last month."
        }
        return (s, delta)
    }

    func behavioralInsights() -> [InsightItem] {
        let (thisMonth, _, delta) = dashboardSummary()
        var items: [InsightItem] = []
        if delta < 0 {
            items.append(InsightItem(type: "positive", title: "Spending down", body: "You spent \(Int(abs(delta)))% less this month. Great progress!", metricRef: nil))
        } else if delta > 0 {
            items.append(InsightItem(type: "alert", title: "Spending up", body: "Spending increased \(Int(delta))% vs last month. Consider reviewing top categories.", metricRef: nil))
        }
        if let byCat = thisMonth.byCategory, !byCat.isEmpty {
            let top = byCat.sorted { $0.value > $1.value }.prefix(1)
            if let (cat, amt) = top.first {
                items.append(InsightItem(type: "category", title: "Top category", body: "\(cat): \(formatCurrency(amt)) this month.", metricRef: cat))
            }
        }
        if items.isEmpty {
            items.append(InsightItem(type: nil, title: "Getting started", body: "Add transactions to see personalized insights.", metricRef: nil))
        }
        return items
    }

    func duplicateByHash(_ hash: String) -> Bool {
        guard let ctx = context else { return false }
        let txDescriptor = FetchDescriptor<LocalTransaction>(
            predicate: #Predicate { $0.sourceImageHash == hash }
        )
        if (try? ctx.fetchCount(txDescriptor)) ?? 0 > 0 { return true }
        let pendingDescriptor = FetchDescriptor<LocalPendingTransaction>(
            predicate: #Predicate { $0.sourceImageHash == hash }
        )
        return (try? ctx.fetchCount(pendingDescriptor)) ?? 0 > 0
    }

    private func monthKey(for date: Date) -> String {
        let cal = Calendar.current
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        return String(format: "%04d-%02d", y, m)
    }

    private func formatCurrency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$0"
    }
}

enum LocalStoreError: Error {
    case noContext
    case notFound
}
