//
//  DashboardViewModel.swift
//  Airy
//
//  Local-only: aggregate from SwiftData.
//

import SwiftUI

@Observable
final class DashboardViewModel {
    var thisMonth: MonthSummary?
    var previousMonthSpent: Double = 0
    var deltaPercent: Double = 0
    var isLoading = true
    var errorMessage: String?

    var recentTransactions: [Transaction] = []
    var upcomingSubscriptions: [Subscription] = []
    var aiSummaryLine: String?

    func load() async {
        isLoading = true
        defer { Task { @MainActor in isLoading = false } }
        await MainActor.run {
            LocalDataStore.shared.processDueSubscriptions()
            let (this, prev, delta) = LocalDataStore.shared.dashboardSummary()
            thisMonth = this
            previousMonthSpent = prev
            deltaPercent = delta
            recentTransactions = LocalDataStore.shared.fetchTransactions(limit: 5)
            // #region agent log
            do {
                let payload: [String: Any] = [
                    "sessionId": "ad783c",
                    "location": "DashboardViewModel.load",
                    "message": "recentTransactions after fetch",
                    "data": ["count": recentTransactions.count],
                    "timestamp": Int(Date().timeIntervalSince1970 * 1000),
                    "hypothesisId": "H1"
                ]
                if let json = try? JSONSerialization.data(withJSONObject: payload),
                   let line = String(data: json, encoding: .utf8) {
                    let path = "/Users/oduvanchik/Desktop/Airy/.cursor/debug-ad783c.log"
                    let lineData = (line + "\n").data(using: .utf8)!
                    if FileManager.default.fileExists(atPath: path) {
                        if let h = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
                            defer { try? h.close() }
                            h.seekToEndOfFile()
                            h.write(lineData)
                        }
                    } else {
                        FileManager.default.createFile(atPath: path, contents: lineData, attributes: nil)
                    }
                }
            }
            // #endregion
            let subs = LocalDataStore.shared.subscriptionsFromTransactions()
            upcomingSubscriptions = subs
                .filter { $0.nextBillingDate != nil && !($0.nextBillingDate?.isEmpty ?? true) }
                .sorted { (a, b) in
                    guard let da = a.nextBillingDate, let db = b.nextBillingDate else { return false }
                    return da.compare(db) == .orderedAscending
                }
                .prefix(5)
                .map { $0 }
            if delta < 0 {
                let absPct = abs(Int(delta.rounded()))
                aiSummaryLine = "Spending is down \(absPct)% vs last month. Keep it up."
            } else if delta > 0 {
                aiSummaryLine = "Spending is up \(Int(delta.rounded()))% vs last month. Review your habits."
            } else {
                aiSummaryLine = "Your spending is in line with last month."
            }
        }
    }
}
