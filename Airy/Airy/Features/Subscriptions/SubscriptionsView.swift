//
//  SubscriptionsView.swift
//  Airy
//
//  Subscriptions tab: summary with donut, insights, active list with progress rings.
//

import SwiftUI

struct SubscriptionsView: View {
    var onDismiss: (() -> Void)? = nil
    @State private var viewModel = SubscriptionsViewModel()
    @State private var selectedSubscription: Subscription?
    @State private var showSubscriptionLab = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                OnboardingGradientBackground()

                ScrollView {
                    VStack(spacing: 20) {
                        headerSection
                        summaryCardSection
                        recurringInsightsSection
                        activeSubscriptionsSection
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
                if onDismiss != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { onDismiss?() } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("SUBSCRIPTIONS")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(OnboardingDesign.textTertiary)
                }
            }
            .sheet(isPresented: $viewModel.showPaywall) {
                PaywallView()
            }
            .sheet(item: $selectedSubscription) { sub in
                EditSubscriptionView(
                    subscription: sub,
                    onSave: { Task { await viewModel.load() } },
                    onCancel: { Task { await viewModel.load() } }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
            }
            .navigationDestination(isPresented: $showSubscriptionLab) {
                SubscriptionLabView(
                    subscriptions: viewModel.subscriptions,
                    insights: SubscriptionInsightStore.shared.loadAll()
                )
            }
            .task { await viewModel.load() }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        Text("What You Pay For")
            .font(.system(size: 34, weight: .light))
            .tracking(-0.5)
            .lineSpacing(4)
            .foregroundColor(OnboardingDesign.textPrimary)
            .multilineTextAlignment(.center)
    }

    // MARK: - Summary card (with embedded donut + category legend)

