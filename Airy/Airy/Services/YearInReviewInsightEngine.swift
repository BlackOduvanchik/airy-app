//
//  YearInReviewInsightEngine.swift
//  Airy
//
//  Pure computation: generates scored, deduplicated insight cards grouped by dynamic sections.
//  No state, no MainActor — receives Context, returns [YRSectionGroup].
//

import SwiftUI

// MARK: - Public interface

@MainActor
struct YRInsightEngine {

    struct Context {
        let monthlyData: [YRMonthData]
        let transactions: [Transaction]
        let selectedPeriod: String           // year string or "all"
        let selectedMonthIndex: Int?
        let baseCurrency: String
        let previousPeriodTransactions: [Transaction]?
    }

    static func generate(from ctx: Context) -> [YRSectionGroup] {
        let sections = activeSections(for: ctx)
        var groups: [YRSectionGroup] = []

        for section in sections {
            let candidates = allCandidates(for: section, ctx: ctx)
            let selected = selectTop(candidates, range: section.cardRange, alwaysOn: section.alwaysOn)
            if !selected.isEmpty {
                let cards = selected.map { $0.toCard() }
                groups.append(YRSectionGroup(section: section, cards: cards))
            }
        }
        return groups
    }
}

// MARK: - Internal candidate type

@MainActor
private struct Candidate {
    let section: YRSection
    let icon: String
    let title: String
    let body: String
    let accentColor: Color
    let tags: Set<String>
    let significance: Double    // 0-5
    let novelty: Double         // 0-5
    let confidence: Double      // 0-5
    let clarity: Double         // 0-5
    var duplicationPenalty: Double = 0

    var totalScore: Double {
        significance + novelty + confidence + clarity - duplicationPenalty
    }

    func toCard() -> YRInsightCard {
        YRInsightCard(icon: icon, title: title, body: body, accentColor: accentColor, section: section)
    }
}

// MARK: - Section activation

private extension YRInsightEngine {

    static func activeSections(for ctx: Context) -> [YRSection] {
        let md = ctx.monthlyData
        var sections: [YRSection] = [.yearSummary, .categoryIntelligence, .smartInsights]

        if md.count >= 3 { sections.append(.spendingPatterns) }

        // Conditional: score each, pick top 1-2
        var conditional: [(YRSection, Double)] = []

        if ctx.selectedMonthIndex != nil {
            conditional.append((.selectedMonth, 10))
        }

        let totalInc = md.reduce(0) { $0 + $1.income }
        let totalExp = md.reduce(0) { $0 + $1.expense }

        if totalInc > totalExp * 0.1 && totalInc > 0 {
            conditional.append((.incomePatterns, 3 + min(5, totalInc / max(1, totalExp) * 5)))
        }

        let totalSubExp = md.reduce(0) { $0 + $1.subscriptionExpense }
        if totalExp > 0 && totalSubExp / totalExp >= 0.08 {
            conditional.append((.subscriptionAnalysis, 3 + totalSubExp / totalExp * 10))
        }

        // Turning points: look for sharp net changes
        if md.count >= 4 {
            let nets = md.map(\.net)
            var maxSwing = 0.0
            for i in 1..<nets.count {
                maxSwing = max(maxSwing, abs(nets[i] - nets[i-1]))
            }
            let avgNet = totalExp > 0 ? totalExp / Double(md.count) : 1
            if maxSwing > avgNet * 0.5 {
                conditional.append((.turningPoints, 3 + min(5, maxSwing / avgNet * 3)))
            }
        }

        if ctx.previousPeriodTransactions != nil {
            conditional.append((.comparisonVsPrevious, 5))
        }

        if ctx.selectedPeriod == "all" && md.count >= 12 {
            conditional.append((.allTimePerspective, 6))
        }

        conditional.sort { $0.1 > $1.1 }
        let picked = Array(conditional.prefix(2)).map(\.0)
        sections.append(contentsOf: picked)

        return sections.sorted { $0.rawValue < $1.rawValue }
    }
}

// MARK: - Candidate dispatch

private extension YRInsightEngine {

    static func allCandidates(for section: YRSection, ctx: Context) -> [Candidate] {
        switch section {
        case .yearSummary:          return yearSummaryCandidates(ctx)
        case .spendingPatterns:     return spendingPatternsCandidates(ctx)
        case .categoryIntelligence: return categoryIntelligenceCandidates(ctx)
        case .selectedMonth:        return selectedMonthCandidates(ctx)
        case .smartInsights:        return smartInsightsCandidates(ctx)
        case .incomePatterns:       return incomePatternsCandidates(ctx)
        case .subscriptionAnalysis: return subscriptionAnalysisCandidates(ctx)
        case .turningPoints:        return turningPointsCandidates(ctx)
        case .comparisonVsPrevious: return comparisonCandidates(ctx)
        case .allTimePerspective:   return allTimePerspectiveCandidates(ctx)
        }
    }
}

// MARK: - Selection with deduplication

private extension YRInsightEngine {

    static func selectTop(_ candidates: [Candidate], range: ClosedRange<Int>, alwaysOn: Bool) -> [Candidate] {
        guard !candidates.isEmpty else { return [] }

        var remaining = candidates
        var selected: [Candidate] = []
        var usedTags: [String: Int] = [:]

        while selected.count < range.upperBound && !remaining.isEmpty {
            // Recompute duplication penalties
            for i in remaining.indices {
                let shared = remaining[i].tags.reduce(0) { $0 + (usedTags[$1] ?? 0) }
                remaining[i].duplicationPenalty = min(5, Double(shared) * 1.5)
            }
            remaining.sort { $0.totalScore > $1.totalScore }

            let best = remaining.removeFirst()
            let threshold: Double = (alwaysOn && selected.count < range.lowerBound) ? 1.0 : 3.0
            if best.totalScore < threshold && selected.count >= range.lowerBound { break }
            selected.append(best)
            for tag in best.tags { usedTags[tag, default: 0] += 1 }
        }
        return selected
    }
}

// MARK: - 1. Year Summary

private extension YRInsightEngine {

