//
//  YearInReviewModels.swift
//  Airy
//
//  Shared types for Year in Review: chart data, category summaries, insight cards, section definitions.
//

import SwiftUI

// MARK: - Chart mode

enum YRChartMode: String, CaseIterable {
    case all, month
}

// MARK: - Monthly data point

struct YRMonthData: Identifiable {
    let id: String
    let monthKey: String
    let label: String       // Short (chart axis): "Mar"
    let fullLabel: String   // Full (insights): "March"
    let income: Double
    let expense: Double
    let subscriptionExpense: Double
    let subscriptionIncome: Double
    var net: Double { income - expense }
}

// MARK: - Category summary

struct YRCategorySummary: Identifiable {
    let id: String
    let name: String
    let amount: Double
    let share: Double
    let iconName: String
    let color: Color
}

// MARK: - Dynamic sections

enum YRSection: Int, CaseIterable, Identifiable {
    case yearSummary = 0
    case spendingPatterns
    case categoryIntelligence
    case selectedMonth
    case smartInsights
    case incomePatterns
    case subscriptionAnalysis
    case turningPoints
    case comparisonVsPrevious
    case allTimePerspective

    var id: Int { rawValue }

    @MainActor var displayName: String {
        switch self {
        case .yearSummary:          return L("yr_year_summary")
        case .spendingPatterns:     return L("yr_spending_patterns")
        case .categoryIntelligence: return L("yr_category_intel")
        case .selectedMonth:        return L("yr_this_month")
        case .smartInsights:        return L("yr_smart_insights")
        case .incomePatterns:       return L("yr_income_patterns")
        case .subscriptionAnalysis: return L("yr_subscription_analysis")
        case .turningPoints:        return L("yr_turning_points")
        case .comparisonVsPrevious: return L("yr_comparison_prev")
        case .allTimePerspective:   return L("yr_all_time_perspective")
        }
    }

    /// Min...max cards to show per section.
    var cardRange: ClosedRange<Int> {
        switch self {
        case .yearSummary: return 3...5
        default:           return 2...4
        }
    }

    var alwaysOn: Bool {
        switch self {
        case .yearSummary, .categoryIntelligence, .smartInsights: return true
        default: return false
        }
    }
}

// MARK: - Section group (view-facing)

struct YRSectionGroup: Identifiable {
    let id: YRSection
    let section: YRSection
    let cards: [YRInsightCard]

    init(section: YRSection, cards: [YRInsightCard]) {
        self.id = section
        self.section = section
        self.cards = cards
    }
}

// MARK: - Insight card (view-facing)

struct YRInsightCard: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let body: String
    let accentColor: Color
    let section: YRSection
}
