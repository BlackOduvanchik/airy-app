//
//  SubscriptionLabView.swift
//  Airy
//
//  Subscription optimization page: Smart Analysis, Optimization Opportunities, insights.
//

import SwiftUI

struct SubscriptionLabView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: SubscriptionLabViewModel

    init(subscriptions: [Subscription], insights: [SubscriptionInsight]) {
        self._viewModel = State(initialValue: SubscriptionLabViewModel(
            subscriptions: subscriptions, insights: insights
        ))
    }

    var body: some View {
        ZStack(alignment: .top) {
            OnboardingGradientBackground()

            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    smartAnalysisSection
                    optimizationOpportunitiesSection
                    bottomInsightsSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            ToolbarItem(placement: .principal) {
                Text("OPTIMIZATION ENGINE")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(OnboardingDesign.textTertiary)
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        Text("Subscription Lab")
            .font(.system(size: 34, weight: .light))
            .tracking(-0.5)
            .lineSpacing(4)
            .foregroundColor(OnboardingDesign.textPrimary)
            .multilineTextAlignment(.center)
    }

    // MARK: - Smart Analysis

    private var smartAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SMART ANALYSIS")
                .font(.system(size: 12, weight: .semibold))
                .tracking(1)
                .foregroundColor(OnboardingDesign.textTertiary)
                .padding(.leading, 4)

            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(OnboardingDesign.aiGlow.opacity(0.15))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "sparkles")
                                .font(.system(size: 16))
                                .foregroundColor(OnboardingDesign.aiGlow)
                        )
                    Text(viewModel.aiSummaryText)
                        .font(.system(size: 14, weight: .medium))
                        .lineSpacing(4)
                        .foregroundColor(OnboardingDesign.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if viewModel.totalYearlySavings > 0 {
                    Rectangle()
                        .fill(OnboardingDesign.glassBorder)
                        .frame(height: 1)

                    HStack {
                        Text("Yearly Total Potential Savings")
                            .font(.system(size: 12))
                            .foregroundColor(OnboardingDesign.textSecondary)
                        Spacer()
                        Text(fmtCur(viewModel.totalYearlySavings))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(OnboardingDesign.accentGreen)
                    }
                }
            }
            .padding(20)
            .modifier(SubsGlassModifier())
        }
    }

    // MARK: - Optimization Opportunities

    private var optimizationOpportunitiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OPTIMIZATION OPPORTUNITIES")
                .font(.system(size: 12, weight: .semibold))
                .tracking(1)
                .foregroundColor(OnboardingDesign.textTertiary)
                .padding(.leading, 4)

            VStack(spacing: 8) {
                ForEach(viewModel.optimizableItems) { item in
                    opportunityRow(item: item)
                }
            }
        }
    }

    private func opportunityRow(item: LabSubscriptionItem) -> some View {
        let sub = item.subscription
        let subColor = sub.colorHex.flatMap { Color(hex: $0) } ?? merchantColor(sub.merchant)
        let subIcon = sub.iconLetter ?? String(sub.merchant.prefix(1)).uppercased()
        let isSFSymbol = subIcon.count > 1

        return HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 14)
                .fill(subColor)
                .frame(width: 44, height: 44)
                .overlay(
                    Group {
                        if isSFSymbol {
                            Image(systemName: subIcon)
                                .font(.system(size: 18, weight: .bold))
                        } else {
                            Text(subIcon)
                                .font(.system(size: 18, weight: .bold))
                        }
                    }
                    .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(sub.merchant)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(OnboardingDesign.textPrimary)
                Text(item.secondaryText)
                    .font(.system(size: 11))
                    .foregroundColor(item.hasSavings ? OnboardingDesign.accentAmber : OnboardingDesign.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 4) {
                Text(formatAmount(sub.amount, sub.currency))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(OnboardingDesign.textPrimary)
                if item.hasSavings {
                    savingsPill(yearly: item.yearlySavings)
                }
            }
        }
        .padding(16)
        .modifier(SubsGlassModifier())
        .overlay(alignment: .topTrailing) {
            if let badge = item.badgeType {
                badgeView(badge)
                    .offset(x: -12, y: -6)
            }
        }
    }

    // MARK: - Badge

    private func badgeView(_ badge: LabBadgeType) -> some View {
        let (text, gradient): (String, LinearGradient) = {
            switch badge {
            case .unused:
                return ("Unused", LinearGradient(
                    colors: [OnboardingDesign.aiGlow, OnboardingDesign.aiGlow.opacity(0.8)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            case .tierDown:
                return ("Tier Down", LinearGradient(
                    colors: [OnboardingDesign.aiGlow, OnboardingDesign.aiGlow.opacity(0.8)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            case .savePercent(let pct):
                return ("Save \(pct)%", LinearGradient(
                    colors: [OnboardingDesign.accentGreen, OnboardingDesign.accentGreen.opacity(0.8)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            }
        }()

        return Text(text)
            .font(.system(size: 9, weight: .heavy))
            .textCase(.uppercase)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(gradient)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.4), lineWidth: 1)
            )
            .shadow(color: OnboardingDesign.aiGlow.opacity(0.3), radius: 4, x: 0, y: 2)
    }

    // MARK: - Savings pill

    private func savingsPill(yearly: Double) -> some View {
        Text("-\(fmtCur(yearly))/yr")
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(OnboardingDesign.accentGreen)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(OnboardingDesign.accentGreen.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Bottom Insights

    @ViewBuilder
    private var bottomInsightsSection: some View {
        if !viewModel.bottomInsights.isEmpty {
            VStack(spacing: 12) {
                ForEach(Array(viewModel.bottomInsights.enumerated()), id: \.offset) { _, text in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 18))
                            .foregroundColor(OnboardingDesign.aiGlow)
                        Text(text)
                            .font(.system(size: 14))
                            .lineSpacing(4)
                            .foregroundColor(OnboardingDesign.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .modifier(SubsGlassModifier())
                }
            }
        }
    }

    // MARK: - Helpers

    private func fmtCur(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = BaseCurrencyStore.baseCurrency
        f.maximumFractionDigits = 0
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$0"
    }

    private func formatAmount(_ amount: Double, _ currency: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: amount)) ?? "\(amount) \(currency)"
    }

    private func merchantColor(_ merchant: String) -> Color {
        let m = merchant.lowercased()
        if m.contains("netflix") { return Color(red: 0.898, green: 0.035, blue: 0.078) }
        if m.contains("spotify") { return Color(red: 0.114, green: 0.725, blue: 0.329) }
        if m.contains("chatgpt") || m.contains("openai") { return Color(red: 0, green: 0.651, blue: 0.494) }
        if m.contains("headspace") { return Color(red: 0.98, green: 0.365, blue: 0.365) }
        if m.contains("adobe") { return Color(red: 0.176, green: 0.243, blue: 0.314) }
        if m.contains("nyt") || m.contains("new york") { return Color(red: 0.071, green: 0.071, blue: 0.071) }
        return OnboardingDesign.accentBlue
    }
}

#Preview {
    NavigationStack {
        SubscriptionLabView(subscriptions: [], insights: [])
    }
}