    static func yearSummaryCandidates(_ ctx: Context) -> [Candidate] {
        let md = ctx.monthlyData
        guard md.count >= 2 else { return [] }
        var c: [Candidate] = []

        let expenses = md.map(\.expense)
        let incomes = md.map(\.income)
        let nets = md.map(\.net)
        let totalExp = expenses.reduce(0, +)
        let totalInc = incomes.reduce(0, +)
        let totalSubExp = md.reduce(0) { $0 + $1.subscriptionExpense }
        let netVal = totalInc - totalExp
        let cur = ctx.baseCurrency

        // Net result
        c.append(Candidate(
            section: .yearSummary, icon: netVal >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill",
            title: L("yr_ins_net_title"),
            body: L("yr_ins_net_body", g(fc(totalInc, cur)), r(fc(totalExp, cur)), fnet(netVal, cur)),
            accentColor: netVal >= 0 ? .green : .red,
            tags: ["net", "total"], significance: 5, novelty: 3, confidence: 5, clarity: 5
        ))

        // Best month
        if let bestIdx = nets.indices.max(by: { nets[$0] < nets[$1] }) {
            c.append(Candidate(
                section: .yearSummary, icon: "crown.fill", title: L("yr_ins_best_month_title"),
                body: L("yr_ins_best_month_body", b(md[bestIdx].fullLabel), fnet(nets[bestIdx], cur)),
                accentColor: .green,
                tags: ["best_month", "net"], significance: 4, novelty: 3, confidence: 5, clarity: 5
            ))
        }

        // Toughest month
        if let worstIdx = nets.indices.min(by: { nets[$0] < nets[$1] }) {
            c.append(Candidate(
                section: .yearSummary, icon: "exclamationmark.triangle.fill", title: L("yr_ins_worst_month_title"),
                body: L("yr_ins_worst_month_body", b(md[worstIdx].fullLabel), fnet(nets[worstIdx], cur)),
                accentColor: .orange,
                tags: ["worst_month", "net"], significance: 4, novelty: 3, confidence: 5, clarity: 5
            ))
        }

        // Peak spending
        if let hi = expenses.indices.max(by: { expenses[$0] < expenses[$1] }) {
            c.append(Candidate(
                section: .yearSummary, icon: "flame.fill", title: L("yr_ins_peak_spend_title"),
                body: L("yr_ins_peak_spend_body", b(md[hi].fullLabel), r(fc(expenses[hi], cur))),
                accentColor: .red,
                tags: ["peak_spend", "expense"], significance: 3, novelty: 2, confidence: 5, clarity: 5
            ))
        }

        // Peak income
        if let hi = incomes.indices.max(by: { incomes[$0] < incomes[$1] }), incomes[hi] > 0 {
            c.append(Candidate(
                section: .yearSummary, icon: "star.fill", title: L("yr_ins_peak_income_title"),
                body: L("yr_ins_peak_income_body", b(md[hi].fullLabel), g(fc(incomes[hi], cur))),
                accentColor: .green,
                tags: ["peak_income", "income"], significance: 3, novelty: 2, confidence: 5, clarity: 5
            ))
        }

        // Strongest recovery
        for i in 1..<nets.count {
            if nets[i - 1] < 0 && nets[i] > nets[i - 1] {
                let recovery = nets[i] - nets[i - 1]
                let meanExp = totalExp / Double(md.count)
                let sig = min(5, recovery / max(1, meanExp) * 3)
                c.append(Candidate(
                    section: .yearSummary, icon: "arrow.uturn.up.circle.fill", title: L("yr_ins_recovery_title"),
                    body: L("yr_ins_recovery_body", b(md[i].fullLabel), g(fc(recovery, cur))),
                    accentColor: .green,
                    tags: ["recovery", "net"], significance: sig, novelty: 4, confidence: 4, clarity: 4
                ))
                break
            }
        }

        // Strongest quarter
        if md.count >= 4 {
            let quarterNets = quarterAggregates(md).map { $0.net }
            if let bestQ = quarterNets.indices.max(by: { quarterNets[$0] < quarterNets[$1] }) {
                c.append(Candidate(
                    section: .yearSummary, icon: "chart.bar.fill", title: L("yr_ins_strongest_q_title"),
                    body: L("yr_ins_strongest_q_body", b("Q\(bestQ + 1)"), fnet(quarterNets[bestQ], cur)),
                    accentColor: .green,
                    tags: ["quarter", "net"], significance: 3, novelty: 3, confidence: 4, clarity: 4
                ))
            }
        }

        // Weakest quarter
        if md.count >= 4 {
            let quarterExps = quarterAggregates(md).map { $0.expense }
            if let worstQ = quarterExps.indices.max(by: { quarterExps[$0] < quarterExps[$1] }) {
                c.append(Candidate(
                    section: .yearSummary, icon: "exclamationmark.circle", title: L("yr_ins_weakest_q_title"),
                    body: L("yr_ins_weakest_q_body", b("Q\(worstQ + 1)"), r(fc(quarterExps[worstQ], cur))),
                    accentColor: .orange,
                    tags: ["quarter", "expense"], significance: 3, novelty: 3, confidence: 4, clarity: 4
                ))
            }
        }

        // Savings rate
        if totalInc > 0 {
            let rate = (totalInc - totalExp) / totalInc * 100
            c.append(Candidate(
                section: .yearSummary, icon: "percent", title: L("yr_ins_savings_rate_title"),
                body: L("yr_ins_savings_rate_body", rate >= 0 ? g(fp(rate)) : r(fp(rate))),
                accentColor: rate >= 0 ? .green : .red,
                tags: ["savings", "net"], significance: 4, novelty: 3, confidence: 5, clarity: 5
            ))
        }

        // Subscription burden
        if totalExp > 0 && totalSubExp > 0 {
            let pct = totalSubExp / totalExp * 100
            let sig = min(5, pct / 10)
            c.append(Candidate(
                section: .yearSummary, icon: "repeat.circle.fill", title: L("yr_ins_sub_burden_title"),
                body: L("yr_ins_sub_burden_body", r(fp(pct)), r(fc(totalSubExp, cur))),
                accentColor: .orange,
                tags: ["subscription", "burden"], significance: sig, novelty: 3, confidence: 5, clarity: 4
            ))
        }

        return c
    }
}

// MARK: - 2. Spending Patterns

private extension YRInsightEngine {

    static func spendingPatternsCandidates(_ ctx: Context) -> [Candidate] {
        let md = ctx.monthlyData
        guard md.count >= 3 else { return [] }
        var c: [Candidate] = []

        let expenses = md.map(\.expense)
        let meanExp = expenses.reduce(0, +) / Double(expenses.count)
        let sd = stdDev(expenses)
        let cv = meanExp > 0 ? sd / meanExp : 0
        let totalExp = expenses.reduce(0, +)
        let totalSubExp = md.reduce(0) { $0 + $1.subscriptionExpense }
        let subShare = totalExp > 0 ? totalSubExp / totalExp : 0

        // Personality
        let personality: String
        if subShare > 0.4 { personality = L("yr_personality_sub_heavy") }
        else if cv < 0.10 { personality = L("yr_personality_disciplined") }
        else if cv < 0.15 { personality = L("yr_personality_steady") }
        else if cv < 0.25 {
            // Check front vs back loading
            let firstHalf = expenses.prefix(md.count / 2).reduce(0, +)
            let secondHalf = expenses.suffix(md.count - md.count / 2).reduce(0, +)
            if firstHalf > secondHalf * 1.2 { personality = L("yr_personality_front_loaded") }
            else if secondHalf > firstHalf * 1.2 { personality = L("yr_personality_back_loaded") }
            else { personality = L("yr_personality_seasonal") }
        }
        else if cv < 0.35 {
            // Check recovery pattern
            var recoveries = 0
            for i in 1..<expenses.count {
                if expenses[i-1] > meanExp * 1.2 && expenses[i] < meanExp * 1.1 { recoveries += 1 }
            }
            if recoveries >= 2 { personality = L("yr_personality_recovery_driven") }
            else { personality = L("yr_personality_spike_prone") }
        }
        else { personality = L("yr_personality_chaotic") }

        c.append(Candidate(
            section: .spendingPatterns, icon: "person.fill.viewfinder", title: L("yr_ins_personality_title"),
            body: L("yr_ins_personality_body", b(personality)),
            accentColor: .blue,
            tags: ["personality"], significance: 4, novelty: 4, confidence: 4, clarity: 5
        ))

        // Consistency score
        let consistency = max(0, min(100, (1 - cv) * 100))
        c.append(Candidate(
            section: .spendingPatterns, icon: "metronome.fill", title: L("yr_ins_consistency_title"),
            body: L("yr_ins_consistency_body", b(String(format: "%.0f", consistency))),
            accentColor: consistency > 70 ? .green : .orange,
            tags: ["consistency", "volatility"], significance: 3, novelty: 3, confidence: 5, clarity: 5
        ))

        // Volatility
        let volatilityLabel = cv > 0.35 ? L("yr_volatility_high") : (cv > 0.2 ? L("yr_volatility_moderate") : L("yr_volatility_low"))
        c.append(Candidate(
            section: .spendingPatterns, icon: "waveform.path.ecg", title: L("yr_ins_volatility_title"),
            body: L("yr_ins_volatility_body", b(volatilityLabel)),
            accentColor: cv > 0.3 ? .orange : .green,
            tags: ["volatility", "consistency"], significance: 3, novelty: 3, confidence: 4, clarity: 4
        ))

        // Acceleration
        if md.count >= 6 {
            let halfN = md.count / 2
            let firstHalf = expenses.prefix(halfN).reduce(0, +) / Double(halfN)
            let secondHalf = expenses.suffix(halfN).reduce(0, +) / Double(halfN)
            if firstHalf > 0 {
                let accel = (secondHalf - firstHalf) / firstHalf * 100
                let label = accel > 5 ? L("yr_accel_up") : (accel < -5 ? L("yr_accel_down") : L("yr_accel_flat"))
                let pctStr = accel > 5 ? r(fp(abs(accel))) : g(fp(abs(accel)))
                let sig = min(5, abs(accel) / 10)
                c.append(Candidate(
                    section: .spendingPatterns, icon: "gauge.with.dots.needle.67percent", title: L("yr_ins_acceleration_title"),
                    body: L("yr_ins_acceleration_body", b(label), pctStr),
                    accentColor: accel > 5 ? .red : .green,
                    tags: ["acceleration", "trend"], significance: sig, novelty: 3, confidence: 4, clarity: 4
                ))
            }
        }

        // Seasonality
        if md.count >= 6 {
            let firstHalfExp = expenses.prefix(md.count / 2).reduce(0, +)
            let secondHalfExp = expenses.suffix(md.count - md.count / 2).reduce(0, +)
            let heavier = firstHalfExp > secondHalfExp ? L("yr_seasonality_first_half") : L("yr_seasonality_second_half")
            let ratio = max(firstHalfExp, secondHalfExp) / max(1, min(firstHalfExp, secondHalfExp))
            if ratio > 1.2 {
                c.append(Candidate(
                    section: .spendingPatterns, icon: "calendar.badge.clock", title: L("yr_ins_seasonality_title"),
                    body: L("yr_ins_seasonality_body", b(heavier)),
                    accentColor: .blue,
                    tags: ["seasonality", "trend"], significance: min(5, ratio), novelty: 3, confidence: 4, clarity: 4
                ))
            }
        }

        // Rebound pattern
        var rebounds = 0
        for i in 1..<expenses.count {
            if expenses[i - 1] > meanExp * 1.2 && expenses[i] < meanExp { rebounds += 1 }
        }
        if rebounds > 0 {
            c.append(Candidate(
                section: .spendingPatterns, icon: "arrow.triangle.2.circlepath", title: L("yr_ins_rebound_title"),
                body: L("yr_ins_rebound_body", b("\(rebounds)")),
                accentColor: .green,
                tags: ["rebound", "recovery"], significance: min(5, Double(rebounds) * 2), novelty: 4, confidence: 4, clarity: 4
            ))
        }

        // Streaks (above average)
        var streak = 0, maxStreak = 0
        for e in expenses {
            if e > meanExp { streak += 1; maxStreak = max(maxStreak, streak) }
            else { streak = 0 }
        }
        if maxStreak >= 3 {
            c.append(Candidate(
                section: .spendingPatterns, icon: "flame.circle.fill", title: L("yr_ins_streak_title"),
                body: L("yr_ins_streak_body", b("\(maxStreak)")),
                accentColor: .red,
                tags: ["streak", "expense"], significance: min(5, Double(maxStreak)), novelty: 4, confidence: 5, clarity: 4
            ))
        }

        // Concentration over time
        let sortedExps = expenses.sorted(by: >)
        if md.count >= 4 {
            let top2 = sortedExps.prefix(2).reduce(0, +)
            let share = totalExp > 0 ? top2 / totalExp : 0
            if share > 0.4 {
                c.append(Candidate(
                    section: .spendingPatterns, icon: "scope", title: L("yr_ins_time_concentration_title"),
                    body: L("yr_ins_time_concentration_body", b(fp(share * 100))),
                    accentColor: .orange,
                    tags: ["concentration", "time"], significance: min(5, share * 6), novelty: 4, confidence: 4, clarity: 3
                ))
            }
        }

        // Stability label
        let stabilityLabel: String
        if cv < 0.15 { stabilityLabel = L("yr_stability_controlled") }
        else if cv < 0.30 { stabilityLabel = L("yr_stability_predictable") }
        else { stabilityLabel = L("yr_stability_uneven") }
        c.append(Candidate(
            section: .spendingPatterns, icon: "shield.checkered", title: L("yr_ins_stability_title"),
            body: L("yr_ins_stability_body", b(stabilityLabel)),
            accentColor: cv < 0.25 ? .green : .orange,
            tags: ["stability", "consistency"], significance: 2, novelty: 2, confidence: 4, clarity: 5
        ))

        return c
    }
}