    private var summaryCardSection: some View {
        Group {
            if viewModel.isLoading && viewModel.subscriptions.isEmpty {
                subsGlassPanel {
                    ProgressView()
                        .padding(.vertical, 24)
                }
            } else {
                subsGlassPanel {
                    VStack(spacing: 14) {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                HStack(alignment: .firstTextBaseline, spacing: 2) {
                                    Text(formatCurrencyWhole(viewModel.totalMonthly))
                                        .font(.system(size: 32, weight: .medium))
                                        .foregroundColor(OnboardingDesign.textPrimary)
                                    Text("/mo")
                                        .font(.system(size: 16, weight: .regular))
                                        .foregroundColor(OnboardingDesign.textSecondary)
                                }
                                deltaChip(text: "+$12 vs last month")
                            }
                            Spacer()
                            donutChartView
                                .frame(width: 64, height: 64)
                            Spacer()
                        }
                        if !subscriptionChartSegments.isEmpty {
                            Rectangle()
                                .fill(OnboardingDesign.glassBorder)
                                .frame(height: 1)
                            HStack(spacing: 10) {
                                ForEach(subscriptionChartSegments.prefix(2)) { seg in
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(seg.color)
                                            .frame(width: 6, height: 6)
                                        Text("\(seg.label) \(Int(round(seg.percent * 100)))%")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(OnboardingDesign.textSecondary)
                                            .lineLimit(1)
                                    }
                                }
                                Text("\u{00B7}")
                                    .foregroundColor(OnboardingDesign.textTertiary)
                                Text("\(viewModel.subscriptionSharePercent)% of spending")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(OnboardingDesign.textPrimary)
                            }
                        }
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 4)
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

    // MARK: - Active subscriptions list (sorted by billing date)

    private var activeSubscriptionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SUBSCRIPTION DETAILS")
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
                    ForEach(viewModel.nextUpSubscriptions) { sub in
                        Button { selectedSubscription = sub } label: {
                            subRow(subscription: sub)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func subRow(subscription: Subscription) -> some View {
        let isTrial = subscription.status.lowercased().contains("trial")
        let subColor = subscription.colorHex.flatMap { Color(hex: $0) } ?? merchantColor(subscription.merchant)
        let subIcon = subscription.iconLetter ?? String(subscription.merchant.prefix(1)).uppercased()
        let isSFSymbol = subIcon.count > 1
        return HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 12)
                .fill(subColor)
                .frame(width: 40, height: 40)
                .overlay(
                    Group {
                        if isSFSymbol {
                            Image(systemName: subIcon)
                                .font(.system(size: 18, weight: .bold))
                        } else {
                            Text(subIcon)
                                .font(.system(size: 16, weight: .bold))
                        }
                    }
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
                Text("\(subscription.interval) \u{00B7} \(formatNextBillingShort(subscription.nextBillingDate))")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isTrial ? OnboardingDesign.accentAmber : OnboardingDesign.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(formatAmount(subscription.amount, subscription.currency))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(OnboardingDesign.textPrimary)
            billingProgressRing(for: subscription)
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

    // MARK: - Billing progress ring

    private func billingProgressRing(for subscription: Subscription) -> some View {
        let cycleDays: Double = {
            let interval = subscription.interval.lowercased()
            if interval.hasPrefix("year") || interval.hasPrefix("annual") { return 365 }
            if interval.hasPrefix("week") { return 7 }
            return 30
        }()
        let daysLeft = max(Double(daysUntil(subscription.nextBillingDate) ?? 0), 0)
        let progress = min((cycleDays - daysLeft) / cycleDays, 1)
        let remainingRatio = daysLeft / cycleDays
        let ringColor: Color = remainingRatio > 0.5 ? OnboardingDesign.accentGreen
            : remainingRatio > 0.25 ? OnboardingDesign.accentAmber
            : OnboardingDesign.textDanger

        return ZStack {
            Circle()
                .stroke(ringColor.opacity(0.15), lineWidth: 3)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 24, height: 24)
    }

    // MARK: - Recurring insights

    private var recurringInsightsSection: some View {
        let insights = SubscriptionInsightStore.shared.loadAll()
            .filter { $0.monthlySavingsPotential > 0 }
            .sorted { $0.monthlySavingsPotential > $1.monthlySavingsPotential }
        let hasSavings = !insights.isEmpty

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RECURRING INSIGHTS")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1)
                    .foregroundColor(OnboardingDesign.textTertiary)
                    .padding(.leading, 4)
                Spacer()
                if hasSavings {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(OnboardingDesign.textTertiary)
                }
            }

            Button { showSubscriptionLab = true } label: {
                VStack(spacing: 12) {
                    if hasSavings {
                        let totalYearlySavings = Int(insights.reduce(0) { $0 + $1.monthlySavingsPotential } * 12)
                        insightCard("You could save ~$\(totalYearlySavings)/year on \(insights.count) service\(insights.count == 1 ? "" : "s").")
                        ForEach(insights.prefix(2)) { insight in
                            insightCard(insight.tip)
                        }
                    } else if SubscriptionAnalysisService.shared.isAnalyzing {
                        HStack(spacing: 12) {
                            ProgressView()
                                .tint(OnboardingDesign.accentBlue)
                            Text("Analyzing your subscriptions...")
                                .font(.system(size: 14))
                                .foregroundColor(OnboardingDesign.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .modifier(SubsGlassModifier())
                    } else {
                        insightCard("We'll analyze your subscriptions for savings opportunities.")
                    }
                }
                .padding(hasSavings ? 16 : 0)
                .background(
                    hasSavings
                        ? RoundedRectangle(cornerRadius: 28)
                            .fill(OnboardingDesign.accentGreen.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 28)
                                    .stroke(OnboardingDesign.accentGreen.opacity(0.3), lineWidth: 1.5)
                            )
                        : nil
                )
            }
            .buttonStyle(.plain)
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
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .modifier(SubsGlassModifier())
    }

    // MARK: - Donut chart (real data from subscriptions by category)

    private struct SubsChartSegment: Identifiable {
        let id: String
        let start: CGFloat
        let end: CGFloat
        let color: Color
        let label: String
        let percent: Double
    }

    private var subscriptionChartSegments: [SubsChartSegment] {
        let base = BaseCurrencyStore.baseCurrency
        var byCat: [String: Double] = [:]
        for sub in viewModel.subscriptions {
            let monthly: Double
            let interval = sub.interval.lowercased()
            if interval.hasPrefix("year") || interval.hasPrefix("annual") {
                monthly = sub.amount / 12
            } else if interval.hasPrefix("week") {
                monthly = sub.amount * (52.0 / 12.0)
            } else {
                monthly = sub.amount
            }
            let inBase = CurrencyService.convert(amount: monthly, from: sub.currency, to: base)
            let catId = sub.categoryId ?? "other"
            byCat[catId, default: 0] += inBase
        }
        let total = byCat.values.reduce(0, +)
        guard total > 0 else { return [] }
        let sorted = byCat.sorted { $0.value > $1.value }
        let n = sorted.count
        let fillRatio: Double = {
            switch n {
            case 1: return 1.0
            case 2: return 0.90
            case 3: return 0.88
            case 4: return 0.78
            case 5: return 0.70
            default: return 0.60
            }
        }()
        let usableAngle = 360 * fillRatio
        let gapAngle = n > 1 ? (360 - usableAngle) / Double(n) : 0
        let fallbackColors: [Color] = [
            OnboardingDesign.accentGreen,
            OnboardingDesign.accentBlue,
            OnboardingDesign.accentAmber,
            OnboardingDesign.bgTop,
            Color.white.opacity(0.6)
        ]
        var current: Double = 0
        return sorted.enumerated().map { i, pair in
            let norm = pair.value / total
            let segmentAngle = usableAngle * norm
            let start = current
            let end = start + segmentAngle
            current = end + gapAngle
            let cat = CategoryStore.byId(pair.key)
            let label = cat?.name ?? pair.key.capitalized
            let color = cat?.color ?? fallbackColors[i % fallbackColors.count]
            return SubsChartSegment(
                id: pair.key,
                start: CGFloat(start / 360),
                end: CGFloat(end / 360),
                color: color,
                label: label,
                percent: norm
            )
        }
    }

    private var donutChartView: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 4)
            ForEach(subscriptionChartSegments) { seg in
                Circle()
                    .trim(from: seg.start, to: seg.end)
                    .stroke(seg.color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(2)
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
        guard let s = dateStr, !s.isEmpty else { return "\u{2014}" }
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

struct SubsGlassModifier: ViewModifier {
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
