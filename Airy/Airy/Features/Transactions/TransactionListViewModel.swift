//
//  TransactionListViewModel.swift
//  Airy
//
//  Local-only: fetch from SwiftData.
//

import SwiftUI
import SwiftData

/// Dynamic category filter item for the transaction list.
struct CategoryFilterItem: Identifiable, Equatable {
    let id: String
    let label: String
}

/// One month group: label (e.g. "June 2025"), total spent, and transactions.
struct TransactionMonthGroup: Identifiable {
    let id: String
    let monthLabel: String
    let total: Double
    let transactions: [Transaction]
}

@MainActor
@Observable
final class TransactionListViewModel {
    static let shared = TransactionListViewModel()

    var transactions: [Transaction] = []
    var nextCursor: String?
    var hasMore = false
    var isLoading = false
    private(set) var isLoadingMore = false
    var errorMessage: String?

    var searchText = "" { didSet { rebuildDerivedData() } }
    var selectedFilterId: String? = nil { didSet { rebuildDerivedData() } }
    var categoryFilters: [CategoryFilterItem] = [CategoryFilterItem(id: "all", label: "All")]
    var refreshTrigger = 0
    var pinnedIds: Set<String> = [] { didSet { rebuildDerivedData() } }
    private let pageSize = 50
    private var isPreloaded = false

    // Cached derived data — rebuilt only when inputs change
    private(set) var filteredTransactions: [Transaction] = []
    private(set) var pinnedTransactions: [Transaction] = []
    private(set) var groupedByMonth: [TransactionMonthGroup] = []

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private let monthLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    // MARK: - Derived data rebuild

    private func rebuildDerivedData() {
        // 1. Filter
        var list = transactions
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
            list = list.filter {
                ($0.merchant ?? "").lowercased().contains(q) ||
                ($0.title ?? "").lowercased().contains(q) ||
                $0.category.lowercased().contains(q)
            }
        }
        if let filterId = selectedFilterId {
            if filterId == "subscriptions" {
                list = list.filter { $0.isSubscription == true }
            } else {
                list = list.filter { $0.category == filterId }
            }
        }
        list.sort { ($0.transactionDate, $0.transactionTime ?? "") > ($1.transactionDate, $1.transactionTime ?? "") }
        filteredTransactions = list

        // 2. Pinned
        pinnedTransactions = list.filter { pinnedIds.contains($0.id) }

