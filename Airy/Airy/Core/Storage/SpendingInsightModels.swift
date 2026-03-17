//
//  SpendingInsightModels.swift
//  Airy
//
//  Data models for the local spending insights engine.
//  All values are in the user's base currency.
//

import Foundation

struct SpendingSnapshot {
    let thisMonthSpent: Double
    let lastMonthSpent: Double
    let monthDeltaPercent: Double

    let thisWeekSpent: Double
    let lastWeekSpent: Double
    let weekDeltaPercent: Double

    let thisMonthIncome: Double

    let categoryDeltas: [CategoryDelta]

    let dailyAverageThisMonth: Double
    let projectedMonthlySpend: Double
    let projectedMonthlySavings: Double

    let safeToSpend: Double

    let topMerchantByCategory: [String: MerchantStat]
    let merchantAnomalies: [MerchantAnomaly]

    let weekdayAvgSpend: Double
    let weekendAvgSpend: Double

    let monthlyHistory: [MonthlySpendPoint]
    let subscriptionTrend: SubscriptionTrendData

    let totalTransactionCount: Int
    let computedAt: Date
}

struct CategoryDelta: Identifiable {
    let id: String
    let name: String
    let emoji: String
    let thisMonth: Double
    let lastMonth: Double
    let deltaPercent: Double
}

struct MerchantStat {
    let merchant: String
    let totalSpent: Double
}

struct MerchantAnomaly: Identifiable {
    let id: String
    let merchant: String
    let category: String
    let categoryName: String
    let currentSpent: Double
    let averageSpent: Double
    let ratio: Double
}

struct MonthlySpendPoint: Identifiable {
    let id: String
    let monthKey: String
    let shortLabel: String
    let total: Double
    let isCurrent: Bool
}

struct SubscriptionTrendData {
    let monthlyTotals: [(monthKey: String, total: Double)]
    let deltaAmount: Double
    let newTrialsCount: Int
}
