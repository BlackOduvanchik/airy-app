//
//  SubscriptionsView.swift
//  Airy
//
//  Subscriptions tab: summary, next up strip, active list, insights, donut chart.
//

import SwiftUI

struct SubscriptionsView: View {
    @State private var viewModel = SubscriptionsViewModel()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                OnboardingGradientBackground()

                ScrollView {
                    VStack(spacing: 20) {
                        headerSection
                        summaryCardSection
                        nextUpSection
                        activeSubscriptionsSection
                        recurringInsightsSection
                        donutChartSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 120)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Subscriptions")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $viewModel.showPaywall) {
                PaywallView()
            }
            .task { await viewModel.load() }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("SUBSCRIPTIONS")
                .font(.system(size: 12, weight: .semibold))
                .tracking(1)
                .foregroundColor(OnboardingDesign.textTertiary)
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.9), Color.white.opacity(0.2)],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 30
                        )
                    )
                    .frame(width: 48, height: 48)
                Image(systemName: "cloud.fill")
                    .font(.system(size: 24))
                    .foregroundColor(OnboardingDesign.textPrimary)
            }
            .padding(.bottom, 8)
            Text("What You Pay For")
                .font(.system(size: 34, weight: .light))
                .tracking(-0.5)
                .lineSpacing(4)
                .foregroundColor(OnboardingDesign.textPrimary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 20)
        .padding(.bottom, 2)
    }

    // MARK: - Summary card

    private var summaryCardSection: some View {
        Group {
            if viewModel.isLoading && viewModel.subscriptions.isEmpty {
                subsGlassPanel {
                    ProgressView()
                        .padding(.vertical, 24)
                }
            } else {
                subsGlassPanel {
                    VStack(spacing: 8) {
                        (Text(formatCurrencyWhole(viewModel.totalMonthly))
                            .font(.system(size: 32, weight: .medium))
                            .foregroundColor(OnboardingDesign.textPrimary)
                        + Text("/mo")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(OnboardingDesign.textSecondary))
                        deltaChip(text: "+$12 vs last month")
                        Text("\(viewModel.subscriptions.count) active subscriptions")
                            .font(.system(size: 14))
                            .foregroundColor(OnboardingDesign.textTertiary)
                    }
                    .padding(.vertical, 16)
                }
            }
        }
    }

    private func deltaChip(text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "chevron.up")
                .font(.system(size: 12, weight: .bold))
            Text(text)
                .font(.system(size: 12, weight: .bold))
        }
        .foregroundColor(OnboardingDesign.accentAmber)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Next Up (horizontal scroll)

    private var nextUpSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NEXT UP")
                .font(.system(size: 12, weight: .semibold))
                .tracking(1)
                .foregroundColor(OnboardingDesign.textTertiary)
                .padding(.leading, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.nextUpSubscriptions.prefix(5)) { sub in
                        nextUpCard(subscription: sub)
                    }
                    if viewModel.nextUpSubscriptions.isEmpty && !viewModel.subscriptions.isEmpty {
                        Text("No upcoming dates")
                            .font(.system(size: 13))
                            .foregroundColor(OnboardingDesign.textTertiary)
                            .frame(minWidth: 140)
                            .padding(16)
                            .modifier(SubsGlassModifier())
                    }
                }
                .padding(.vertical, 4)
                .padding(.bottom, 12)
            }
        }
    }

    private func nextUpCard(subscription: Subscription) -> some View {
        let days = daysUntil(subscription.nextBillingDate)
        let urgent = days != nil && (days ?? 99) < 7
        return VStack(alignment: .leading, spacing: 12) {
            Circle()
                .fill(merchantColor(subscription.merchant))
                .frame(width: 32, height: 32)
                .overlay(
                    Text(String(subscription.merchant.prefix(1)).uppercased())
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(subscription.merchant)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(OnboardingDesign.textPrimary)
                    .lineLimit(1)
                Text(formatAmount(subscription.amount, subscription.currency))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(OnboardingDesign.textPrimary)
            }
            if let d = days {
                Text(d == 0 ? "Today" : d == 1 ? "Tomorrow" : "\(d) days")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(urgent ? OnboardingDesign.accentAmber : OnboardingDesign.accentGreen)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background((urgent ? OnboardingDesign.accentAmber : OnboardingDesign.accentGreen).opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(minWidth: 140)
        .padding(16)
        .modifier(SubsGlassModifier())
    }

    // MARK: - Active subscriptions list

    private var activeSubscriptionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ACTIVE SUBSCRIPTIONS")
                .font(.system(size: 12, weight: .semibold))
                .tracking(1)
                .foregroundColor(OnboardingDesign.textTertiary)
                .padding(.leading, 4)
            if viewModel.subscriptions.isEmpty && !viewModel.isLoading {
                subsGlassPanel {
                    Text("No subscriptions yet")
                        .font(.system(size: 14))
                        .foregroundColor(OnboardingDesign.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(24)
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(viewModel.subscriptions) { sub in
                        subRow(subscription: sub)
                    }
                }
            }
        }
    }

    private func subRow(subscription: Subscription) -> some View {
        let isTrial = subscription.status.lowercased().contains("trial")
        return HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 12)
                .fill(merchantColor(subscription.merchant))
                .frame(width: 40, height: 40)
                .overlay(
                    Text(String(subscription.merchant.prefix(1)).uppercased())
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                )
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(subscription.merchant)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(OnboardingDesign.textPrimary)
                    if isTrial {
                        Text("TRIAL")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(OnboardingDesign.accentAmber)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                Text("\(subscription.interval) · \(formatNextBillingShort(subscription.nextBillingDate))")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isTrial ? OnboardingDesign.accentAmber : OnboardingDesign.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(formatAmount(subscription.amount, subscription.currency))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(OnboardingDesign.textPrimary)
        }
        .padding(16)
        .modifier(SubsGlassModifier())
        .overlay(alignment: .leading) {
            if isTrial {
                RoundedRectangle(cornerRadius: 28)
                    .fill(OnboardingDesign.accentAmber)
                    .frame(width: 4)
                    .padding(.vertical, 16)
            }
        }
    }

    // MARK: - Recurring insights

    private var recurringInsightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RECURRING INSIGHTS")
                .font(.system(size: 12, weight: .semibold))
                .tracking(1)
                .foregroundColor(OnboardingDesign.textTertiary)
                .padding(.leading, 4)
            VStack(spacing: 12) {
                insightCard("You have 3 subscriptions you haven't used in 30+ days.")
                insightCard("Annual plans could save you $94/year on 2 services.")
            }
        }
    }

    private func insightCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 18))
                .foregroundColor(OnboardingDesign.accentBlue)
            Text(text)
                .font(.system(size: 14))
                .lineSpacing(4)
                .foregroundColor(OnboardingDesign.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .modifier(SubsGlassModifier())
    }

    // MARK: - Donut chart

    private var donutChartSection: some View {
        HStack(alignment: .center, spacing: 24) {
            donutChartView
                .frame(width: 80, height: 80)
            VStack(alignment: .leading, spacing: 4) {
                legendRow(color: OnboardingDesign.accentBlue, label: "Entertainment")
                legendRow(color: OnboardingDesign.accentGreen, label: "Productivity")
                legendRow(color: OnboardingDesign.accentAmber, label: "Health")
                legendRow(color: OnboardingDesign.bgTop, label: "News")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
        .modifier(SubsGlassModifier())
    }

    private var donutChartView: some View {
        ZStack {
            ForEach(Array(donutSegments.enumerated()), id: \.offset) { index, seg in
                Circle()
                    .trim(from: seg.start, to: seg.end)
                    .stroke(seg.color, style: StrokeStyle(lineWidth: 3, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(2)
    }

    private var donutSegments: [(start: CGFloat, end: CGFloat, color: Color)] {
        let total: CGFloat = 100
        let a: CGFloat = 40 / total
        let b: CGFloat = 30 / total
        let c: CGFloat = 20 / total
        let d: CGFloat = 10 / total
        return [
            (0, a, OnboardingDesign.accentBlue),
            (a, a + b, OnboardingDesign.accentGreen),
            (a + b, a + b + c, OnboardingDesign.accentAmber),
            (a + b + c, 1, OnboardingDesign.bgTop)
        ]
    }

    private func legendRow(color: Color, label: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(OnboardingDesign.textSecondary)
        }
    }

    // MARK: - Helpers

    private func subsGlassPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .modifier(SubsGlassModifier())
    }

    private func formatCurrencyWhole(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }

    private func formatAmount(_ amount: Double, _ currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount) \(currency)"
    }

    private func formatNextBillingShort(_ dateStr: String?) -> String {
        guard let s = dateStr, !s.isEmpty else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        guard let d = f.date(from: String(s.prefix(10))) else { return s }
        let out = DateFormatter()
        out.dateFormat = "MMM d"
        return out.string(from: d)
    }

    private func daysUntil(_ dateStr: String?) -> Int? {
        guard let s = dateStr, !s.isEmpty else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        guard let d = f.date(from: String(s.prefix(10))) else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: d).day
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

// MARK: - Glass modifier

private struct SubsGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .overlay(OnboardingDesign.glassBg.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .stroke(OnboardingDesign.glassBorder, lineWidth: 1)
            )
            .shadow(color: OnboardingDesign.textPrimary.opacity(0.06), radius: 16, x: 0, y: 8)
    }
}

#Preview {
    SubscriptionsView()
}
