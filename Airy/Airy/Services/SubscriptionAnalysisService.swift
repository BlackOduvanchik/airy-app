//
//  SubscriptionAnalysisService.swift
//  Airy
//
//  Triggers GPT subscription analysis on app foreground. Max once per 7 days.
//  First analysis: 1 hour after the first subscription is added.
//

import Foundation

@MainActor @Observable
final class SubscriptionAnalysisService {
    static let shared = SubscriptionAnalysisService()

    var isAnalyzing = false

    private let gptService = GPTRulesService()
    private let store = SubscriptionInsightStore.shared
    private var analyzeTask: Task<Void, Never>?

    private init() {}

    /// Called from AiryApp on `didBecomeActive`. Checks cooldown and runs analysis if needed.
    func checkAndAnalyzeIfNeeded() {
        let subscriptions = LocalDataStore.shared.subscriptionsFromTransactions()

        // Mark first subscription timestamp
        if !subscriptions.isEmpty {
            store.markFirstSubscriptionAdded()
        }

        guard store.shouldAnalyze(subscriptionCount: subscriptions.count) else { return }

        // Don't overlap with photo analysis
        guard !ImportViewModel.shared.isAnalyzing else { return }

        // Don't double-start
        guard !isAnalyzing else { return }

        analyzeTask = Task {
            await runAnalysis(subscriptions: subscriptions)
        }
    }

    private func runAnalysis(subscriptions: [Subscription]) async {
        isAnalyzing = true
        defer { isAnalyzing = false }

        // Filter: skip subs that already have a fresh insight (< 7 days old)
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 3600)
        let existingInsights = store.loadAll()
        let freshMerchants = Set(existingInsights
            .filter { $0.fetchedAt > sevenDaysAgo }
            .map { $0.id })

        let needsAnalysis = subscriptions
            .filter { !freshMerchants.contains($0.merchant.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)) }
            .sorted { $0.amount > $1.amount }  // prioritize expensive subs

        // Cap at 50 per cycle to avoid excessive API calls
        let capped = Array(needsAnalysis.prefix(50))

        let input = capped.map { sub -> (merchant: String, amount: Double, interval: String, currency: String) in
            (merchant: sub.merchant, amount: sub.amount, interval: sub.interval, currency: sub.currency)
        }

        print("[SubsInsight] Total: \(subscriptions.count), fresh: \(freshMerchants.count), to analyze: \(input.count)")

        guard !input.isEmpty else {
            print("[SubsInsight] All subscriptions already have fresh insights, skipping")
            store.setLastAnalysisDate(Date())
            return
        }

        let batchSize = 50
        let batches = stride(from: 0, to: input.count, by: batchSize).map {
            Array(input[$0..<min($0 + batchSize, input.count)])
        }

        var allInsights: [SubscriptionInsight] = []
        let now = Date()

        for (i, batch) in batches.enumerated() {
            print("[SubsInsight] Batch \(i + 1)/\(batches.count): \(batch.count) subs")
            do {
                let responses = try await gptService.analyzeSubscriptions(subscriptions: batch)

                let insights = responses.map { resp -> SubscriptionInsight in
                    let alts = resp.alternatives.map { alt -> PricingAlternative in
                        let monthly: Double
                        if alt.interval.lowercased().hasPrefix("year") || alt.interval.lowercased().hasPrefix("annual") {
                            monthly = alt.price / 12
                        } else if alt.interval.lowercased().hasPrefix("week") {
                            monthly = alt.price * (52.0 / 12.0)
                        } else {
                            monthly = alt.price
                        }
                        return PricingAlternative(
                            planName: alt.planName,
                            price: alt.price,
                            interval: alt.interval,
                            estimatedMonthlyCost: monthly
                        )
                    }
                    return SubscriptionInsight(
                        id: resp.merchant.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
                        merchant: resp.merchant,
                        userPrice: input.first { $0.merchant.lowercased() == resp.merchant.lowercased() }?.amount ?? 0,
                        userInterval: input.first { $0.merchant.lowercased() == resp.merchant.lowercased() }?.interval ?? "monthly",
                        alternatives: alts,
                        tip: resp.tip,
                        monthlySavingsPotential: resp.monthlySavingsPotential,
                        fetchedAt: now
                    )
                }
                allInsights.append(contentsOf: insights)
                print("[SubsInsight] Batch \(i + 1) OK: \(insights.count) insight(s)")
            } catch {
                print("[SubsInsight] Batch \(i + 1) failed: \(error.localizedDescription)")
                // Continue with remaining batches
            }
        }

        if !allInsights.isEmpty {
            store.save(allInsights)
            print("[SubsInsight] Saved \(allInsights.count) insight(s). Potential monthly savings: $\(allInsights.reduce(0) { $0 + $1.monthlySavingsPotential })")
            for ins in allInsights {
                print("[SubsInsight]  · \(ins.merchant): savings $\(String(format: "%.2f", ins.monthlySavingsPotential))/mo | tip: \(ins.tip)")
            }
        } else {
            print("[SubsInsight] No insights returned from any batch")
        }
        store.setLastAnalysisDate(now)
    }
}