// MARK: - 3. Category Intelligence

private extension YRInsightEngine {

    static func categoryIntelligenceCandidates(_ ctx: Context) -> [Candidate] {
        let md = ctx.monthlyData
        guard md.count >= 2 else { return [] }
        var c: [Candidate] = []

        let expTxs = ctx.transactions.filter { $0.type.lowercased() != "income" }
        var catMonthly: [String: [String: Double]] = [:]
        var catTotal: [String: Double] = [:]

        for tx in expTxs {
            let mk = String(tx.transactionDate.prefix(7))
            let amt = YearInReviewViewModel.amountInBase(tx)
            catMonthly[tx.category, default: [:]][mk, default: 0] += amt
            catTotal[tx.category, default: 0] += amt
        }

        let totalExp = catTotal.values.reduce(0, +)
        let sortedCats = catTotal.sorted { $0.value > $1.value }
        let cur = ctx.baseCurrency

        // Biggest category
        if let biggest = sortedCats.first {
            let name = CategoryIconHelper.displayName(categoryId: biggest.key)
            let share = totalExp > 0 ? biggest.value / totalExp * 100 : 0
            c.append(Candidate(
                section: .categoryIntelligence, icon: "trophy.fill", title: L("yr_ins_biggest_cat_title"),
                body: L("yr_ins_biggest_cat_body", b(name), r(fc(biggest.value, cur))),
                accentColor: CategoryIconHelper.color(categoryId: biggest.key),
                tags: ["biggest_cat", "cat_\(biggest.key)"], significance: 4, novelty: 2, confidence: 5, clarity: 5
            ))

            // Top category control (>35%)
            if share > 35 {
                c.append(Candidate(
                    section: .categoryIntelligence, icon: "exclamationmark.bubble.fill",
                    title: L("yr_ins_top_cat_control_title"),
                    body: L("yr_ins_top_cat_control_body", b(name), r(fp(share))),
                    accentColor: .purple,
                    tags: ["biggest_cat", "concentration", "cat_\(biggest.key)"],
                    significance: min(5, share / 10), novelty: 3, confidence: 5, clarity: 4
                ))
            }
        }

        // Second biggest
        if sortedCats.count >= 2 {
            let second = sortedCats[1]
            let name = CategoryIconHelper.displayName(categoryId: second.key)
            c.append(Candidate(
                section: .categoryIntelligence, icon: "2.circle.fill", title: L("yr_ins_second_cat_title"),
                body: L("yr_ins_second_cat_body", b(name), r(fc(second.value, cur))),
                accentColor: CategoryIconHelper.color(categoryId: second.key),
                tags: ["second_cat", "cat_\(second.key)"], significance: 2, novelty: 2, confidence: 5, clarity: 5
            ))
        }

        // Category concentration (top 2)
        if sortedCats.count >= 2 && totalExp > 0 {
            let top2 = (sortedCats[0].value + sortedCats[1].value) / totalExp * 100
            c.append(Candidate(
                section: .categoryIntelligence, icon: "target", title: L("yr_ins_cat_concentration_title"),
                body: L("yr_ins_cat_concentration_body", b(fp(top2))),
                accentColor: top2 > 60 ? .orange : .blue,
                tags: ["concentration", "category"], significance: top2 > 60 ? 4 : 2, novelty: 3, confidence: 5, clarity: 4
            ))
        }

        // Fastest growing category
        if md.count >= 6 {
            let halfPoint = md.count / 2
            let firstKeys = Set(md.prefix(halfPoint).map(\.monthKey))
            let secondKeys = Set(md.suffix(md.count - halfPoint).map(\.monthKey))

            var growthRates: [(String, Double)] = []
            for (cat, monthly) in catMonthly {
                let firstAvg = firstKeys.reduce(0.0) { $0 + (monthly[$1] ?? 0) } / max(1, Double(firstKeys.count))
                let secondAvg = secondKeys.reduce(0.0) { $0 + (monthly[$1] ?? 0) } / max(1, Double(secondKeys.count))
                if firstAvg > 10 {
                    growthRates.append((cat, (secondAvg - firstAvg) / firstAvg * 100))
                }
            }
            if let fastest = growthRates.max(by: { $0.1 < $1.1 }), fastest.1 > 20 {
                let name = CategoryIconHelper.displayName(categoryId: fastest.0)
                c.append(Candidate(
                    section: .categoryIntelligence, icon: "chart.line.uptrend.xyaxis",
                    title: L("yr_ins_fastest_cat_title"),
                    body: L("yr_ins_fastest_cat_body", b(name), r(fp(fastest.1))),
                    accentColor: .orange,
                    tags: ["growth", "cat_\(fastest.0)"], significance: min(5, fastest.1 / 20), novelty: 4, confidence: 3, clarity: 4
                ))
            }

            // Category drift (top H1 vs top H2)
            let topFirst = catMonthly.max { a, b in
                firstKeys.reduce(0.0) { $0 + (a.value[$1] ?? 0) } < firstKeys.reduce(0.0) { $0 + (b.value[$1] ?? 0) }
            }
            let topSecond = catMonthly.max { a, b in
                secondKeys.reduce(0.0) { $0 + (a.value[$1] ?? 0) } < secondKeys.reduce(0.0) { $0 + (b.value[$1] ?? 0) }
            }
            if let tf = topFirst, let ts = topSecond, tf.key != ts.key {
                let n1 = CategoryIconHelper.displayName(categoryId: tf.key)
                let n2 = CategoryIconHelper.displayName(categoryId: ts.key)
                c.append(Candidate(
                    section: .categoryIntelligence, icon: "arrow.left.arrow.right", title: L("yr_ins_cat_drift_title"),
                    body: L("yr_ins_cat_drift_body", b(n1), b(n2)),
                    accentColor: .purple,
                    tags: ["drift", "shift", "cat_\(tf.key)", "cat_\(ts.key)"],
                    significance: 4, novelty: 5, confidence: 3, clarity: 4
                ))
            }

            // Most stable category
            var catVariances: [(String, Double)] = []
            for (cat, monthly) in catMonthly {
                let vals = md.map { monthly[$0.monthKey] ?? 0 }
                let sd = stdDev(vals)
                let mean = vals.reduce(0, +) / max(1, Double(vals.count))
                if mean > 10 { catVariances.append((cat, mean > 0 ? sd / mean : 99)) }
            }
            if let most = catVariances.min(by: { $0.1 < $1.1 }), most.1 < 0.3 {
                let name = CategoryIconHelper.displayName(categoryId: most.0)
                c.append(Candidate(
                    section: .categoryIntelligence, icon: "checkmark.seal.fill",
                    title: L("yr_ins_most_stable_cat_title"),
                    body: L("yr_ins_most_stable_cat_body", b(name)),
                    accentColor: .green,
                    tags: ["stable_cat", "cat_\(most.0)"], significance: 2, novelty: 4, confidence: 4, clarity: 4
                ))
            }

            // Surprise category
            for (cat, monthly) in catMonthly {
                let firstAvg = firstKeys.reduce(0.0) { $0 + (monthly[$1] ?? 0) } / max(1, Double(firstKeys.count))
                let secondAvg = secondKeys.reduce(0.0) { $0 + (monthly[$1] ?? 0) } / max(1, Double(secondKeys.count))
                if firstAvg < 5 && secondAvg > 30 {
                    let name = CategoryIconHelper.displayName(categoryId: cat)
                    c.append(Candidate(
                        section: .categoryIntelligence, icon: "sparkles",
                        title: L("yr_ins_surprise_cat_title"),
                        body: L("yr_ins_surprise_cat_body", b(name)),
                        accentColor: .yellow,
                        tags: ["surprise", "cat_\(cat)"], significance: 4, novelty: 5, confidence: 3, clarity: 4
                    ))
                    break
                }
            }
        }

        // Essential vs flexible
        let essentialIds = Set(["food", "transport", "housing", "health", "bills"])
        let essentialTotal = catTotal.filter { essentialIds.contains($0.key) }.values.reduce(0, +)
        if totalExp > 0 {
            let essentialPct = essentialTotal / totalExp * 100
            let dominant = essentialPct > 55 ? L("yr_essential_dominant") : L("yr_flexible_dominant")
            c.append(Candidate(
                section: .categoryIntelligence, icon: "scale.3d", title: L("yr_ins_essential_vs_flex_title"),
                body: L("yr_ins_essential_vs_flex_body", b(dominant), b(fp(essentialPct))),
                accentColor: .blue,
                tags: ["essential", "flexible", "category"], significance: 3, novelty: 3, confidence: 4, clarity: 4
            ))
        }

        return c
    }
}

