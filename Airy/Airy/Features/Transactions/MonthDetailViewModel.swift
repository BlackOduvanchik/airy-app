//
//  MonthDetailViewModel.swift
//  Airy
//
//  Loads transactions for a selected month and builds calendar + list for MonthDetailView.
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
        do {
            let res = try await APIClient.shared.getTransactions(
                limit: 200,
                cursor: nil,
                month: String(format: "%02d", ym.month),
                year: String(ym.year)
            )
            await MainActor.run {
                transactions = res.transactions.sorted { a, b in
                    (a.transactionDate, a.transactionTime ?? "") < (b.transactionDate, b.transactionTime ?? "")
                }
                totalSpent = transactions
                    .filter { $0.type.lowercased() != "income" }
                    .reduce(0) { $0 + $1.amountOriginal }
            }
        } catch {
            await MainActor.run {
                transactions = []
                totalSpent = 0
                errorMessage = error.localizedDescription
            }
        }
    }
}
