//
//  Endpoints.swift
//  Airy
//

import Foundation

enum Endpoints {
    /// API base URL: from environment variable (dev override), then Info.plist AIRY_API_BASE_URL, then Debug localhost. Release requires plist key.
    static let baseURL: URL = {
        if let env = ProcessInfo.processInfo.environment["AIRY_API_BASE_URL"], let url = URL(string: env), !env.isEmpty {
            return url
        }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "AIRY_API_BASE_URL") as? String, !plist.isEmpty, let url = URL(string: plist) {
            return url
        }
        #if DEBUG
        return URL(string: "http://localhost:3000")!
        #else
        fatalError("AIRY_API_BASE_URL must be set in Info.plist for release builds. Add key AIRY_API_BASE_URL with your production API URL (e.g. https://api.yourapp.com).")
        #endif
    }()

    static let authRegister = "/api/auth/register-or-login"
    static let authApple = "/api/auth/apple"
    static let parseScreenshot = "/api/transactions/parse-screenshot"
    static let transactionsPending = "/api/transactions/pending"
    static let transactions = "/api/transactions"
    static let analyticsDashboard = "/api/analytics/dashboard"
    static let analyticsMonthly = "/api/analytics/monthly"
    static let analyticsYearly = "/api/analytics/yearly"
    static let insightsMonthlySummary = "/api/insights/monthly-summary"
    static let insightsBehavioral = "/api/insights/behavioral"
    static let insightsMoneyMirror = "/api/insights/money-mirror"
    static let insightsYearlyReview = "/api/insights/yearly-review"
    static let subscriptions = "/api/subscriptions"
    static let entitlements = "/api/entitlements"
    static let exportCsv = "/api/export/csv"
    static let exportJson = "/api/export/json"
    static let merchantRules = "/api/merchant-rules"
    static let billingSync = "/api/billing/sync"
}