// MARK: - 4. Selected Month

private extension YRInsightEngine {

    static func selectedMonthCandidates(_ ctx: Context) -> [Candidate] {
        let md = ctx.monthlyData
        guard let idx = ctx.selectedMonthIndex, idx < md.count else { return [] }
        var c: [Candidate] = []
        let m = md[idx]
        let cur = ctx.baseCurrency

        let expenses = md.map(\.expense)
        let meanExp = expenses.reduce(0, +) / max(1, Double(expenses.count))

        // Month vs average
        let delta = meanExp > 0 ? (m.expense - meanExp) / meanExp * 100 : 0
        let deltaStr = delta >= 0 ? r(fp(abs(delta))) : g(fp(abs(delta)))
        c.append(Candidate(
            section: .selectedMonth, icon: "chart.bar.fill", title: L("yr_ins_month_vs_avg_title"),
            body: L("yr_ins_month_vs_avg_body", b(m.fullLabel), deltaStr, delta >= 0 ? L("yr_above") : L("yr_below")),
            accentColor: delta > 0 ? .red : .green,
            tags: ["month_avg", "expense"], significance: min(5, abs(delta) / 10), novelty: 3, confidence: 5, clarity: 5
        ))

        // Month net
        c.append(Candidate(
            section: .selectedMonth, icon: "banknote.fill", title: L("yr_ins_month_net_title"),
            body: L("yr_ins_month_net_body", b(m.fullLabel), fnet(m.net, cur)),
            accentColor: m.net >= 0 ? .green : .red,
            tags: ["month_net", "net"], significance: 3, novelty: 2, confidence: 5, clarity: 5
        ))

        // Month over month
        if idx > 0 {
            let prev = md[idx - 1]
            let mom = prev.expense > 0 ? (m.expense - prev.expense) / prev.expense * 100 : 0
            let momStr = mom >= 0 ? r(fp(abs(mom))) : g(fp(abs(mom)))
            c.append(Candidate(
                section: .selectedMonth, icon: "arrow.left.arrow.right.circle.fill", title: L("yr_ins_mom_title"),
                body: L("yr_ins_mom_body", b(m.fullLabel), b(prev.fullLabel), momStr, mom >= 0 ? L("yr_more") : L("yr_less")),
                accentColor: mom > 0 ? .red : .green,
                tags: ["mom", "expense"], significance: min(5, abs(mom) / 10), novelty: 3, confidence: 5, clarity: 4
            ))
        }

        // Subscription load this month
        if m.subscriptionExpense > 0 && m.expense > 0 {
            let pct = m.subscriptionExpense / m.expense * 100
            c.append(Candidate(
                section: .selectedMonth, icon: "repeat", title: L("yr_ins_month_sub_title"),
                body: L("yr_ins_month_sub_body", b(m.fullLabel), r(fp(pct)), r(fc(m.subscriptionExpense, cur))),
                accentColor: .orange,
                tags: ["subscription", "month_sub"], significance: min(5, pct / 10), novelty: 3, confidence: 5, clarity: 4
            ))
        }

        // Dominant category this month
        let monthTxs = ctx.transactions.filter {
            $0.type.lowercased() != "income" && String($0.transactionDate.prefix(7)) == m.monthKey
        }
        var catTotals: [String: Double] = [:]
        for tx in monthTxs { catTotals[tx.category, default: 0] += YearInReviewViewModel.amountInBase(tx) }
        if let top = catTotals.max(by: { $0.value < $1.value }), m.expense > 0 {
            let name = CategoryIconHelper.displayName(categoryId: top.key)
            let share = top.value / m.expense * 100
            c.append(Candidate(
                section: .selectedMonth, icon: "star.circle.fill", title: L("yr_ins_month_dominant_title"),
                body: L("yr_ins_month_dominant_body", b(name), r(fp(share))),
                accentColor: CategoryIconHelper.color(categoryId: top.key),
                tags: ["month_cat", "cat_\(top.key)"], significance: share > 40 ? 4 : 2, novelty: 3, confidence: 5, clarity: 5
            ))
        }

        // Biggest transaction this month
        if let biggest = monthTxs.max(by: { YearInReviewViewModel.amountInBase($0) < YearInReviewViewModel.amountInBase($1) }) {
            let amt = YearInReviewViewModel.amountInBase(biggest)
            let merchant = biggest.merchant ?? CategoryIconHelper.displayName(categoryId: biggest.category)
            if m.expense > 0 && amt / m.expense > 0.15 {
                c.append(Candidate(
                    section: .selectedMonth, icon: "creditcard.fill", title: L("yr_ins_month_biggest_tx_title"),
                    body: L("yr_ins_month_biggest_tx_body", b(merchant), r(fc(amt, cur))),
                    accentColor: .red,
                    tags: ["biggest_tx"], significance: min(5, amt / m.expense * 5), novelty: 4, confidence: 5, clarity: 5
                ))
            }
        }

        // Month label
        let label: String
        if m.net > 0 && abs(delta) < 15 { label = L("yr_month_label_balanced") }
        else if m.net > 0 && m.expense < meanExp * 0.85 { label = L("yr_month_label_clean") }
        else if idx > 0 && md[idx-1].net < 0 && m.net > 0 { label = L("yr_month_label_recovery") }
        else if m.expense > meanExp * 1.3 { label = L("yr_month_label_overloaded") }
        else if m.expense > meanExp * 1.15 { label = L("yr_month_label_spike") }
        else { label = L("yr_month_label_balanced") }
        c.append(Candidate(
            section: .selectedMonth, icon: "tag.fill", title: L("yr_ins_month_label_title"),
            body: L("yr_ins_month_label_body", b(m.fullLabel), b(label)),
            accentColor: .blue,
            tags: ["month_label"], significance: 2, novelty: 3, confidence: 3, clarity: 5
        ))

        return c
    }
}

