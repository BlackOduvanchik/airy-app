//
//  InsightsViewModel.swift
//  Airy
//

import SwiftUI

@Observable
final class InsightsViewModel {
    var summary = ""
    var insights: [InsightItem] = []
    var isLoading = true
    var showPaywall = false
    var errorMessage: String?

    /// For comparison tiles (this month vs last month).
    var thisMonthSpent: Double = 0
    var lastMonthSpent: Double = 0
    var deltaPercent: Double = 0

    func load() async {
        isLoading = true
        defer { Task { @MainActor in isLoading = false } }
        do {
            async let summaryTask = APIClient.shared.getMonthlySummary(month: nil)
            async let insightsTask = APIClient.shared.getBehavioralInsights()
            async let dashboardTask = APIClient.shared.getDashboard()

            let s = try await summaryTask
            await MainActor.run {
                summary = s.summary
                deltaPercent = s.deltaPercent
            }

            let i = try await insightsTask
            await MainActor.run { insights = i }

            do {
                let d = try await dashboardTask
                await MainActor.run {
                    thisMonthSpent = d.thisMonth.totalSpent
                    lastMonthSpent = d.previousMonthSpent
                    if deltaPercent == 0 { deltaPercent = d.deltaPercent }
                }
            } catch {
                // Dashboard optional; summary/insights already applied
            }
        } catch APIError.paymentRequired {
            let entitlements = try? await APIClient.shared.getEntitlements()
            await MainActor.run {
                if entitlements?.unlimitedAiAnalysis != true { showPaywall = true }
            }
        } catch {
            await MainActor.run { summary = ""; insights = []; errorMessage = error.localizedDescription }
        }
    }
}
