//
//  TransactionListViewModel.swift
//  Airy
//
//  Local-only: fetch from SwiftData.
//

import SwiftUI

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
    var transactions: [Transaction] = []
    var nextCursor: String?
    var hasMore = false
    var isLoading = false
    var errorMessage: String?

    var searchText = ""
    var selectedFilterId: String? = nil // nil = "All"
    var categoryFilters: [CategoryFilterItem] = [CategoryFilterItem(id: "all", label: "All")]
    var refreshTrigger = 0
    var pinnedIds: Set<String> = []
    private let pageSize = 50

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

    /// Filtered list by search and category.
    var filteredTransactions: [Transaction] {
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
        return list.sorted { (a, b) in
            (a.transactionDate, a.transactionTime ?? "") > (b.transactionDate, b.transactionTime ?? "")
        }
    }

    /// Pinned transactions only (for Pinned Items section).
    var pinnedTransactions: [Transaction] {
        return filteredTransactions.filter { pinnedIds.contains($0.id) }
            .sorted { (a, b) in (a.transactionDate, a.transactionTime ?? "") > (b.transactionDate, b.transactionTime ?? "") }
    }

    /// Groups filtered transactions by month, excluding pinned; each group has total (expenses only).
    var groupedByMonth: [TransactionMonthGroup] {
        let nonPinned = filteredTransactions.filter { !pinnedIds.contains($0.id) }
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
                existing.total += CurrencyService.amountInBase(amountOriginal: abs(tx.amountOriginal), currencyOriginal: tx.currencyOriginal, amountBase: tx.amountBase, baseCurrency: tx.baseCurrency)
            }
            groupDict[key] = existing
        }
        return groupDict.sorted { $0.key > $1.key }.map { key, value in
            TransactionMonthGroup(id: key, monthLabel: value.monthLabel, total: value.total, transactions: value.list)
        }
    }

    func isPinned(_ tx: Transaction) -> Bool {
        pinnedIds.contains(tx.id)
    }

    /// Heuristic: same month has another tx with same merchant and subscription → possible duplicate.
    func isPossibleDuplicate(_ tx: Transaction, inMonthTransactions list: [Transaction]) -> Bool {
        guard tx.isSubscription == true else { return false }
        let sameMerchant = list.filter { $0.merchant == tx.merchant && $0.id != tx.id }
        return !sameMerchant.isEmpty
    }

    /// Incrementally load remaining pages (used when a filter is active to avoid spinner stuck).
    func loadRemaining() async {
        while hasMore {
            await MainActor.run {
                let offset = transactions.count
                let page = LocalDataStore.shared.fetchTransactions(limit: pageSize, offset: offset)
                transactions.append(contentsOf: page)
                hasMore = page.count == pageSize
            }
        }
    }

    func load(append: Bool = false) async {
        if !append { isLoading = true }
        defer { if !append { Task { @MainActor in isLoading = false } } }
        await MainActor.run {
            pinnedIds = LocalDataStore.shared.pinnedTransactionIds()
            if append {
                let offset = transactions.count
                let page = LocalDataStore.shared.fetchTransactions(limit: pageSize, offset: offset)
                transactions.append(contentsOf: page)
                hasMore = page.count == pageSize
            } else {
                let page = LocalDataStore.shared.fetchTransactions(limit: pageSize)
                transactions = page
                hasMore = page.count == pageSize
                buildCategoryFilters()
            }
        }
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