// MARK: - 5. Smart Insights

private extension YRInsightEngine {

    static func smartInsightsCandidates(_ ctx: Context) -> [Candidate] {
        let md = ctx.monthlyData
        guard md.count >= 3 else { return [] }
        var c: [Candidate] = []

        let expenses = md.map(\.expense)
        let incomes = md.map(\.income)
        let meanExp = expenses.reduce(0, +) / Double(expenses.count)
        let totalExp = expenses.reduce(0, +)
        let totalInc = incomes.reduce(0, +)
        let totalSubExp = md.reduce(0) { $0 + $1.subscriptionExpense }
        let cur = ctx.baseCurrency

        let expTxs = ctx.transactions.filter { $0.type.lowercased() != "income" }
        var catTotal: [String: Double] = [:]
        for tx in expTxs { catTotal[tx.category, default: 0] += YearInReviewViewModel.amountInBase(tx) }

        // Invisible tax (subscriptions)
        if totalSubExp > 0 {
            c.append(Candidate(
                section: .smartInsights, icon: "eye.slash.fill", title: L("yr_ins_invisible_tax_title"),
                body: L("yr_ins_invisible_tax_body", r(fc(totalSubExp, cur))),
                accentColor: .orange,
                tags: ["subscription", "invisible"], significance: min(5, totalSubExp / max(1, totalExp) * 10),
                novelty: 4, confidence: 5, clarity: 4
            ))
        }

        // One category changed everything (>35%)
        if let biggest = catTotal.max(by: { $0.value < $1.value }), totalExp > 0 {
            let share = biggest.value / totalExp
            if share > 0.35 {
                let name = CategoryIconHelper.displayName(categoryId: biggest.key)
                c.append(Candidate(
                    section: .smartInsights, icon: "exclamationmark.bubble.fill",
                    title: L("yr_ins_one_cat_title"),
                    body: L("yr_ins_one_cat_body", b(name), r(fp(share * 100))),
                    accentColor: .purple,
                    tags: ["one_cat", "concentration"], significance: min(5, share * 6), novelty: 4, confidence: 5, clarity: 5
                ))
            }
        }

        // Lifestyle inflation
        if md.count >= 6 {
            let halfN = md.count / 2
            let firstHalfAvg = expenses.prefix(halfN).reduce(0, +) / Double(halfN)
            let secondHalfAvg = expenses.suffix(halfN).reduce(0, +) / Double(halfN)
            if firstHalfAvg > 0 && secondHalfAvg > firstHalfAvg * 1.15 {
                let pct = (secondHalfAvg - firstHalfAvg) / firstHalfAvg * 100
                c.append(Candidate(
                    section: .smartInsights, icon: "arrow.up.right.circle.fill", title: L("yr_ins_lifestyle_title"),
                    body: L("yr_ins_lifestyle_body", r(fp(pct))),
                    accentColor: .orange,
                    tags: ["inflation", "trend"], significance: min(5, pct / 10), novelty: 4, confidence: 4, clarity: 4
                ))
            }
        }

        // Recovery power
        var quickRecoveries = 0
        for i in 1..<expenses.count {
            if expenses[i-1] > meanExp * 1.2 && expenses[i] < meanExp * 1.05 { quickRecoveries += 1 }
        }
        if quickRecoveries >= 2 {
            c.append(Candidate(
                section: .smartInsights, icon: "bolt.heart.fill", title: L("yr_ins_recovery_power_title"),
                body: L("yr_ins_recovery_power_body"),
                accentColor: .green,
                tags: ["recovery", "pattern"], significance: 4, novelty: 5, confidence: 4, clarity: 4
            ))
        }

        // False stability
        if md.count >= 6 {
            let expCV = meanExp > 0 ? stdDev(expenses) / meanExp : 0
            // Check if category mix changed while total stayed stable
            let halfPoint = md.count / 2
            let firstKeys = Set(md.prefix(halfPoint).map(\.monthKey))
            let secondKeys = Set(md.suffix(md.count - halfPoint).map(\.monthKey))

            var catMonthly: [String: [String: Double]] = [:]
            for tx in expTxs {
                let mk = String(tx.transactionDate.prefix(7))
                catMonthly[tx.category, default: [:]][mk, default: 0] += YearInReviewViewModel.amountInBase(tx)
            }

            var shiftsCount = 0
            for (_, monthly) in catMonthly {
                let firstAvg = firstKeys.reduce(0.0) { $0 + (monthly[$1] ?? 0) } / max(1, Double(firstKeys.count))
                let secondAvg = secondKeys.reduce(0.0) { $0 + (monthly[$1] ?? 0) } / max(1, Double(secondKeys.count))
                if firstAvg > 10 && abs(secondAvg - firstAvg) / firstAvg > 0.3 { shiftsCount += 1 }
            }

            if expCV < 0.2 && shiftsCount >= 2 {
                c.append(Candidate(
                    section: .smartInsights, icon: "theatermasks.fill", title: L("yr_ins_false_stability_title"),
                    body: L("yr_ins_false_stability_body"),
                    accentColor: .purple,
                    tags: ["stability", "shift"], significance: 4, novelty: 5, confidence: 3, clarity: 3
                ))
            }
        }

        // Expense drag (recurring weakening healthy months)
        if totalSubExp > 0 && totalInc > 0 {
            let subToIncome = totalSubExp / totalInc
            if subToIncome > 0.15 {
                c.append(Candidate(
                    section: .smartInsights, icon: "arrow.down.right.circle.fill",
                    title: L("yr_ins_expense_drag_title"),
                    body: L("yr_ins_expense_drag_body", r(fp(subToIncome * 100))),
                    accentColor: .red,
                    tags: ["subscription", "drag"], significance: min(5, subToIncome * 10), novelty: 4, confidence: 4, clarity: 3
                ))
            }
        }

        // Timing insight (income vs expense peaks don't align)
        if md.count >= 4 {
            let peakExpIdx = expenses.indices.max(by: { expenses[$0] < expenses[$1] })
            let peakIncIdx = incomes.indices.max(by: { incomes[$0] < incomes[$1] })
            if let ei = peakExpIdx, let ii = peakIncIdx, incomes[ii] > 0, abs(ei - ii) >= 2 {
                c.append(Candidate(
                    section: .smartInsights, icon: "clock.arrow.2.circlepath", title: L("yr_ins_timing_title"),
                    body: L("yr_ins_timing_body", b(md[ii].fullLabel), b(md[ei].fullLabel)),
                    accentColor: .blue,
                    tags: ["timing", "income", "expense"], significance: 3, novelty: 5, confidence: 4, clarity: 3
                ))
            }
        }

        // Efficiency insight
        if md.count >= 6 && totalInc > 0 {
            let halfN = md.count / 2
            let firstInc = incomes.prefix(halfN).reduce(0, +) / Double(halfN)
            let secondInc = incomes.suffix(halfN).reduce(0, +) / Double(halfN)
            let firstExp = expenses.prefix(halfN).reduce(0, +) / Double(halfN)
            let secondExp = expenses.suffix(halfN).reduce(0, +) / Double(halfN)
            if firstInc > 0 && firstExp > 0 {
                let incGrowth = (secondInc - firstInc) / firstInc
                let expGrowth = (secondExp - firstExp) / firstExp
                if incGrowth > expGrowth + 0.05 && incGrowth > 0 {
                    c.append(Candidate(
                        section: .smartInsights, icon: "bolt.fill", title: L("yr_ins_efficiency_title"),
                        body: L("yr_ins_efficiency_body"),
                        accentColor: .green,
                        tags: ["efficiency", "income", "trend"], significance: 4, novelty: 5, confidence: 3, clarity: 4
                    ))
                }
            }
        }

        // Calmest quarter
        if md.count >= 4 {
            let quarters = quarterAggregates(md)
            var quarterVols: [(Int, Double)] = []
            for (i, q) in quarters.enumerated() {
                if q.months.count >= 2 {
                    quarterVols.append((i + 1, stdDev(q.months.map(\.expense))))
                }
            }
            if let calmest = quarterVols.min(by: { $0.1 < $1.1 }) {
                c.append(Candidate(
                    section: .smartInsights, icon: "leaf.fill", title: L("yr_ins_calmest_q_title"),
                    body: L("yr_ins_calmest_q_body", b("Q\(calmest.0)")),
                    accentColor: .green,
                    tags: ["quarter", "calm"], significance: 2, novelty: 3, confidence: 4, clarity: 4
                ))
            }
        }

        return c
    }
}

