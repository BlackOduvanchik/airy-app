//
//  SubscriptionLabViewModel.swift
//  Airy
//
//  Merges subscriptions with GPT-generated insights for the Subscription Lab page.
//

import SwiftUI

enum LabBadgeType {
    case unused
    case tierDown
    case savePercent(Int)
}

struct LabSubscriptionItem: Identifiable {
    let id: String
    let subscription: Subscription
    let insight: SubscriptionInsight?

    var hasSavings: Bool { (insight?.monthlySavingsPotential ?? 0) > 0 }
    var monthlySavings: Double { insight?.monthlySavingsPotential ?? 0 }
    var yearlySavings: Double { monthlySavings * 12 }

    var badgeType: LabBadgeType? {
        guard let insight, hasSavings else { return nil }
        let tip = insight.tip.lowercased()
        if tip.contains("unused") || tip.contains("not using") || tip.contains("cancel") {
            return .unused
        }
        if tip.contains("tier") || tip.contains("downgrade") || tip.contains("lower plan") {
            return .tierDown
        }
        let price = subscription.amount
        guard price > 0 else { return nil }
        let pct = Int(round(monthlySavings / price * 100))
        return pct > 0 ? .savePercent(pct) : nil
    }

    var secondaryText: String {
        if let insight, hasSavings {
            return insight.tip
        }
        return "Optimal usage detected"
    }
}

@Observable
final class SubscriptionLabViewModel {
    var items: [LabSubscriptionItem] = []
    var optimizableItems: [LabSubscriptionItem] = []
    var optimalItems: [LabSubscriptionItem] = []

    var totalMonthlySavings: Double = 0
    var totalYearlySavings: Double = 0
    var optimizableCount: Int = 0
    var aiSummaryText: String = ""
    var bottomInsights: [String] = []

    init(subscriptions: [Subscription], insights: [SubscriptionInsight]) {
        buildItems(subscriptions: subscriptions, insights: insights)
    }

    private func buildItems(subscriptions: [Subscription], insights: [SubscriptionInsight]) {
        items = subscriptions.map { sub in
            let insight = SubscriptionInsightStore.shared.forMerchant(sub.merchant)
            return LabSubscriptionItem(id: sub.id, subscription: sub, insight: insight)
        }

        optimizableItems = items
            .filter { $0.hasSavings }
            .sorted { $0.monthlySavings > $1.monthlySavings }

        optimalItems = items.filter { !$0.hasSavings }

        totalMonthlySavings = optimizableItems.reduce(0) { $0 + $1.monthlySavings }
        totalYearlySavings = totalMonthlySavings * 12
        optimizableCount = optimizableItems.count

        aiSummaryText = generateSummary(insights: insights)
        bottomInsights = generateBottomInsights(insights: insights)
    }

    private func generateSummary(insights: [SubscriptionInsight]) -> String {
        let withSavings = insights.filter { $0.monthlySavingsPotential > 0 }
        let totalSubs = items.count

        guard !withSavings.isEmpty else {
            if totalSubs > 0 {
                return "All \(totalSubs) subscription\(totalSubs == 1 ? " is" : "s are") well-optimized. No changes needed."
            }
            return "We're analyzing your subscriptions. Check back soon."
        }

        let fmt = currencyFormatter()
        let yearlyStr = fmt.string(from: NSNumber(value: totalYearlySavings)) ?? "$0"

        let hasUnused = withSavings.contains { $0.tip.lowercased().contains("unused") || $0.tip.lowercased().contains("cancel") }
        let hasAnnual = withSavings.contains { $0.tip.lowercased().contains("annual") || $0.tip.lowercased().contains("yearly") }

        var parts: [String] = []
        if hasAnnual && hasUnused {
            parts.append("Switch to annual billing and cancel unused services")
        } else if hasAnnual {
            parts.append("Switch \(withSavings.count) plan\(withSavings.count == 1 ? "" : "s") to annual billing")
        } else if hasUnused {
            parts.append("Cancel unused subscriptions")
        } else {
            parts.append("Optimize \(withSavings.count) subscription\(withSavings.count == 1 ? "" : "s")")
        }
        parts.append("to save ~\(yearlyStr)/year.")

        return parts.joined(separator: " ")
    }

    private func generateBottomInsights(insights: [SubscriptionInsight]) -> [String] {
        insights
            .filter { $0.monthlySavingsPotential > 0 }
            .sorted { $0.monthlySavingsPotential > $1.monthlySavingsPotential }
            .prefix(3)
            .map { $0.tip }
    }

    private func currencyFormatter() -> NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = BaseCurrencyStore.baseCurrency
        f.maximumFractionDigits = 0
        f.minimumFractionDigits = 0
        return f
    }
}
