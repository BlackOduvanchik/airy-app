//
//  TransactionListViewModel.swift
//  Airy
//
//  Local-only: fetch from SwiftData.
//

import SwiftUI

/// Filter pill options for the transaction list (matches design: All, Food, Transport, …).
enum TransactionCategoryFilter: String, CaseIterable {
    case all = "All"
    case food = "Food"
    case transport = "Transport"
    case shopping = "Shopping"
    case subscriptions = "Subscriptions"
    case health = "Health"
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
    var selectedFilter: TransactionCategoryFilter = .all
    var refreshTrigger = 0

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
        switch selectedFilter {
        case .all: break
        case .food:
            list = list.filter { $0.category.lowercased().contains("food") || $0.category.lowercased().contains("dining") }
        case .transport:
            list = list.filter { $0.category.lowercased().contains("transport") || $0.category.lowercased().contains("transit") }
        case .shopping:
            list = list.filter { $0.category.lowercased().contains("shopping") }
        case .subscriptions:
            list = list.filter { $0.isSubscription == true }
        case .health:
            list = list.filter { $0.category.lowercased().contains("health") }
        }
        return list.sorted { (a, b) in
            (a.transactionDate, a.transactionTime ?? "") > (b.transactionDate, b.transactionTime ?? "")
        }
    }

    /// Pinned transactions only (for Pinned Items section).
    var pinnedTransactions: [Transaction] {
        let pinned = LocalDataStore.shared.pinnedTransactionIds()
        return filteredTransactions.filter { pinned.contains($0.id) }
            .sorted { (a, b) in (a.transactionDate, a.transactionTime ?? "") > (b.transactionDate, b.transactionTime ?? "") }
    }

    /// Groups filtered transactions by month, excluding pinned; each group has total (expenses only).
    var groupedByMonth: [TransactionMonthGroup] {
        let pinned = LocalDataStore.shared.pinnedTransactionIds()
        let nonPinned = filteredTransactions.filter { !pinned.contains($0.id) }
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
        LocalDataStore.shared.pinnedTransactionIds().contains(tx.id)
    }

    /// Heuristic: same month has another tx with same merchant and subscription → possible duplicate.
    func isPossibleDuplicate(_ tx: Transaction, inMonthTransactions list: [Transaction]) -> Bool {
        guard tx.isSubscription == true else { return false }
        let sameMerchant = list.filter { $0.merchant == tx.merchant && $0.id != tx.id }
        return !sameMerchant.isEmpty
    }

    func load(append: Bool = false) async {
        if !append { isLoading = true }
        defer { if !append { Task { @MainActor in isLoading = false } } }
        await MainActor.run {
            transactions = LocalDataStore.shared.fetchTransactions(limit: 100)
            nextCursor = nil
            hasMore = false
        }
    }
}