// MARK: - 6. Income Patterns

private extension YRInsightEngine {

    static func incomePatternsCandidates(_ ctx: Context) -> [Candidate] {
        let md = ctx.monthlyData
        let incomes = md.map(\.income)
        let totalInc = incomes.reduce(0, +)
        guard totalInc > 0, md.count >= 3 else { return [] }
        var c: [Candidate] = []
        let cur = ctx.baseCurrency

        let meanInc = totalInc / Double(md.count)
        let incCV = meanInc > 0 ? stdDev(incomes) / meanInc : 0

        // Income stability
        let label = incCV < 0.15 ? L("yr_income_stable") : (incCV < 0.35 ? L("yr_income_variable") : L("yr_income_volatile"))
        c.append(Candidate(
            section: .incomePatterns, icon: "waveform.path", title: L("yr_ins_income_stability_title"),
            body: L("yr_ins_income_stability_body", b(label)),
            accentColor: incCV < 0.2 ? .green : .orange,
            tags: ["income", "stability"], significance: 3, novelty: 3, confidence: 4, clarity: 5
        ))

        // Peak income months concentration
        let nonZero = incomes.filter { $0 > 0 }
        if nonZero.count >= 2 {
            let top2 = incomes.sorted(by: >).prefix(2).reduce(0, +)
            let share = top2 / totalInc * 100
            if share > 50 {
                c.append(Candidate(
                    section: .incomePatterns, icon: "chart.pie.fill", title: L("yr_ins_income_peak_title"),
                    body: L("yr_ins_income_peak_body", b(fp(share))),
                    accentColor: share > 70 ? .orange : .blue,
                    tags: ["income", "concentration"], significance: min(5, share / 20), novelty: 4, confidence: 4, clarity: 4
                ))
            }
        }

        // Strongest income quarter
        if md.count >= 4 {
            let quarters = quarterAggregates(md)
            let quarterInc = quarters.enumerated().map { ($0.offset + 1, $0.element.income) }
            if let best = quarterInc.max(by: { $0.1 < $1.1 }), best.1 > 0 {
                c.append(Candidate(
                    section: .incomePatterns, icon: "star.circle.fill", title: L("yr_ins_income_best_q_title"),
                    body: L("yr_ins_income_best_q_body", b("Q\(best.0)"), g(fc(best.1, cur))),
                    accentColor: .green,
                    tags: ["income", "quarter"], significance: 3, novelty: 3, confidence: 4, clarity: 4
                ))
            }
        }

        // Recurring income coverage
        let subInc = md.reduce(0) { $0 + $1.subscriptionIncome }
        if subInc > 0 && totalInc > 0 {
            let pct = subInc / totalInc * 100
            c.append(Candidate(
                section: .incomePatterns, icon: "repeat", title: L("yr_ins_recurring_income_title"),
                body: L("yr_ins_recurring_income_body", b(fp(pct))),
                accentColor: .green,
                tags: ["income", "recurring"], significance: 3, novelty: 4, confidence: 4, clarity: 4
            ))
        }

        // Income vs previous period
        if let prevTxs = ctx.previousPeriodTransactions {
            let prevInc = prevTxs.filter { $0.type.lowercased() == "income" }.reduce(0.0) { $0 + YearInReviewViewModel.amountInBase($1) }
            if prevInc > 0 {
                let change = (totalInc - prevInc) / prevInc * 100
                c.append(Candidate(
                    section: .incomePatterns, icon: "arrow.up.arrow.down.circle.fill",
                    title: L("yr_ins_income_vs_prev_title"),
                    body: L("yr_ins_income_vs_prev_body", change >= 0 ? g(fp(change)) : r(fp(abs(change))), change >= 0 ? L("yr_more") : L("yr_less")),
                    accentColor: change >= 0 ? .green : .red,
                    tags: ["income", "comparison"], significance: min(5, abs(change) / 10), novelty: 4, confidence: 4, clarity: 4
                ))
            }
        }

        return c
    }
}

// MARK: - 7. Subscription Analysis

private extension YRInsightEngine {

    static func subscriptionAnalysisCandidates(_ ctx: Context) -> [Candidate] {
        let md = ctx.monthlyData
        let totalExp = md.reduce(0) { $0 + $1.expense }
        let totalSubExp = md.reduce(0) { $0 + $1.subscriptionExpense }
        guard totalSubExp > 0, md.count >= 2 else { return [] }
        var c: [Candidate] = []
        let cur = ctx.baseCurrency

        // Subscription share
        if totalExp > 0 {
            let pct = totalSubExp / totalExp * 100
            c.append(Candidate(
                section: .subscriptionAnalysis, icon: "percent", title: L("yr_ins_sub_share_title"),
                body: L("yr_ins_sub_share_body", r(fp(pct)), r(fc(totalSubExp, cur))),
                accentColor: pct > 20 ? .red : .orange,
                tags: ["subscription", "share"], significance: min(5, pct / 8), novelty: 3, confidence: 5, clarity: 5
            ))
        }

        // Heaviest subscription month
        let subExps = md.map(\.subscriptionExpense)
        if let hi = subExps.indices.max(by: { subExps[$0] < subExps[$1] }), subExps[hi] > 0 {
            c.append(Candidate(
                section: .subscriptionAnalysis, icon: "calendar.badge.exclamationmark",
                title: L("yr_ins_sub_peak_month_title"),
                body: L("yr_ins_sub_peak_month_body", b(md[hi].fullLabel), r(fc(subExps[hi], cur))),
                accentColor: .orange,
                tags: ["subscription", "peak"], significance: 3, novelty: 3, confidence: 5, clarity: 5
            ))
        }

        // Fixed cost trend
        if md.count >= 6 {
            let halfN = md.count / 2
            let firstHalf = subExps.prefix(halfN).reduce(0, +) / Double(halfN)
            let secondHalf = subExps.suffix(halfN).reduce(0, +) / Double(halfN)
            if firstHalf > 0 {
                let change = (secondHalf - firstHalf) / firstHalf * 100
                if abs(change) > 10 {
                    let label = change > 0 ? L("yr_sub_trend_rising") : L("yr_sub_trend_falling")
                    c.append(Candidate(
                        section: .subscriptionAnalysis, icon: change > 0 ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis",
                        title: L("yr_ins_sub_trend_title"),
                        body: L("yr_ins_sub_trend_body", b(label), change > 0 ? r(fp(change)) : g(fp(abs(change)))),
                        accentColor: change > 0 ? .red : .green,
                        tags: ["subscription", "trend"], significance: min(5, abs(change) / 10), novelty: 4, confidence: 4, clarity: 4
                    ))
                }
            }
        }

        // Net without recurring
        let totalInc = md.reduce(0) { $0 + $1.income }
        let netWithout = totalInc - (totalExp - totalSubExp)
        let netWith = totalInc - totalExp
        if netWithout > netWith {
            c.append(Candidate(
                section: .subscriptionAnalysis, icon: "minus.circle.fill", title: L("yr_ins_sub_net_impact_title"),
                body: L("yr_ins_sub_net_impact_body", g(fc(netWithout, cur)), fnet(netWith, cur)),
                accentColor: .blue,
                tags: ["subscription", "net"], significance: 4, novelty: 4, confidence: 5, clarity: 4
            ))
        }

        // Recurring income offset
        let subInc = md.reduce(0) { $0 + $1.subscriptionIncome }
        if subInc > 0 && totalSubExp > 0 {
            let pct = subInc / totalSubExp * 100
            c.append(Candidate(
                section: .subscriptionAnalysis, icon: "arrow.left.arrow.right", title: L("yr_ins_sub_offset_title"),
                body: L("yr_ins_sub_offset_body", b(fp(pct))),
                accentColor: pct > 50 ? .green : .orange,
                tags: ["subscription", "income_offset"], significance: 3, novelty: 4, confidence: 4, clarity: 3
            ))
        }

        return c
    }
}

