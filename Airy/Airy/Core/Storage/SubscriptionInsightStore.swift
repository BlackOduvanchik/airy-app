//
//  SubscriptionInsightStore.swift
//  Airy
//
//  Stores GPT-generated subscription insights (pricing alternatives, saving tips).
//  UserDefaults-backed, thread-safe. Max 100 entries.
//

import Foundation

struct PricingAlternative: Codable {
    let planName: String
    let price: Double
    let interval: String
    let estimatedMonthlyCost: Double
}

struct SubscriptionInsight: Codable, Identifiable {
    let id: String
    let merchant: String
    let userPrice: Double
    let userInterval: String
    let alternatives: [PricingAlternative]
    let tip: String
    let monthlySavingsPotential: Double
    let fetchedAt: Date
}

final class SubscriptionInsightStore {
    static let shared = SubscriptionInsightStore()

    private let insightsKey = "subscriptionInsights_v1"
    private let lastAnalysisKey = "subscriptionInsights_lastAnalysis"
    private let firstSubAddedKey = "subscriptionInsights_firstSubAdded"
    private let maxEntries = 100
    private let queue = DispatchQueue(label: "ai.airy.subscriptionInsightStore", attributes: .concurrent)
    private var cache: [SubscriptionInsight]?

    private init() {}

    func loadAll() -> [SubscriptionInsight] {
        queue.sync {
            if let c = cache { return c }
            guard let data = UserDefaults.standard.data(forKey: insightsKey),
                  let decoded = try? JSONDecoder().decode([SubscriptionInsight].self, from: data) else { return [] }
            cache = decoded
            return decoded
        }
    }

    func save(_ insights: [SubscriptionInsight]) {
        queue.async(flags: .barrier) { [self] in
            var current = loadAllUnsafe()
            for insight in insights {
                current.removeAll { $0.id == insight.id }
                current.append(insight)
            }
            if current.count > maxEntries {
                current.sort { $0.fetchedAt > $1.fetchedAt }
                current = Array(current.prefix(maxEntries))
            }
            cache = current
            if let data = try? JSONEncoder().encode(current) {
                UserDefaults.standard.set(data, forKey: insightsKey)
            }
        }
    }

    func forMerchant(_ name: String) -> SubscriptionInsight? {
        let key = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return loadAll().first { $0.id == key }
    }

    // MARK: - Analysis timing

    func lastAnalysisDate() -> Date? {
        UserDefaults.standard.object(forKey: lastAnalysisKey) as? Date
    }

    func setLastAnalysisDate(_ date: Date) {
        UserDefaults.standard.set(date, forKey: lastAnalysisKey)
    }

    func resetCooldown() {
        UserDefaults.standard.removeObject(forKey: lastAnalysisKey)
    }

    func firstSubscriptionAddedAt() -> Date? {
        UserDefaults.standard.object(forKey: firstSubAddedKey) as? Date
    }

    func markFirstSubscriptionAdded() {
        guard firstSubscriptionAddedAt() == nil else { return }
        UserDefaults.standard.set(Date(), forKey: firstSubAddedKey)
    }

    func shouldAnalyze(subscriptionCount: Int) -> Bool {
        guard subscriptionCount > 0 else { return false }
        if let last = lastAnalysisDate() {
            let days = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
            return days >= 7
        }
        guard let firstAdded = firstSubscriptionAddedAt() else { return false }
        let hours = Calendar.current.dateComponents([.hour], from: firstAdded, to: Date()).hour ?? 0
        return hours >= 1
    }

    // MARK: - Private

    private func loadAllUnsafe() -> [SubscriptionInsight] {
        if let c = cache { return c }
        guard let data = UserDefaults.standard.data(forKey: insightsKey),
              let decoded = try? JSONDecoder().decode([SubscriptionInsight].self, from: data) else { return [] }
        cache = decoded
        return decoded
    }
}