        // 3. Grouped (non-pinned only)
        let nonPinned = list.filter { !pinnedIds.contains($0.id) }
        var groupDict: [String: (monthLabel: String, total: Double, list: [Transaction])] = [:]
        for tx in nonPinned {
            let dateStr = String(tx.transactionDate.prefix(10))
            guard let date = dateFormatter.date(from: dateStr) else {
                var other = groupDict["other"] ?? ("Other", 0, [])
                other.list.append(tx)
                groupDict["other"] = other
                continue
            }
            let key = String(dateFormatter.string(from: date).prefix(7))
            let monthLabel = monthLabelFormatter.string(from: date)
            var existing = groupDict[key] ?? (monthLabel, 0, [Transaction]())
            existing.list.append(tx)
            if tx.type.lowercased() != "income" {
                existing.total += CurrencyService.amountInBase(
                    amountOriginal: abs(tx.amountOriginal),
                    currencyOriginal: tx.currencyOriginal,
                    amountBase: tx.amountBase,
                    baseCurrency: tx.baseCurrency
                )
            }
            groupDict[key] = existing
        }
        groupedByMonth = groupDict.sorted { $0.key > $1.key }.map { key, value in
            TransactionMonthGroup(id: key, monthLabel: value.monthLabel, total: value.total, transactions: value.list)
        }
    }

    // MARK: - Mutations

    /// Remove a deleted transaction from the in-memory list without reloading from DB.
    /// Prevents the list from resetting to page 1 and losing scroll position.
    func removeLocally(id: String) {
        transactions.removeAll { $0.id == id }
        pinnedIds.remove(id)
        rebuildDerivedData()
    }

    /// Update an edited transaction in-place without resetting pagination.
    func updateLocally(id: String) {
        guard let updated = LocalDataStore.shared.fetchTransaction(id: id) else { return }
        if let idx = transactions.firstIndex(where: { $0.id == id }) {
            transactions[idx] = updated
            rebuildDerivedData()
        }
    }

    // MARK: - Queries

    func isPinned(_ tx: Transaction) -> Bool {
        pinnedIds.contains(tx.id)
    }

    /// Heuristic: same month has another tx with same merchant and subscription → possible duplicate.
    func isPossibleDuplicate(_ tx: Transaction, inMonthTransactions list: [Transaction]) -> Bool {
        guard tx.isSubscription == true else { return false }
        let sameMerchant = list.filter { $0.merchant == tx.merchant && $0.id != tx.id }
        return !sameMerchant.isEmpty
    }

    /// Preload the first page in the background so data is ready when the user navigates here.
    func preload() async {
        guard !isPreloaded else { return }
        isPreloaded = true
        pinnedIds = LocalDataStore.shared.pinnedTransactionIds()
        let page = await fetchPage(limit: pageSize, offset: 0)
        transactions = page
        hasMore = page.count == pageSize
        buildCategoryFilters()
        rebuildDerivedData()
    }

    /// Incrementally load remaining pages (used when a filter is active to avoid spinner stuck).
    func loadRemaining() async {
        while hasMore {
            let offset = transactions.count
            let page = await fetchPage(limit: pageSize, offset: offset)
            transactions.append(contentsOf: page)
            hasMore = page.count == pageSize
        }
        rebuildDerivedData()
    }

    func load(append: Bool = false) async {
        let loadStart = CFAbsoluteTimeGetCurrent()
        if append { guard !isLoadingMore else { return }; isLoadingMore = true }
        if !append {
            // If preloaded data exists, use it directly — no fetch needed.
            if isPreloaded && !transactions.isEmpty {
                isLoading = false
                let ms = (CFAbsoluteTimeGetCurrent() - loadStart) * 1000
                print("[Perf] TransactionListVM.load() took \(String(format: "%.1f", ms))ms (preloaded, skipped)")
                return
            }
            isLoading = true
        }

        pinnedIds = LocalDataStore.shared.pinnedTransactionIds()

        let offset = append ? transactions.count : 0
        let page = await fetchPage(limit: pageSize, offset: offset)

        if append {
            transactions.append(contentsOf: page)
            hasMore = page.count == pageSize
        } else {
            transactions = page
            hasMore = page.count == pageSize
            buildCategoryFilters()
        }
        rebuildDerivedData()
        if append { isLoadingMore = false }
        if !append { isLoading = false }
        let ms = (CFAbsoluteTimeGetCurrent() - loadStart) * 1000
        print("[Perf] TransactionListVM.load(append: \(append)) took \(String(format: "%.1f", ms))ms (\(page.count) rows)")
    }

    /// Fetch a page of transactions on a background thread to keep the UI responsive.
    private func fetchPage(limit: Int, offset: Int) async -> [Transaction] {
        guard let container = LocalDataStore.shared.modelContainer else { return [] }
        return await Task.detached {
            let ctx = ModelContext(container)
            var descriptor = FetchDescriptor<LocalTransaction>(
                sortBy: [
                    SortDescriptor(\.transactionDate, order: .reverse),
                    SortDescriptor(\.createdAt, order: .reverse)
                ]
            )
            descriptor.fetchLimit = limit
            descriptor.fetchOffset = offset
            descriptor.predicate = #Predicate<LocalTransaction> { tx in
                tx.isSubscription != true
            }
            return (try? ctx.fetch(descriptor))?.map { $0.toTransaction() } ?? []
        }.value
    }

    private func buildCategoryFilters() {
        let allCategories = CategoryStore.load()

        let thisMonthKey: String = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM"
            return f.string(from: Date())
        }()
        var byCategory: [String: Double] = [:]
        for tx in transactions where tx.type.lowercased() != "income" {
            let key = String(tx.transactionDate.prefix(7))
            if key == thisMonthKey {
                byCategory[tx.category, default: 0] += abs(tx.amountOriginal)
            }
        }

        var sorted: [Category]
        if byCategory.isEmpty {
            sorted = allCategories.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } else {
            sorted = allCategories.sorted { a, b in
                let aSpend = byCategory[a.id] ?? 0
                let bSpend = byCategory[b.id] ?? 0
                if aSpend != bSpend { return aSpend > bSpend }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        }

        var filters: [CategoryFilterItem] = [CategoryFilterItem(id: "all", label: "All")]
        for cat in sorted {
            filters.append(CategoryFilterItem(id: cat.id, label: cat.name))
        }
        filters.append(CategoryFilterItem(id: "subscriptions", label: "Subscriptions"))
        categoryFilters = filters
    }
}