// MARK: - 8. Turning Points

private extension YRInsightEngine {

    static func turningPointsCandidates(_ ctx: Context) -> [Candidate] {
        let md = ctx.monthlyData
        guard md.count >= 4 else { return [] }
        var c: [Candidate] = []

        let nets = md.map(\.net)
        let expenses = md.map(\.expense)
        let cur = ctx.baseCurrency

        // Marked turning point (biggest net swing)
        var maxSwing = 0.0, swingIdx = 0
        for i in 1..<nets.count {
            let swing = abs(nets[i] - nets[i-1])
            if swing > maxSwing { maxSwing = swing; swingIdx = i }
        }
        if maxSwing > 0 {
            let direction = nets[swingIdx] > nets[swingIdx - 1]
            c.append(Candidate(
                section: .turningPoints, icon: "arrow.turn.right.up", title: L("yr_ins_turning_point_title"),
                body: L("yr_ins_turning_point_body", b(md[swingIdx].fullLabel), direction ? g(fc(maxSwing, cur)) : r(fc(maxSwing, cur))),
                accentColor: direction ? .green : .red,
                tags: ["turning", "swing"], significance: min(5, maxSwing / max(1, expenses.reduce(0,+) / Double(md.count)) * 2),
                novelty: 5, confidence: 4, clarity: 4
            ))
        }

        // Clear half split
        if md.count >= 6 {
            let halfN = md.count / 2
            let firstNet = nets.prefix(halfN).reduce(0, +)
            let secondNet = nets.suffix(halfN).reduce(0, +)
            let diff = abs(firstNet - secondNet)
            let total = abs(firstNet) + abs(secondNet)
            if total > 0 && diff / total > 0.3 {
                let lighter = firstNet > secondNet ? L("yr_seasonality_first_half") : L("yr_seasonality_second_half")
                c.append(Candidate(
                    section: .turningPoints, icon: "rectangle.split.2x1.fill", title: L("yr_ins_half_split_title"),
                    body: L("yr_ins_half_split_body", b(lighter)),
                    accentColor: .blue,
                    tags: ["split", "trend"], significance: min(5, diff / max(1, total) * 6), novelty: 4, confidence: 4, clarity: 4
                ))
            }
        }

        // One spike changed picture
        let meanExp = expenses.reduce(0, +) / Double(md.count)
        if let maxIdx = expenses.indices.max(by: { expenses[$0] < expenses[$1] }) {
            let spikeRatio = meanExp > 0 ? expenses[maxIdx] / meanExp : 0
            if spikeRatio > 1.8 {
                c.append(Candidate(
                    section: .turningPoints, icon: "bolt.circle.fill", title: L("yr_ins_one_spike_title"),
                    body: L("yr_ins_one_spike_body", b(md[maxIdx].fullLabel)),
                    accentColor: .red,
                    tags: ["spike", "expense"], significance: min(5, spikeRatio), novelty: 4, confidence: 4, clarity: 5
                ))
            }
        }

        // Quarter reset
        if md.count >= 8 {
            let quarters = quarterAggregates(md)
            for i in 1..<quarters.count {
                let prevNet = quarters[i-1].net
                let curNet = quarters[i].net
                if prevNet < 0 && curNet > 0 && curNet > abs(prevNet) * 0.5 {
                    c.append(Candidate(
                        section: .turningPoints, icon: "arrow.clockwise.circle.fill",
                        title: L("yr_ins_quarter_reset_title"),
                        body: L("yr_ins_quarter_reset_body", b("Q\(i + 1)")),
                        accentColor: .green,
                        tags: ["quarter", "reset"], significance: 4, novelty: 4, confidence: 4, clarity: 4
                    ))
                    break
                }
            }
        }

        // Strongest improvement start
        var bestImprovement = 0.0, bestImpIdx = 0
        for i in 1..<nets.count {
            let improvement = nets[i] - nets[i-1]
            if improvement > bestImprovement { bestImprovement = improvement; bestImpIdx = i }
        }
        if bestImprovement > meanExp * 0.3 {
            c.append(Candidate(
                section: .turningPoints, icon: "sunrise.fill", title: L("yr_ins_improvement_start_title"),
                body: L("yr_ins_improvement_start_body", b(md[bestImpIdx].fullLabel)),
                accentColor: .green,
                tags: ["improvement", "recovery"], significance: min(5, bestImprovement / max(1, meanExp) * 2),
                novelty: 4, confidence: 4, clarity: 4
            ))
        }

        return c
    }
}

// MARK: - 9. Comparison vs Previous Period

private extension YRInsightEngine {

    static func comparisonCandidates(_ ctx: Context) -> [Candidate] {
        guard let prevTxs = ctx.previousPeriodTransactions, !prevTxs.isEmpty else { return [] }
        let md = ctx.monthlyData
        guard md.count >= 2 else { return [] }
        var c: [Candidate] = []
        let cur = ctx.baseCurrency

        let curExp = md.reduce(0) { $0 + $1.expense }
        let curInc = md.reduce(0) { $0 + $1.income }
        let curNet = curInc - curExp
        let curSubExp = md.reduce(0) { $0 + $1.subscriptionExpense }

        let prevExp = prevTxs.filter { $0.type.lowercased() != "income" }.reduce(0.0) { $0 + YearInReviewViewModel.amountInBase($1) }
        let prevInc = prevTxs.filter { $0.type.lowercased() == "income" }.reduce(0.0) { $0 + YearInReviewViewModel.amountInBase($1) }
        let prevNet = prevInc - prevExp
        let prevSubExp = prevTxs.filter { $0.isSubscription == true && $0.type.lowercased() != "income" }.reduce(0.0) { $0 + YearInReviewViewModel.amountInBase($1) }

        // Expense change
        if prevExp > 0 {
            let change = (curExp - prevExp) / prevExp * 100
            c.append(Candidate(
                section: .comparisonVsPrevious, icon: change > 0 ? "arrow.up.circle" : "arrow.down.circle",
                title: L("yr_ins_comp_expense_title"),
                body: L("yr_ins_comp_expense_body", change > 0 ? r(fp(change)) : g(fp(abs(change)))),
                accentColor: change > 0 ? .red : .green,
                tags: ["comparison", "expense"], significance: min(5, abs(change) / 8), novelty: 3, confidence: 4, clarity: 5
            ))
        }

        // Net improvement
        let netChange = curNet - prevNet
        c.append(Candidate(
            section: .comparisonVsPrevious, icon: netChange > 0 ? "arrow.up.right" : "arrow.down.right",
            title: L("yr_ins_comp_net_title"),
            body: L("yr_ins_comp_net_body", fnet(netChange, cur)),
            accentColor: netChange > 0 ? .green : .red,
            tags: ["comparison", "net"], significance: min(5, abs(netChange) / max(1, abs(prevNet)) * 3), novelty: 3, confidence: 4, clarity: 5
        ))

        // Subscription growth
        if prevSubExp > 0 {
            let subChange = (curSubExp - prevSubExp) / prevSubExp * 100
            if abs(subChange) > 5 {
                c.append(Candidate(
                    section: .comparisonVsPrevious, icon: "repeat.circle",
                    title: L("yr_ins_comp_sub_title"),
                    body: L("yr_ins_comp_sub_body", subChange > 0 ? r(fp(subChange)) : g(fp(abs(subChange)))),
                    accentColor: subChange > 0 ? .red : .green,
                    tags: ["comparison", "subscription"], significance: min(5, abs(subChange) / 10), novelty: 4, confidence: 4, clarity: 4
                ))
            }
        }

        // Category concentration change
        var curCatTotal: [String: Double] = [:]
        for tx in ctx.transactions.filter({ $0.type.lowercased() != "income" }) {
            curCatTotal[tx.category, default: 0] += YearInReviewViewModel.amountInBase(tx)
        }
        var prevCatTotal: [String: Double] = [:]
        for tx in prevTxs.filter({ $0.type.lowercased() != "income" }) {
            prevCatTotal[tx.category, default: 0] += YearInReviewViewModel.amountInBase(tx)
        }
        let curTop2 = curCatTotal.sorted { $0.value > $1.value }.prefix(2).reduce(0.0) { $0 + $1.value }
        let prevTop2 = prevCatTotal.sorted { $0.value > $1.value }.prefix(2).reduce(0.0) { $0 + $1.value }
        let curConc = curExp > 0 ? curTop2 / curExp * 100 : 0
        let prevConc = prevExp > 0 ? prevTop2 / prevExp * 100 : 0
        let concChange = curConc - prevConc
        if abs(concChange) > 5 {
            let label = concChange > 0 ? L("yr_comp_more_concentrated") : L("yr_comp_more_diversified")
            c.append(Candidate(
                section: .comparisonVsPrevious, icon: "circle.grid.2x2.fill",
                title: L("yr_ins_comp_concentration_title"),
                body: L("yr_ins_comp_concentration_body", b(label)),
                accentColor: .blue,
                tags: ["comparison", "concentration"], significance: min(5, abs(concChange) / 5), novelty: 4, confidence: 3, clarity: 3
            ))
        }

        // Income stability change
        if prevInc > 0 && curInc > 0 {
            let change = (curInc - prevInc) / prevInc * 100
            c.append(Candidate(
                section: .comparisonVsPrevious, icon: "arrow.up.arrow.down",
                title: L("yr_ins_comp_income_title"),
                body: L("yr_ins_comp_income_body", change > 0 ? g(fp(change)) : r(fp(abs(change)))),
                accentColor: change > 0 ? .green : .red,
                tags: ["comparison", "income"], significance: min(5, abs(change) / 8), novelty: 3, confidence: 4, clarity: 5
            ))
        }

        return c
    }
}

