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
            sortBy: [
                SortDescriptor(\.transactionDate, order: .reverse),
                SortDescriptor(\.createdAt, order: .reverse)
            ]
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
        let userBase = BaseCurrencyStore.baseCurrency
        let baseAmount = CurrencyService.convert(amount: body.amountOriginal, from: body.currencyOriginal, to: userBase)
        let tx = LocalTransaction(
            type: body.type,
            amountOriginal: body.amountOriginal,
            currencyOriginal: body.currencyOriginal,
            amountBase: baseAmount,
            baseCurrency: userBase,
            merchant: body.merchant,
            title: body.title,
            transactionDate: body.transactionDate,
            transactionTime: body.transactionTime,
            category: body.category,
            subcategory: body.subcategory,
            isSubscription: body.isSubscription,
            subscriptionInterval: body.subscriptionInterval,
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
        if let v = body.amountOriginal {
            tx.amountOriginal = v
            tx.amountBase = CurrencyService.convert(amount: v, from: tx.currencyOriginal, to: BaseCurrencyStore.baseCurrency)
        } else if let v = body.amountBase {
            tx.amountBase = v
        }
        if let v = body.merchant { tx.merchant = v }
        if let v = body.category { tx.category = v }
        if let v = body.subcategory { tx.subcategory = v }
        if let v = body.transactionDate { tx.transactionDate = v }
        if let v = body.isSubscription { tx.isSubscription = v }
        if let v = body.subscriptionInterval { tx.subscriptionInterval = v }
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
        setPinned(id: id, pinned: false)
    }

    private let pinnedIdsKey = "pinnedTransactionIds"

    func pinnedTransactionIds() -> Set<String> {
        guard let arr = UserDefaults.standard.array(forKey: pinnedIdsKey) as? [String] else { return [] }
        return Set(arr)
    }

    func setPinned(id: String, pinned: Bool) {
        var ids = pinnedTransactionIds()
        if pinned {
            ids.insert(id)
        } else {
            ids.remove(id)
        }
        UserDefaults.standard.set(Array(ids), forKey: pinnedIdsKey)
    }

    /// Reassigns all transactions from a category to a target category (used when deleting a category).
    func reassignTransactions(fromCategory categoryId: String, toCategory targetId: String) {
        guard let ctx = context else { return }
        let descriptor = FetchDescriptor<LocalTransaction>(predicate: #Predicate<LocalTransaction> { $0.category == categoryId })
        guard let list = try? ctx.fetch(descriptor) else { return }
        for tx in list {
            tx.category = targetId
            tx.subcategory = nil
        }
        try? ctx.save()
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

    func confirmPending(id: String, overrides: ConfirmPendingOverrides? = nil, rememberMerchant: Bool = true) -> Bool {
        guard let ctx = context else { return false }
        var descriptor = FetchDescriptor<LocalPendingTransaction>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let pending = try? ctx.fetch(descriptor).first,
              let payload = pending.decodedPayload else { return false }
        if rememberMerchant, let o = overrides {
            if let corrected = o.merchant, !corrected.isEmpty, corrected != (payload.merchant ?? "Transaction"),
               let amt = payload.amountOriginal ?? o.amountOriginal,
               let dt = payload.transactionDate ?? o.transactionDate {
                MerchantCorrectionStore.shared.saveCorrection(
                    amount: amt,
                    date: dt,
                    originalMerchant: payload.merchant,
                    correctedMerchant: corrected
                )
            }
            if o.category != nil || o.subcategoryId != nil {
                let merchant = payload.merchant ?? "Transaction"
                let catId = o.category ?? payload.category ?? "other"
                MerchantCategoryRuleStore.shared.save(merchant: merchant, categoryId: catId, subcategoryId: o.subcategoryId)
            }
        }
        let merged = mergePayloadWithOverrides(payload, overrides)
        let userBase = BaseCurrencyStore.baseCurrency
        let orig = merged.amountOriginal ?? 0
        let curr = merged.currencyOriginal ?? "USD"
        let baseAmount = CurrencyService.convert(amount: orig, from: curr, to: userBase)
        let tx = LocalTransaction(
            type: merged.type ?? "expense",
            amountOriginal: orig,
            currencyOriginal: curr,
            amountBase: baseAmount,
            baseCurrency: userBase,
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
            subcategory: o.subcategoryId ?? o.subcategory ?? p.subcategory
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
            let inBase = CurrencyService.amountInBase(amountOriginal: abs(tx.amountOriginal), currencyOriginal: tx.currencyOriginal, amountBase: tx.amountBase, baseCurrency: tx.baseCurrency)
            if key == thisMonthKey {
                if tx.type.lowercased() == "income" {
                    thisIncome += CurrencyService.amountInBase(amountOriginal: tx.amountOriginal, currencyOriginal: tx.currencyOriginal, amountBase: tx.amountBase, baseCurrency: tx.baseCurrency)
                } else if tx.isSubscription != true {
                    thisSpent += inBase
                    thisByCategory[tx.category, default: 0] += inBase
                }
            } else if key == lastMonthKey, tx.type.lowercased() != "income", tx.isSubscription != true {
                lastSpent += inBase
            }
        }

        let delta = lastSpent > 0 ? ((thisSpent - lastSpent) / lastSpent) * 100 : 0
        // #region agent log
        let payload: [String: Any] = [
            "sessionId": "ad783c",
            "location": "LocalDataStore.dashboardSummary",
            "message": "dashboard totals",
            "data": ["thisSpent": thisSpent, "thisIncome": thisIncome, "byCategoryCount": thisByCategory.count],
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "hypothesisId": "H1"
        ]
        if let json = try? JSONSerialization.data(withJSONObject: payload),
           let line = String(data: json, encoding: .utf8) {
            let path = "/Users/oduvanchik/Desktop/Airy/.cursor/debug-ad783c.log"
            let lineData = (line + "\n").data(using: .utf8)!
            if FileManager.default.fileExists(atPath: path) {
                if let h = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
                    defer { try? h.close() }
                    h.seekToEndOfFile()
                    h.write(lineData)
                }
            } else {
                FileManager.default.createFile(atPath: path, contents: lineData, attributes: nil)
            }
        }
        // #endregion
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
        return subs.enumerated().map { i, tx in
            let interval = tx.subscriptionInterval ?? "monthly"
            let nextBillingDate = addInterval(to: tx.transactionDate, interval: interval)
            return Subscription(
                id: "sub-\(i)-\(tx.id)",
                merchant: tx.merchant ?? "Unknown",
                amount: tx.amountOriginal,
                currency: tx.currencyOriginal,
                interval: interval,
                nextBillingDate: nextBillingDate,
                status: "active",
                templateTransactionId: tx.id,
                categoryId: tx.category,
                subcategoryId: tx.subcategory,
                title: tx.title
            )
        }
    }

    /// When a subscription's nextBillingDate is today or in the past, creates an expense transaction and advances the template date.
    func processDueSubscriptions() {
        guard let ctx = context else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        let todayStr = formatter.string(from: Date())
        let subs = subscriptionsFromTransactions()
        for sub in subs {
            guard let due = sub.nextBillingDate, due <= todayStr, let templateId = sub.templateTransactionId else { continue }
            var descriptor = FetchDescriptor<LocalTransaction>(predicate: #Predicate<LocalTransaction> { $0.id == templateId })
            descriptor.fetchLimit = 1
            guard let template = try? ctx.fetch(descriptor).first else { continue }
            let body = CreateTransactionBody(
                type: "expense",
                amountOriginal: sub.amount,
                currencyOriginal: sub.currency,
                amountBase: template.amountBase,
                baseCurrency: template.baseCurrency,
                merchant: sub.merchant,
                title: template.title,
                transactionDate: due,
                transactionTime: nil,
                category: template.category,
                subcategory: template.subcategory,
                isSubscription: false,
                subscriptionInterval: nil,
                comment: nil,
                sourceType: "subscription_payment"
            )
            do {
                _ = try createTransaction(body)
                _ = try updateTransaction(id: templateId, body: UpdateTransactionBody(amountOriginal: nil, amountBase: nil, merchant: nil, category: nil, subcategory: nil, transactionDate: due, isSubscription: nil, subscriptionInterval: nil, comment: nil))
            } catch {}
        }
    }

    private func addInterval(to dateStr: String, interval: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        guard let date = formatter.date(from: String(dateStr.prefix(10))) else { return dateStr }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let (component, value): (Calendar.Component, Int) = {
            switch interval.lowercased() {
            case "weekly": return (.day, 7)
            case "yearly": return (.year, 1)
            default: return (.month, 1)
            }
        }()
        // First payment date = date added + one interval (e.g. 03.13 → 04.13 for monthly)
        var next = cal.date(byAdding: component, value: value, to: date) ?? date
        while next < today, let d = cal.date(byAdding: component, value: value, to: next) {
            next = d
        }
        return formatter.string(from: next)
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

    /// True if a transaction with same merchant, same date, same amount already exists (saved or pending).
    func isExactDuplicateTransaction(merchant: String?, date: String, amount: Double) -> Bool {
        let dateStr = String(date.prefix(10))
        let merchantLower = (merchant ?? "").lowercased()
        guard !merchantLower.isEmpty else { return false }
        let transactions = fetchTransactions(limit: 500)
        for tx in transactions {
            guard abs(tx.amountOriginal - amount) < 0.01 else { continue }
            guard String(tx.transactionDate.prefix(10)) == dateStr else { continue }
            let txMerchant = (tx.merchant ?? "").lowercased()
            guard txMerchant.contains(merchantLower) || merchantLower.contains(txMerchant) else { continue }
            return true
        }
        let pendingList = fetchPendingTransactions()
        for p in pendingList {
            guard let pl = p.decodedPayload,
                  let amt = pl.amountOriginal,
                  abs(amt - amount) < 0.01,
                  let pd = pl.transactionDate,
                  String(pd.prefix(10)) == dateStr,
                  let pm = pl.merchant, !pm.isEmpty else { continue }
            let pmLower = pm.lowercased()
            guard pmLower.contains(merchantLower) || merchantLower.contains(pmLower) else { continue }
            return true
        }
        return false
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
