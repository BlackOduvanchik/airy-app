//
//  SubscriptionsViewModel.swift
//  Airy
//
//  Local-only: derive from SwiftData transactions.
//

import SwiftUI

@Observable
final class SubscriptionsViewModel {
    var subscriptions: [Subscription] = []
    var isLoading = true
    var showPaywall = false
    var errorMessage: String?

    var nextUpSubscriptions: [Subscription] {
        subscriptions
            .filter { $0.nextBillingDate != nil && !($0.nextBillingDate?.isEmpty ?? true) }
            .sorted { (a, b) in
                guard let da = a.nextBillingDate, let db = b.nextBillingDate else { return false }
                return da.compare(db) == .orderedAscending
            }
    }

    var totalMonthly: Double {
        subscriptions.reduce(0) { sum, sub in
            let monthly: Double
            if sub.interval.lowercased().hasPrefix("year") || sub.interval.lowercased().hasPrefix("annual") {
                monthly = sub.amount / 12
            } else {
                monthly = sub.amount
            }
            return sum + monthly
        }
    }

    func load() async {
        isLoading = true
        defer { Task { @MainActor in isLoading = false } }
        await MainActor.run {
            subscriptions = LocalDataStore.shared.subscriptionsFromTransactions()
        }
    }
}
