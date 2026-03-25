//
//  SpendingInsightModels.swift
//  Airy
//
//  Data models for the local spending insights engine.
//  All values are in the user's base currency.
//

import Foundation

struct CategoryTxCount: Sendable {
    let thisMonth: Int
    let avg3Month: Double
}

struct MonthlySubTotal: Sendable {
    let monthKey: String
    let total: Double
}

struct SpendingSnapshot: Sendable {
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

    // MARK: - Pace

    let last3MonthAvgSpend: Double
    let spendPaceRatio: Double          // thisMonthSpent / expectedByToday
    let firstHalfSpend: Double          // first 7 days
    let secondHalfSpend: Double         // last 7 days

    // MARK: - Concentration

    let topCategoryShare: Double
    let topCategoryName: String?
    let top2CategoriesShare: Double
    let topMerchantShareTotal: Double
    let topMerchantNameTotal: String?
    let topMerchantShareInCategory: [String: MerchantConcentration]

    // MARK: - Frequency

    let txCountThisMonth: Int
    let txCountLast3MonthAvg: Double
    let topFrequentMerchant: String?
    let topFrequentMerchantCount: Int
    let categoryTxCounts: [String: CategoryTxCount]

    // MARK: - Ticket size

    let smallTxShare: Double
    let smallTxCount: Int
    let avgTicketThisMonth: Double
    let avgTicketLast3Month: Double
    let medianTicketThisMonth: Double
    let medianTicketLast3Month: Double

    // MARK: - Subscriptions extended

    let committedToIncomeRatio: Double
    let upcomingBillsNext7Days: Double
    let subscriptionMonthlyTotal: Double
    let recurringCostDeltaPercent: Double

    // MARK: - Risk / anomaly

    let anomalyCount: Int
    let newMerchantCount: Int
    let repeatedMerchantStreak: MerchantStreak?
    let safeToSpendRaw: Double          // can be negative (for risk templates)
    let avgWeeklySpend8Weeks: Double

    // MARK: - Positive

    let lastMonthSavings: Double

    // MARK: - Calendar

    let dayOfMonth: Int
    let daysInMonth: Int

    // MARK: - Daily cumulative spend (for trend chart)

    let dailyCumulativeThisMonth: [Double]   // cumulative spend day 1...dayOfMonth
    let dailyCumulativeLastMonth: [Double]   // cumulative spend day 1...daysInLastMonth
}

struct MerchantConcentration: Sendable {
    let merchant: String
    let share: Double
}

struct MerchantStreak: Sendable {
    let merchant: String
    let days: Int
}

struct InsightCandidate: Sendable {
    let priority: Double
    let text: String
    let tag: String
}

struct CategoryDelta: Identifiable, Sendable {
    let id: String
    let name: String
    let emoji: String
    let thisMonth: Double
    let lastMonth: Double
    let deltaPercent: Double
}

struct MerchantStat: Sendable {
    let merchant: String
    let totalSpent: Double
}

struct MerchantAnomaly: Identifiable, Sendable {
    let id: String
    let merchant: String
    let category: String
    let categoryName: String
    let currentSpent: Double
    let averageSpent: Double
    let ratio: Double
}

struct MonthlySpendPoint: Identifiable, Sendable {
    let id: String
    let monthKey: String
    let shortLabel: String
    let total: Double
    let isCurrent: Bool
}

struct SubscriptionTrendData: Sendable {
    let monthlyTotals: [MonthlySubTotal]
    let deltaAmount: Double
    let newSubsCount: Int
}
