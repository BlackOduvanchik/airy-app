//
//  SubscriptionLabView.swift
//  Airy
//
//  Subscription optimization page: Smart Analysis, Optimization Opportunities, insights.
//

import SwiftUI

struct SubscriptionLabView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeProvider.self) private var theme
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
                    savingsCard
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
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
            ToolbarItem(placement: .principal) {
                Text(L("sublab_header"))
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(theme.textTertiary)
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        Text(L("sublab_title"))
            .font(.system(size: 34, weight: .light))
            .tracking(-0.5)
            .lineSpacing(4)
            .foregroundColor(theme.textPrimary)
            .multilineTextAlignment(.center)
    }

    // MARK: - Savings Card

    private var savingsCard: some View {
        VStack(spacing: 4) {
            Text(L("sublab_total_savings"))
                .font(.system(size: 12, weight: .semibold))
                .tracking(1)
                .foregroundColor(theme.textTertiary)
                .padding(.bottom, 8)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(fmtCur(viewModel.totalYearlySavings))
                    .font(.system(size: 48, weight: .semibold))
                    .tracking(-1)
                    .foregroundColor(theme.textPrimary)
                Text("/" + L("sublab_yr"))
                    .font(.system(size: 20))
                    .foregroundColor(theme.textSecondary)
            }

            HStack(spacing: 6) {
                Image(systemName: "dollarsign")
                    .font(.system(size: 12, weight: .bold))
                Text(viewModel.optimizableCount > 0
                     ? L("sublab_ready_optimize")
                     : L("sublab_all_good"))
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundColor(theme.accentGreen)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(theme.accentGreen.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
        .modifier(SubsGlassModifier())
    }

    // MARK: - Optimization Opportunities

    private var optimizationOpportunitiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("sublab_recommendations"))
                .font(.system(size: 12, weight: .semibold))
                .tracking(1)
                .foregroundColor(theme.textTertiary)
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
                    .foregroundColor(theme.textPrimary)
                Text(item.secondaryText)
                    .font(.system(size: 11))
                    .foregroundColor(item.hasSavings ? theme.accentAmber : theme.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 4) {
                Text(formatAmount(sub.amount, sub.currency))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(theme.textPrimary)
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
                return (L("sublab_unused"), LinearGradient(
                    colors: [theme.aiGlow, theme.aiGlow.opacity(0.8)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            case .tierDown:
                return (L("sublab_tier_down"), LinearGradient(
                    colors: [theme.aiGlow, theme.aiGlow.opacity(0.8)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            case .savePercent(let pct):
                return (L("sublab_save_pct", "\(pct)"), LinearGradient(
                    colors: [theme.accentGreen, theme.accentGreen.opacity(0.8)],
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
            .shadow(color: theme.aiGlow.opacity(0.3), radius: 4, x: 0, y: 2)
    }

    // MARK: - Savings pill

    private func savingsPill(yearly: Double) -> some View {
        Text(L("sublab_savings_yr", fmtCur(yearly)))
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(theme.accentGreen)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(theme.accentGreen.opacity(0.12))
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
                            .foregroundColor(theme.aiGlow)
                        Text(text)
                            .font(.system(size: 14))
                            .lineSpacing(4)
                            .foregroundColor(theme.textPrimary)
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
        AppFormatters.currency(code: BaseCurrencyStore.baseCurrency, fractionDigits: 0)
            .string(from: NSNumber(value: value)) ?? "$0"
    }

    private func formatAmount(_ amount: Double, _ currency: String) -> String {
        AppFormatters.currency(code: currency, fractionDigits: 2)
            .string(from: NSNumber(value: amount)) ?? "\(amount) \(currency)"
    }

    private func merchantColor(_ merchant: String) -> Color {
        let m = merchant.lowercased()
        if m.contains("netflix") { return Color(red: 0.898, green: 0.035, blue: 0.078) }
        if m.contains("spotify") { return Color(red: 0.114, green: 0.725, blue: 0.329) }
        if m.contains("chatgpt") || m.contains("openai") { return Color(red: 0, green: 0.651, blue: 0.494) }
        if m.contains("headspace") { return Color(red: 0.98, green: 0.365, blue: 0.365) }
        if m.contains("adobe") { return Color(red: 0.176, green: 0.243, blue: 0.314) }
        if m.contains("nyt") || m.contains("new york") { return Color(red: 0.071, green: 0.071, blue: 0.071) }
        return theme.accentBlue
    }
}

#Preview {
    NavigationStack {
        SubscriptionLabView(subscriptions: [], insights: [])
    }
}
