//
//  SubscriptionsViewModel.swift
//  Airy
//

import SwiftUI

@Observable
final class SubscriptionsViewModel {
    var subscriptions: [Subscription] = []
    var isLoading = true
    var showPaywall = false
    var errorMessage: String?

    /// Subscriptions sorted by next billing date (soonest first) for "Next Up" strip.
    var nextUpSubscriptions: [Subscription] {
        subscriptions
            .filter { $0.nextBillingDate != nil && !($0.nextBillingDate?.isEmpty ?? true) }
            .sorted { (a, b) in
                guard let da = a.nextBillingDate, let db = b.nextBillingDate else { return false }
                return da.compare(db) == .orderedAscending
            }
    }

    /// Total monthly equivalent (monthly amount + annual/12).
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
        do {
            let res = try await APIClient.shared.getSubscriptions()
            await MainActor.run { subscriptions = res.subscriptions }
        } catch APIError.paymentRequired {
            let entitlements = try? await APIClient.shared.getEntitlements()
            await MainActor.run {
                if entitlements?.unlimitedAiAnalysis != true { showPaywall = true }
            }
        } catch {
            await MainActor.run { subscriptions = []; errorMessage = error.localizedDescription }
        }
    }
}
