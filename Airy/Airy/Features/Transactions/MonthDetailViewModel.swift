//
//  MonthDetailViewModel.swift
//  Airy
//
//  Local-only: fetch from SwiftData.
//

import SwiftUI

@Observable
final class MonthDetailViewModel {
    var monthKey: String
    var monthLabel: String
    var transactions: [Transaction] = []
    var totalSpent: Double = 0
    var isLoading = true
    var errorMessage: String?

    /// Day numbers (1...31) that have at least one transaction.
    var daysWithTransactions: Set<Int> {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        var set: Set<Int> = []
        for tx in transactions {
            let dateStr = String(tx.transactionDate.prefix(10))
            guard let date = formatter.date(from: dateStr) else { continue }
            let day = Calendar.current.component(.day, from: date)
            set.insert(day)
        }
        return set
    }

    /// Year and month components from monthKey "2025-06".
    private var yearMonth: (year: Int, month: Int)? {
        let parts = monthKey.split(separator: "-")
        guard parts.count >= 2,
              let y = Int(parts[0]),
              let m = Int(parts[1]) else { return nil }
        return (y, m)
    }

    init(monthKey: String, monthLabel: String) {
        self.monthKey = monthKey
        self.monthLabel = monthLabel
    }

    func load() async {
        guard let ym = yearMonth else {
            await MainActor.run { isLoading = false }
            return
        }
        isLoading = true
        defer { Task { @MainActor in isLoading = false } }
        await MainActor.run {
            let monthStr = String(format: "%02d", ym.month)
            let yearStr = String(ym.year)
            transactions = LocalDataStore.shared.fetchTransactions(limit: 200, month: monthStr, year: yearStr)
                .sorted { a, b in
                    (a.transactionDate, a.transactionTime ?? "") < (b.transactionDate, b.transactionTime ?? "")
                }
            totalSpent = transactions
                .filter { $0.type.lowercased() != "income" }
                .reduce(0) { acc, tx in
                    acc + CurrencyService.amountInBase(amountOriginal: abs(tx.amountOriginal), currencyOriginal: tx.currencyOriginal, amountBase: tx.amountBase, baseCurrency: tx.baseCurrency)
                }
        }
    }
}
