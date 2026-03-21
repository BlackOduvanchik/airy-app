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

    // MARK: - Delete All Data

    /// Wipe all user data from the device: transactions, pending, categories, caches, rules.
    func deleteAllData() {
        // 1. SwiftData: delete all transactions and pending
        if let ctx = context {
            do {
                try ctx.delete(model: LocalTransaction.self)
                try ctx.delete(model: LocalPendingTransaction.self)
                try ctx.save()
            } catch {
                print("[LocalDataStore] deleteAllData SwiftData error: \(error)")
            }
        }

        // 2. Categories & subcategories
        CategoryStore.save([])
        SubcategoryStore.save([])

        // 3. Merchant learning stores
        MerchantCategoryRuleStore.shared.clearAll()
        UserDefaults.standard.removeObject(forKey: "merchantAliasStore")

        // 4. Image hash cache
        ImageHashCacheStore.shared.clearAll()

        // 5. Subscription insights
        let insightKeys = ["subscriptionInsights_v1", "subscriptionInsights_lastAnalysis", "subscriptionInsights_firstSubAdded"]
        insightKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }

        // 6. Misc UserDefaults
        let miscKeys = [
            "pinnedTransactionIds",
            "airy.lastUsedCategoryIds",
            "airy.categoriesInitialized",
            "airy.subcategories_seeded",
            "exportSelectedColumns"
        ]
        miscKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    // MARK: - Transactions

    func fetchTransactions(limit: Int = 50, offset: Int = 0, month: String? = nil, year: String? = nil) -> [Transaction] {
        guard let ctx = context else { return [] }
        var descriptor = FetchDescriptor<LocalTransaction>(
            sortBy: [
                SortDescriptor(\.transactionDate, order: .reverse),
                SortDescriptor(\.createdAt, order: .reverse)
            ]
        )
        descriptor.fetchLimit = limit
        descriptor.fetchOffset = offset
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

    func fetchTransactions(from startDate: String, to endDate: String) -> [Transaction] {
        guard let ctx = context else { return [] }
        var descriptor = FetchDescriptor<LocalTransaction>(
            sortBy: [
                SortDescriptor(\.transactionDate, order: .reverse),
                SortDescriptor(\.createdAt, order: .reverse)
            ]
        )
        descriptor.predicate = #Predicate<LocalTransaction> { tx in
            tx.transactionDate >= startDate && tx.transactionDate <= endDate
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
        do { try ctx.save() } catch { print("[LocalDataStore] save failed: \(error)") }
    }

    /// Clears subcategory on transactions that match the given subcategory name + parent category.
    /// Transactions stay in their parent category — only the subcategory label is removed.
    func clearSubcategory(named subcategoryName: String, inCategory categoryId: String) {
        guard let ctx = context else { return }
        let descriptor = FetchDescriptor<LocalTransaction>(predicate: #Predicate<LocalTransaction> {
            $0.category == categoryId && $0.subcategory == subcategoryName
        })
        guard let list = try? ctx.fetch(descriptor) else { return }
        for tx in list {
            tx.subcategory = nil
        }
        do { try ctx.save() } catch { print("[LocalDataStore] save failed: \(error)") }
    }

    /// Renames subcategory on all transactions that match the old name + parent category.
    func renameSubcategory(from oldName: String, to newName: String, inCategory categoryId: String) {
        guard let ctx = context else { return }
        let descriptor = FetchDescriptor<LocalTransaction>(predicate: #Predicate<LocalTransaction> {
            $0.category == categoryId && $0.subcategory == oldName
        })
        guard let list = try? ctx.fetch(descriptor) else { return }
        for tx in list {
            tx.subcategory = newName
        }
        do { try ctx.save() } catch { print("[LocalDataStore] save failed: \(error)") }
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
        do { try ctx.save() } catch { print("[LocalDataStore] save failed: \(error)") }
    }

    /// Fetch raw LocalPendingTransaction by id.
    func fetchPendingLocalTransaction(byId id: String) -> LocalPendingTransaction? {
        guard let ctx = context else { return nil }
        var descriptor = FetchDescriptor<LocalPendingTransaction>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? ctx.fetch(descriptor).first
    }

    func confirmPending(id: String, overrides: ConfirmPendingOverrides? = nil, rememberMerchant: Bool = true) -> Bool {
        guard let ctx = context else { return false }
        var descriptor = FetchDescriptor<LocalPendingTransaction>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let pending = try? ctx.fetch(descriptor).first,
              let payload = pending.decodedPayload else { return false }
        if rememberMerchant, let o = overrides {
            if o.category != nil || o.subcategoryId != nil {
                let merchant = payload.merchant ?? "Transaction"
                let catId = o.category ?? payload.category ?? "other"
                MerchantCategoryRuleStore.shared.save(merchant: merchant, categoryId: catId, subcategoryId: o.subcategoryId)
            }
        }
        var merged = mergePayloadWithOverrides(payload, overrides)
        if let ruleCat = MerchantCategoryRuleStore.shared.categoryId(for: payload.merchant) {
            merged = PendingTransactionPayload(
                type: merged.type,
                amountOriginal: merged.amountOriginal,
                currencyOriginal: merged.currencyOriginal,
                amountBase: merged.amountBase,
                baseCurrency: merged.baseCurrency,
                merchant: merged.merchant,
                title: merged.title,
                transactionDate: merged.transactionDate,
                transactionTime: merged.transactionTime,
                category: ruleCat,
                subcategory: MerchantCategoryRuleStore.shared.subcategoryId(for: payload.merchant) ?? merged.subcategory
            )
        }

        // When user marks this pending as subscription, check for existing similar subscription
        if overrides?.isSubscription == true {
            let pendingMerchant = (merged.merchant ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let subscriptions = subscriptionsFromTransactions()
            if let similar = subscriptions.first(where: { merchantSimilarity($0.merchant, pendingMerchant) >= 0.9 }),
               let templateId = similar.templateTransactionId,
               let expectedDate = similar.nextBillingDate,
               let pendingDateStr = merged.transactionDate, !pendingDateStr.isEmpty {
                if let daysDiff = daysBetween(dateStr1: String(pendingDateStr.prefix(10)), dateStr2: expectedDate) {
                    if daysDiff <= 4 {
                        rejectPending(id: id)
                        return true
                    }
                    if daysDiff > 4, let newDate = merged.transactionDate {
                        _ = try? updateTransaction(id: templateId, body: UpdateTransactionBody(amountOriginal: nil, amountBase: nil, merchant: nil, category: nil, subcategory: nil, transactionDate: newDate, isSubscription: nil, subscriptionInterval: nil, comment: nil))
                        rejectPending(id: id)
                        return true
                    }
                }
            }
        }

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
            transactionDate: merged.transactionDate ?? AppFormatters.iso8601Basic.string(from: Date()).prefix(10).description,
            transactionTime: merged.transactionTime,
            category: merged.category ?? "other",
            subcategory: merged.subcategory,
            isSubscription: overrides?.isSubscription ?? false,
            subscriptionInterval: overrides?.subscriptionInterval,
            sourceType: "screenshot",
            sourceImageHash: pending.sourceImageHash
        )
        ctx.insert(tx)
        ctx.delete(pending)
        do { try ctx.save() } catch { print("[LocalDataStore] save failed: \(error)") }
        return true
    }

    func rejectPending(id: String) {
        guard let ctx = context else { return }
        var descriptor = FetchDescriptor<LocalPendingTransaction>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let pending = try? ctx.fetch(descriptor).first else { return }
        ctx.delete(pending)
        do { try ctx.save() } catch { print("[LocalDataStore] save failed: \(error)") }
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
            subcategory: o.subcategoryId ?? o.subcategory ?? p.subcategory,
            probableDuplicateOfId: p.probableDuplicateOfId
        )
    }

    /// Returns similarity in 0...1 (1 = identical). Uses Levenshtein; ≥0.9 used for "same merchant".
    private func merchantSimilarity(_ a: String, _ b: String) -> Double {
        let a = a.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let b = b.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if a.isEmpty && b.isEmpty { return 1 }
        let maxLen = max(a.count, b.count)
        if maxLen == 0 { return 1 }
        let distance = Self.levenshteinDistance(a, b)
        return 1 - Double(distance) / Double(maxLen)
    }

    private static func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a)
        let b = Array(b)
        let m = a.count
        let n = b.count
        if m == 0 { return n }
        if n == 0 { return m }
        var d = (0...n).map { $0 }
        for i in 1...m {
            var next = [i]
            for j in 1...n {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                next.append(min(next[j - 1] + 1, d[j] + 1, d[j - 1] + cost))
            }
            d = next
        }
        return d[n]
    }

    /// Absolute difference in days between two yyyy-MM-dd strings. Returns nil if either string is invalid.
    private func daysBetween(dateStr1: String, dateStr2: String) -> Int? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        guard let d1 = formatter.date(from: String(dateStr1.prefix(10))),
              let d2 = formatter.date(from: String(dateStr2.prefix(10))) else { return nil }
        let days = Calendar.current.dateComponents([.day], from: d1, to: d2).day ?? 0
        return abs(days)
    }

    // MARK: - Analytics (local)

    /// All expense LocalTransaction objects for the last `months` months. Single fetch for the insights engine.
    func fetchAllExpenseTransactions(months: Int = 13) -> [LocalTransaction] {
        guard let ctx = context else { return [] }
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .month, value: -months, to: Date()) ?? Date()
        let y = cal.component(.year, from: cutoff)
        let m = cal.component(.month, from: cutoff)
        let cutoffStr = String(format: "%04d-%02d-01", y, m)
        let incomeType = "income"
        var descriptor = FetchDescriptor<LocalTransaction>(
            predicate: #Predicate<LocalTransaction> { tx in
                tx.type != incomeType && tx.transactionDate >= cutoffStr
            },
            sortBy: [SortDescriptor(\.transactionDate, order: .reverse)]
        )
        descriptor.fetchLimit = 2000
        return (try? ctx.fetch(descriptor)) ?? []
    }

    /// Total income for a given month key (e.g. "2026-03").
    func fetchIncomeForMonth(monthKey: String) -> Double {
        guard let ctx = context else { return 0 }
        let prefix = monthKey         // "2026-03"
        let nextMonth: String = {
            let parts = monthKey.split(separator: "-")
            guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]) else { return "9999-99" }
            if m == 12 { return String(format: "%04d-01", y + 1) }
            return String(format: "%04d-%02d", y, m + 1)
        }()
        let incomeType = "income"
        var descriptor = FetchDescriptor<LocalTransaction>(
            predicate: #Predicate<LocalTransaction> { tx in
                tx.type == incomeType && tx.transactionDate >= prefix && tx.transactionDate < nextMonth
            }
        )
        descriptor.fetchLimit = 500
        guard let list = try? ctx.fetch(descriptor) else { return 0 }
        let base = BaseCurrencyStore.baseCurrency
        return list.reduce(0) { sum, tx in
            sum + CurrencyService.convert(amount: tx.amountOriginal, from: tx.currencyOriginal, to: base)
        }
    }

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

        // Pairs (monthKey, merchant) that have a non-subscription expense (so we don't double-count when both template and expense exist).
        let expenseMonthMerchant: Set<String> = {
            var set = Set<String>()
            for tx in all where tx.type.lowercased() != "income" && tx.isSubscription != true {
                let k = String(tx.transactionDate.prefix(7))
                let m = tx.merchant ?? ""
                set.insert("\(k)|\(m)")
            }
            return set
        }()

        for tx in all {
            let key = String(tx.transactionDate.prefix(7))
            let inBase = CurrencyService.amountInBase(amountOriginal: abs(tx.amountOriginal), currencyOriginal: tx.currencyOriginal, amountBase: tx.amountBase, baseCurrency: tx.baseCurrency)
            if key == thisMonthKey {
                if tx.type.lowercased() == "income" {
                    thisIncome += CurrencyService.amountInBase(amountOriginal: tx.amountOriginal, currencyOriginal: tx.currencyOriginal, amountBase: tx.amountBase, baseCurrency: tx.baseCurrency)
                } else {
                    let isSub = tx.isSubscription == true
                    let monthMerchant = "\(key)|\(tx.merchant ?? "")"
                    let alreadyCountedAsExpense = isSub && expenseMonthMerchant.contains(monthMerchant)
                    if !alreadyCountedAsExpense {
                        thisSpent += inBase
                        thisByCategory[tx.category, default: 0] += inBase
                    }
                }
            } else if key == lastMonthKey, tx.type.lowercased() != "income" {
                let isSub = tx.isSubscription == true
                let monthMerchant = "\(key)|\(tx.merchant ?? "")"
                let alreadyCountedAsExpense = isSub && expenseMonthMerchant.contains(monthMerchant)
                if !alreadyCountedAsExpense {
                    lastSpent += inBase
                }
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
        guard let ctx = context else { return [] }
        var descriptor = FetchDescriptor<LocalTransaction>(
            sortBy: [SortDescriptor(\.transactionDate, order: .reverse)]
        )
        descriptor.fetchLimit = 500
        guard let all = try? ctx.fetch(descriptor) else { return [] }
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
                title: tx.title,
                iconLetter: tx.subscriptionIconLetter,
                colorHex: tx.subscriptionColorHex
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

    func updateSubscriptionTemplate(templateId: String, iconLetter: String?, colorHex: String?, merchant: String? = nil) {
        guard let ctx = context else { return }
        var descriptor = FetchDescriptor<LocalTransaction>(predicate: #Predicate<LocalTransaction> { $0.id == templateId })
        descriptor.fetchLimit = 1
        guard let tx = try? ctx.fetch(descriptor).first else { return }
        tx.subscriptionIconLetter = iconLetter
        tx.subscriptionColorHex = colorHex
        if let merchant { tx.merchant = merchant }
        tx.updatedAt = Date()
        do { try ctx.save() } catch { print("[LocalDataStore] save failed: \(error)") }
    }

    func cancelSubscription(templateId: String) {
        guard let ctx = context else { return }
        var descriptor = FetchDescriptor<LocalTransaction>(predicate: #Predicate<LocalTransaction> { $0.id == templateId })
        descriptor.fetchLimit = 1
        guard let tx = try? ctx.fetch(descriptor).first else { return }
        tx.isSubscription = false
        tx.subscriptionInterval = nil
        tx.subscriptionIconLetter = nil
        tx.subscriptionColorHex = nil
        tx.updatedAt = Date()
        do { try ctx.save() } catch { print("[LocalDataStore] save failed: \(error)") }
    }

    private func addInterval(to dateStr: String, interval: String) -> String {
        let formatter = AppFormatters.inputDate
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

    /// True if a transaction with same normalized merchant, same date, same amount already exists (saved, and optionally pending).
    /// Uses confirmed alias store only; no substring/contains merchant match.
    /// Use includePending: false when counting "Found X transactions" after re-sending the same image so the user still sees items that are only in pending.
    func isExactDuplicateTransaction(merchant: String?, date: String, amount: Double, includePending: Bool = true) -> Bool {
        switch duplicateClassification(merchant: merchant, date: date, amount: amount, includePending: includePending) {
        case .exactDuplicate: return true
        case .probableDuplicate, .notDuplicate: return false
        }
    }

    /// Classification for duplicate logic: exact (exclude), probable (show in review with label), not. Uses trimmed merchant comparison; no substring/contains.
    func duplicateClassification(merchant: String?, date: String, amount: Double, includePending: Bool = true) -> DuplicateClassification {
        let dateStr = String(date.prefix(10))
        let normCandidate = normalizeMerchantForDuplicate(merchant)
        let amountTolerance = 0.01
        let similarityThreshold = 0.85

        let saved = fetchTransactions(limit: 500).map { tx in
            SavedTransactionRecord(id: tx.id, merchant: tx.merchant, date: tx.transactionDate, amount: tx.amountOriginal)
        }
        for r in saved {
            guard abs(r.amount - amount) < amountTolerance else { continue }
            guard String(r.date.prefix(10)) == dateStr else { continue }
            let normSaved = normalizeMerchantForDuplicate(r.merchant)
            if normCandidate.lowercased() == normSaved.lowercased() {
                return .exactDuplicate
            }
            if merchantSimilarityForDuplicate(normCandidate, normSaved) >= similarityThreshold {
                return .probableDuplicate(ofSavedId: r.id)
            }
        }

        if includePending {
            let pendingList = fetchPendingTransactions()
            for p in pendingList {
                guard let pl = p.decodedPayload, let amt = pl.amountOriginal, let pd = pl.transactionDate else { continue }
                guard abs(amt - amount) < amountTolerance, String(pd.prefix(10)) == dateStr else { continue }
                let normSaved = normalizeMerchantForDuplicate(pl.merchant)
                if normCandidate.lowercased() == normSaved.lowercased() {
                    return .exactDuplicate
                }
                if merchantSimilarityForDuplicate(normCandidate, normSaved) >= similarityThreshold {
                    return .probableDuplicate(ofSavedId: p.id)
                }
            }
        }
        return .notDuplicate
    }

    private func normalizeMerchantForDuplicate(_ raw: String?) -> String {
        let s = (raw ?? "").trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? "Other" : s
    }

    private func merchantSimilarityForDuplicate(_ a: String, _ b: String) -> Double {
        let aLower = a.lowercased()
        let bLower = b.lowercased()
        if aLower == bLower { return 1.0 }
        if aLower.isEmpty || bLower.isEmpty { return 0 }
        let distance = levenshteinDistanceForDuplicate(aLower, bLower)
        let maxLen = max(aLower.count, bLower.count)
        return 1.0 - (Double(distance) / Double(maxLen))
    }

    private func levenshteinDistanceForDuplicate(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        var row = (0...b.count).map { $0 }
        for (i, c1) in a.enumerated() {
            var next = [i + 1]
            for (j, c2) in b.enumerated() {
                let cost = c1 == c2 ? 0 : 1
                next.append(min(next[j] + 1, row[j + 1] + 1, row[j] + cost))
            }
            row = next
        }
        return row.last ?? 0
    }

    private func monthKey(for date: Date) -> String {
        let cal = Calendar.current
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        return String(format: "%04d-%02d", y, m)
    }

    private func formatCurrency(_ value: Double) -> String {
        AppFormatters.currency(code: "USD", fractionDigits: 0).string(from: NSNumber(value: value)) ?? "$0"
    }
}

// MARK: - Duplicate classification (used by LocalDataStore.duplicateClassification and DuplicateClassifier)

enum DuplicateClassification {
    case exactDuplicate
    case probableDuplicate(ofSavedId: String?)
    case notDuplicate
}

struct SavedTransactionRecord {
    let id: String?
    let merchant: String?
    let date: String
    let amount: Double
}

enum LocalStoreError: Error {
    case noContext
    case notFound
}