// MARK: - 10. All-Time Perspective

private extension YRInsightEngine {

    static func allTimePerspectiveCandidates(_ ctx: Context) -> [Candidate] {
        let md = ctx.monthlyData
        guard ctx.selectedPeriod == "all", md.count >= 12 else { return [] }
        var c: [Candidate] = []
        let cur = ctx.baseCurrency

        var byYear: [String: (inc: Double, exp: Double, subExp: Double)] = [:]
        for m in md {
            let yr = String(m.monthKey.prefix(4))
            byYear[yr, default: (0, 0, 0)].inc += m.income
            byYear[yr, default: (0, 0, 0)].exp += m.expense
            byYear[yr, default: (0, 0, 0)].subExp += m.subscriptionExpense
        }
        let yearlyData = byYear.sorted { $0.key < $1.key }

        // Strongest year
        if let strongest = yearlyData.max(by: { ($0.value.inc - $0.value.exp) < ($1.value.inc - $1.value.exp) }) {
            let net = strongest.value.inc - strongest.value.exp
            c.append(Candidate(
                section: .allTimePerspective, icon: "medal.fill", title: L("yr_ins_strongest_year_title"),
                body: L("yr_ins_strongest_year_body", b(strongest.key), fnet(net, cur)),
                accentColor: .green,
                tags: ["year", "best"], significance: 4, novelty: 3, confidence: 5, clarity: 5
            ))
        }

        // Most expensive year
        if let expensive = yearlyData.max(by: { $0.value.exp < $1.value.exp }) {
            c.append(Candidate(
                section: .allTimePerspective, icon: "cart.fill", title: L("yr_ins_expensive_year_title"),
                body: L("yr_ins_expensive_year_body", b(expensive.key), r(fc(expensive.value.exp, cur))),
                accentColor: .red,
                tags: ["year", "expensive"], significance: 4, novelty: 3, confidence: 5, clarity: 5
            ))
        }

        // Direction
        if yearlyData.count >= 2 {
            let first = yearlyData.first!, last = yearlyData.last!
            let firstNet = first.value.inc - first.value.exp
            let lastNet = last.value.inc - last.value.exp
            let dir: String
            if lastNet > firstNet && last.value.exp <= first.value.exp * 1.1 { dir = L("yr_dir_efficient") }
            else if last.value.exp > first.value.exp * 1.2 { dir = L("yr_dir_expensive") }
            else { dir = L("yr_dir_stable") }
            c.append(Candidate(
                section: .allTimePerspective, icon: "compass.drawing", title: L("yr_ins_direction_title"),
                body: L("yr_ins_direction_body", b(dir)),
                accentColor: .blue,
                tags: ["direction", "trend"], significance: 4, novelty: 3, confidence: 3, clarity: 5
            ))
        }

        // Subscription share trend
        if yearlyData.count >= 2 {
            let firstSub = yearlyData.first!.value.subExp
            let lastSub = yearlyData.last!.value.subExp
            let firstExp = yearlyData.first!.value.exp
            let lastExp = yearlyData.last!.value.exp
            if firstExp > 0 && lastExp > 0 {
                let firstShare = firstSub / firstExp * 100
                let lastShare = lastSub / lastExp * 100
                if lastShare > firstShare + 3 {
                    c.append(Candidate(
                        section: .allTimePerspective, icon: "chart.line.uptrend.xyaxis",
                        title: L("yr_ins_sub_share_trend_title"),
                        body: L("yr_ins_sub_share_trend_body", b(fp(firstShare)), b(fp(lastShare))),
                        accentColor: .orange,
                        tags: ["subscription", "trend", "year"], significance: 4, novelty: 4, confidence: 4, clarity: 4
                    ))
                }
            }
        }

        // Expense predictability over years
        if yearlyData.count >= 3 {
            let yearlyExps = yearlyData.map(\.value.exp)
            let mean = yearlyExps.reduce(0, +) / Double(yearlyExps.count)
            let cv = mean > 0 ? stdDev(yearlyExps) / mean : 0
            let label = cv < 0.15 ? L("yr_alltime_predictable") : (cv < 0.3 ? L("yr_alltime_moderate") : L("yr_alltime_volatile"))
            c.append(Candidate(
                section: .allTimePerspective, icon: "waveform.path.ecg.rectangle",
                title: L("yr_ins_predictability_title"),
                body: L("yr_ins_predictability_body", b(label)),
                accentColor: cv < 0.2 ? .green : .orange,
                tags: ["predictability", "year"], significance: 3, novelty: 4, confidence: 4, clarity: 4
            ))
        }

        return c
    }
}

// MARK: - Formatting helpers

@MainActor private func fc(_ value: Double, _ currency: String) -> String {
    AppFormatters.formatTotal(amount: value, currency: currency, fractionDigits: 0)
}
@MainActor private func fp(_ value: Double) -> String { String(format: "%.0f%%", value) }
@MainActor private func b(_ text: String) -> String { "**\(text)**" }
@MainActor private func g(_ text: String) -> String { "++\(text)++" }
@MainActor private func r(_ text: String) -> String { "--\(text)--" }
@MainActor private func fnet(_ value: Double, _ currency: String) -> String {
    let formatted = fc(abs(value), currency)
    if value < 0 { return "--\u{2011}\(formatted)--" }
    return "++\(formatted)++"
}

// MARK: - Math helpers

private func stdDev(_ values: [Double]) -> Double {
    guard values.count >= 2 else { return 0 }
    let mean = values.reduce(0, +) / Double(values.count)
    let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
    return sqrt(variance)
}

// MARK: - Quarter aggregation helper

private struct QuarterData {
    let income: Double
    let expense: Double
    let net: Double
    let months: [YRMonthData]
}

private func quarterAggregates(_ md: [YRMonthData]) -> [QuarterData] {
    let qSize = max(1, md.count / 4)
    var quarters: [QuarterData] = []
    for q in 0..<4 {
        let start = q * qSize
        let end = min(start + qSize, md.count)
        guard start < md.count else { break }
        let slice = Array(md[start..<end])
        let inc = slice.reduce(0) { $0 + $1.income }
        let exp = slice.reduce(0) { $0 + $1.expense }
        quarters.append(QuarterData(income: inc, expense: exp, net: inc - exp, months: slice))
    }
    return quarters
}
