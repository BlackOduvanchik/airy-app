//
//  InsightsView.swift
//  Airy
//
//  AI spending analysis: Money Mirror, comparison, yearly chart, what changed, insights, anomaly, subscription trend.
//

import SwiftUI

struct InsightsView: View {
    @Environment(ThemeProvider.self) private var theme
    @State private var viewModel = InsightsViewModel()
    @State private var showYearInReview = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                OnboardingGradientBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        headerSection
                        aiCardSection
                        comparisonRowSection
                        yearlyChartSection
                        whatChangedSection
                        insightMirrorSections
                        anomalyCardSection
                        subscriptionTrendSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 120)
                }
                .scrollIndicators(.hidden)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(L("insights_title"))
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(theme.textTertiary)
                }
            }
            .navigationDestination(isPresented: $showYearInReview) {
                YearInReviewView()
                    .environment(theme)
            }
            .sheet(isPresented: $viewModel.showPaywall) {
                PaywallView()
                    .environment(theme)
            }
            .task { await viewModel.load() }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        Text(L("insights_header"))
            .font(.system(size: 34, weight: .light))
            .tracking(-0.5)
            .lineSpacing(4)
            .foregroundColor(theme.textPrimary)
            .multilineTextAlignment(.center)
    }

    // MARK: - AI card

    private var aiCardSection: some View {
        Group {
            if viewModel.isLoading && viewModel.summaryText.isEmpty {
                insightsGlassPanel {
                    HStack(alignment: .center, spacing: 14) {
                        ProgressView()
                        Text(L("insights_analyzing"))
                            .font(.system(size: 14))
                            .foregroundColor(theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            } else {
                insightsGlassPanel {
                    HStack(alignment: .center, spacing: 14) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 20))
                            .foregroundColor(theme.accentBlue)
                        Text(viewModel.summaryText.isEmpty ? L("insights_empty") : viewModel.summaryText)
                            .font(.system(size: 14))
                            .lineSpacing(4)
                            .foregroundColor(theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Comparison row (This Month / Last Month)

    private var comparisonRowSection: some View {
        HStack(spacing: 12) {
            comparisonTile(
                caption: L("insights_this_month"),
                amount: viewModel.thisMonthSpent,
                isPrimary: true,
                deltaPercent: viewModel.hasMultipleMonths ? viewModel.deltaPercent : nil
            )
            comparisonTile(
                caption: L("insights_last_month"),
                amount: viewModel.lastMonthSpent,
                isPrimary: false,
                deltaPercent: nil
            )
        }
    }

    private func comparisonTile(caption: String, amount: Double, isPrimary: Bool, deltaPercent: Double?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(caption.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(theme.textTertiary)
            Text(formatCurrency(amount))
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(isPrimary ? theme.textPrimary : theme.textTertiary)
            if let delta = deltaPercent, isPrimary {
                deltaChip(down: delta < 0, value: abs(Int(delta.rounded())))
            } else {
                // Invisible spacer matching deltaChip height for equal tile sizes
                Color.clear.frame(height: 22)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .modifier(InsightsGlassModifier())
    }

    private func deltaChip(down: Bool, value: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: down ? "chevron.down" : "chevron.up")
                .font(.system(size: 10, weight: .bold))
            Text("\(value)%")
                .font(.system(size: 12, weight: .bold))
        }
        .foregroundColor(down ? theme.accentGreen : theme.accentAmber)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(theme.isDark ? 0.08 : 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Yearly overview chart

    private var yearlyChartSection: some View {
        let history = viewModel.snapshot?.monthlyHistory ?? []

        return VStack(alignment: .leading, spacing: 0) {
            Text(L("insights_yearly"))
                .font(.system(size: 12, weight: .semibold))
                .tracking(1)
                .foregroundColor(theme.textTertiary)
            yearlyChartView(points: history)
                .frame(height: 120)
                .padding(.top, 16)
            HStack {
                ForEach(Array(history.enumerated()), id: \.element.id) { index, pt in
                    Text(pt.shortLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(pt.isCurrent ? theme.textPrimary : theme.textTertiary)
                    if index < history.count - 1 { Spacer(minLength: 0) }
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 8)
        }
        .padding(24)
        .padding(.horizontal, 4)
        .modifier(InsightsGlassModifier())
        .contentShape(Rectangle())
        .onTapGesture { showYearInReview = true }
    }

    private func yearlyChartView(points: [MonthlySpendPoint]) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let maxVal = points.map(\.total).max() ?? 1
            let safeMax = maxVal > 0 ? maxVal : 1

            let normalized: [(x: CGFloat, y: CGFloat, isCurrent: Bool)] = points.enumerated().map { i, pt in
                let x = points.count > 1 ? CGFloat(i) / CGFloat(points.count - 1) : 0.5
                let y = CGFloat(pt.total / safeMax)
                return (x, y, pt.isCurrent)
            }

            if normalized.count >= 2 {
                ZStack(alignment: .topLeading) {
                    // Fill
                    Path { p in
                        let xs = normalized.map { $0.x * w }
                        let ys = normalized.map { (1 - $0.y) * h }
                        p.move(to: CGPoint(x: xs[0], y: ys[0]))
                        for i in 1..<normalized.count { p.addLine(to: CGPoint(x: xs[i], y: ys[i])) }
                        p.addLine(to: CGPoint(x: xs.last!, y: h))
                        p.addLine(to: CGPoint(x: xs[0], y: h))
                        p.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [theme.accentGreen.opacity(0.3), theme.accentGreen.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    // Line
                    Path { p in
                        let xs = normalized.map { $0.x * w }
                        let ys = normalized.map { (1 - $0.y) * h }
                        p.move(to: CGPoint(x: xs[0], y: ys[0]))
                        for i in 1..<normalized.count { p.addLine(to: CGPoint(x: xs[i], y: ys[i])) }
                    }
                    .stroke(theme.accentGreen, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    // Current month dot
                    if let current = normalized.first(where: { $0.isCurrent }) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(theme.accentGreen, lineWidth: 2))
                            .position(x: current.x * w, y: (1 - current.y) * h)
                    }
                }
            }
        }
    }

    // MARK: - What Changed (horizontal pills)

    private var whatChangedSection: some View {
        let deltas = (viewModel.snapshot?.categoryDeltas ?? [])
            .filter { abs($0.deltaPercent) >= 5 && $0.lastMonth > 0 }
            .prefix(6)

        return Group {
            if !deltas.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L("insights_what_changed"))
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(1)
                        .foregroundColor(theme.textTertiary)
                        .padding(.leading, 4)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(deltas)) { d in
                                deltaPill(categoryId: d.id, label: d.name, delta: Int(d.deltaPercent.rounded()), up: d.deltaPercent > 0)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            } else if viewModel.hasMultipleMonths && viewModel.hasEnoughData {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L("insights_what_changed"))
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(1)
                        .foregroundColor(theme.textTertiary)
                        .padding(.leading, 4)
                    insightsGlassPanel {
                        Text(L("insights_stable_cats"))
                            .font(.system(size: 14))
                            .foregroundColor(theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func deltaPill(categoryId: String, label: String, delta: Int, up: Bool) -> some View {
        let iconName = CategoryIconHelper.iconName(categoryId: categoryId)
        let iconColor = CategoryIconHelper.color(categoryId: categoryId)

        return HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(iconColor)
                .clipShape(Circle())
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(theme.textPrimary)
            Text("\(up ? "+" : "")\(delta)%")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(up ? theme.accentAmber : theme.accentGreen)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.white.opacity(theme.isDark ? 0.05 : 0.4))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(theme.isDark ? 0.08 : 0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Insight mirror cards

    private var insightMirrorSections: some View {
        let cards = buildInsightCards()
        return Group {
            ForEach(Array(cards.enumerated()), id: \.offset) { _, text in
                insightsGlassPanel {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 18))
                            .foregroundColor(theme.accentBlue)
                        Text(text)
                            .font(.system(size: 14))
                            .lineSpacing(4)
                            .foregroundColor(theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func buildInsightCards() -> [String] {
        guard let s = viewModel.snapshot, viewModel.hasEnoughData else {
            return [L("insights_add_more")]
        }
        var cards: [String] = []

        // Weekend vs weekday
        if s.weekendAvgSpend > 0 && s.weekdayAvgSpend > 0 {
            if s.weekendAvgSpend > s.weekdayAvgSpend * 1.3 {
                cards.append(L("insights_weekend_higher", fmtCur(s.weekendAvgSpend), fmtCur(s.weekdayAvgSpend)))
            } else if s.weekdayAvgSpend > s.weekendAvgSpend * 1.3 {
                cards.append(L("insights_weekday_higher", fmtCur(s.weekdayAvgSpend), fmtCur(s.weekendAvgSpend)))
            }
        }

        // Projected savings
        if s.projectedMonthlySavings > 50 && s.thisMonthIncome > 0 {
            cards.append(L("insights_projected_save", fmtCur(s.projectedMonthlySavings)))
        }

        // Safe to spend
        if s.safeToSpend > 0 && s.thisMonthIncome > 0 {
            cards.append(L("insights_safe_to_spend", fmtCur(s.safeToSpend)))
        }

        // Top merchant in biggest shifting category
        if let topDelta = s.categoryDeltas.first(where: { abs($0.deltaPercent) > 15 && $0.lastMonth > 0 }),
           let topMerch = s.topMerchantByCategory[topDelta.id] {
            let dir = topDelta.deltaPercent > 0 ? L("insights_higher") : L("insights_lower")
            cards.append(L("insights_cat_trend", topDelta.name, dir, topMerch.merchant))
        }

        if cards.isEmpty {
            cards.append(L("insights_healthy"))
        }
        return Array(cards.prefix(3))
    }

    // MARK: - Anomaly card

    @ViewBuilder
    private var anomalyCardSection: some View {
        if let anomaly = viewModel.snapshot?.merchantAnomalies.first, viewModel.hasEnoughData {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "triangle.exclamationmark.fill")
                    .font(.system(size: 24))
                    .foregroundColor(theme.accentAmber)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(anomaly.merchant)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(theme.textPrimary)
                        Spacer()
                        Text(fmtCur(anomaly.currentSpent))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(theme.accentAmber)
                    }
                    Text(L("insights_anomaly_ratio", String(format: "%.1f", anomaly.ratio)))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(theme.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)
            .background(Color.orange.opacity(0.08))
            .overlay(
                Rectangle()
                    .fill(theme.accentAmber)
                    .frame(width: 4),
                alignment: .leading
            )
            .clipShape(RoundedRectangle(cornerRadius: 28))
        }
    }

    // MARK: - Subscription trend

    @ViewBuilder
    private var subscriptionTrendSection: some View {
        if let trend = viewModel.snapshot?.subscriptionTrend, !trend.monthlyTotals.isEmpty,
           trend.monthlyTotals.contains(where: { $0.total > 0 }) {
            let maxTotal = trend.monthlyTotals.map(\.total).max() ?? 1
            let safeMax = maxTotal > 0 ? maxTotal : 1
            let isLast = trend.monthlyTotals.count

            VStack(alignment: .leading, spacing: 0) {
                Text(L("insights_sub_trend"))
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1)
                    .foregroundColor(theme.textTertiary)
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(Array(trend.monthlyTotals.enumerated()), id: \.offset) { i, item in
                        let ratio = item.total / safeMax
                        let isRecent = i >= isLast - 2
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isRecent ? theme.accentBlue : theme.bgBottomLeft.opacity(0.4))
                            .frame(height: max(4, 60 * CGFloat(ratio)))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 60)
                .padding(.top, 20)
                Text(subscriptionTrendText(trend))
                    .font(.system(size: 13))
                    .foregroundColor(theme.textSecondary)
                    .padding(.top, 16)
            }
            .padding(24)
            .padding(.horizontal, 4)
            .modifier(InsightsGlassModifier())
        }
    }

    private func subscriptionTrendText(_ trend: SubscriptionTrendData) -> String {
        var parts: [String] = []
        if abs(trend.deltaAmount) > 1 {
            let dir = trend.deltaAmount > 0 ? L("insights_up") : L("insights_down")
            parts.append("\(dir) \(fmtCur(abs(trend.deltaAmount))) \(L("insights_over_6mo"))")
        }
        if trend.newSubsCount > 0 {
            let s = trend.newSubsCount == 1 ? "" : "s"
            parts.append("\(trend.newSubsCount) \(L("insights_new_subs", s))")
        }
        return parts.isEmpty ? L("insights_subs_stable") : parts.joined(separator: " · ")
    }

    // MARK: - Helpers

    private func insightsGlassPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .modifier(InsightsGlassModifier())
    }

    private func formatCurrency(_ value: Double) -> String {
        fmtCur(value)
    }

    private func fmtCur(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = BaseCurrencyStore.baseCurrency
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }
}

// MARK: - Glass modifier for insights

struct InsightsGlassModifier: ViewModifier {
    @Environment(ThemeProvider.self) private var theme
    func body(content: Content) -> some View {
        content
            .background(theme.isDark ? AnyShapeStyle(theme.glassBg) : AnyShapeStyle(.ultraThinMaterial))
            .overlay(theme.isDark ? nil : theme.glassBg.opacity(0.5).allowsHitTesting(false))
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .stroke(theme.glassBorder, lineWidth: 1)
                    .allowsHitTesting(false)
            )
            .shadow(color: theme.isDark ? Color.black.opacity(0.4) : theme.textPrimary.opacity(0.06), radius: 16, x: 0, y: 8)
    }
}

#Preview {
    InsightsView()
}
