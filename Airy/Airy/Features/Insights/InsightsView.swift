//
//  InsightsView.swift
//  Airy
//
//  AI spending analysis: Money Mirror, comparison, yearly chart, what changed, insights, anomaly, subscription trend.
//

import SwiftUI

/// Navigation routes from Insights page.
enum InsightsRoute: Hashable {
    case subscriptions
    case transactionsCategory(String)
    case transactionsMerchant(String)
    case yearInReview
}

struct InsightsView: View {
    @Environment(ThemeProvider.self) private var theme
    @State private var viewModel = InsightsViewModel()
    @State private var navPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navPath) {
            ZStack(alignment: .top) {
                OnboardingGradientBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        headerSection
                        aiCardSection
                        unifiedComparisonSection
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
            .sheet(isPresented: $viewModel.showPaywall) {
                PaywallView()
                    .themed(theme)
            }
            .navigationDestination(for: InsightsRoute.self) { route in
                switch route {
                case .subscriptions:
                    SubscriptionsView(embedded: true)
                        .environment(theme)
                case .transactionsCategory(let catId):
                    TransactionListView(initialCategoryFilter: catId)
                        .environment(theme)
                case .transactionsMerchant(let merchant):
                    TransactionListView(initialSearchText: merchant)
                        .environment(theme)
                case .yearInReview:
                    YearInReviewView()
                        .environment(theme)
                }
            }
            .onAppear { print("[Nav] Insights") }
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
                        markdownText(viewModel.summaryText.isEmpty ? L("insights_empty") : viewModel.summaryText)
                            .font(.system(size: 14))
                            .lineSpacing(4)
                            .foregroundColor(theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 4)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if viewModel.summaryMentionsSubscriptions {
                        navPath.append(InsightsRoute.subscriptions)
                    }
                }
            }
        }
    }

    // MARK: - Unified Spending Comparison

    /// Color based on month-over-month delta: green (saving), amber (slight over), orange (heavy over).
    private var pacingColor: Color {
        let delta = viewModel.deltaPercent
        if delta <= 0 { return theme.accentGreen }
        if delta <= 15 { return theme.accentAmber }
        return Color(red: 0.9, green: 0.45, blue: 0.2) // orange
    }

    private var unifiedComparisonSection: some View {
        VStack(spacing: 20) {
            pacingHeaderRow
            amountsWithTrendRow
        }
        .padding(24)
        .padding(.horizontal, -4)
        .modifier(InsightsGlassModifier())
    }

    // MARK: Pacing header

    private var pacingHeaderRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                pacingBadge
                pacingSubtitle
                    .padding(.top, 2)
            }
            Spacer(minLength: 12)
            monthProgressCircle
        }
    }

    private var pacingBadge: some View {
        let delta = viewModel.deltaPercent
        let absDelta = abs(Int(delta.rounded()))
        let text: String = {
            if delta <= -1 { return L("insights_pacing_better", "\(absDelta)") }
            if delta >= 1 { return L("insights_pacing_over", "\(absDelta)") }
            return L("insights_pacing_same")
        }()

        return Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(pacingColor)
            .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var pacingSubtitle: some View {
        let thisMonth = viewModel.thisMonthSpent
        let lastMonthFull = viewModel.lastMonthSpent
        let day = viewModel.snapshot?.dayOfMonth ?? 1
        let daysInLastMonth = viewModel.snapshot?.daysInMonth ?? 30 // approximate
        let lastMonthPace = lastMonthFull * Double(day) / Double(daysInLastMonth)
        let delta = lastMonthPace - thisMonth // positive = saving vs last month at same point
        let text: String = {
            if !viewModel.hasMultipleMonths { return "" }
            if delta > 10 {
                return L("insights_save_vs_last", fmtCur(delta), "\(day)")
            }
            if delta < -10 {
                return L("insights_over_vs_last", fmtCur(abs(delta)), "\(day)")
            }
            return ""
        }()

        return Group {
            if !text.isEmpty {
                Text(text)
                    .font(.system(size: 14))
                    .foregroundColor(theme.textSecondary)
            }
        }
    }

    private var monthProgressCircle: some View {
        let lastSpent = CGFloat(viewModel.lastMonthSpent)
        let thisSpent = CGFloat(viewModel.thisMonthSpent)
        let progress: CGFloat
        let pct: Int
        if lastSpent > 0 {
            // Spending ratio: how much of last month's total you've spent so far
            let ratio = thisSpent / lastSpent
            progress = min(ratio, 1.5)
            pct = Int((ratio * 100).rounded())
        } else {
            // Fallback: calendar progress when no last-month data
            let day = CGFloat(viewModel.snapshot?.dayOfMonth ?? 1)
            let total = CGFloat(viewModel.snapshot?.daysInMonth ?? 30)
            progress = min(day / total, 1)
            pct = Int((progress * 100).rounded())
        }

        return ZStack {
            Circle()
                .stroke(Color.white.opacity(theme.isDark ? 0.1 : 0.3), lineWidth: 5)
            Circle()
                .trim(from: 0, to: min(progress, 1))
                .stroke(pacingColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(pct)%")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(pacingColor)
        }
        .frame(width: 56, height: 56)
    }

    // MARK: Amounts + weekly trend chart

    private var amountsWithTrendRow: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("insights_this_month"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(theme.textTertiary)
                Text(fmtCur(viewModel.thisMonthSpent))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(theme.textPrimary)
            }
            .frame(minWidth: 80)

            weeklyTrendChart
                .frame(height: 50)
                .padding(.horizontal, 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(L("insights_last_month"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(theme.textTertiary)
                Text(fmtCur(viewModel.lastMonthSpent))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(theme.textTertiary)
            }
            .frame(minWidth: 80)
        }
    }

    // MARK: Weekly trend chart (smooth Catmull-Rom)

    private var weeklyTrendChart: some View {
        let thisWeeks = viewModel.snapshot?.weeklySpendThisMonth ?? []
        let lastWeeks = viewModel.snapshot?.weeklySpendLastMonth ?? []
        let count = min(thisWeeks.count, lastWeeks.count)

        // Delta at each week point: positive = overspending, negative = saving
        let deltas: [Double] = {
            guard count > 0 else { return [0, 0] }
            return (0..<count).map { thisWeeks[$0] - lastWeeks[$0] }
        }()

        return GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let midY = h / 2

            let maxAbs = max(deltas.map { abs($0) }.max() ?? 1, 1)

            // Convert deltas to points: x evenly spaced, y normalized around center
            let points: [CGPoint] = deltas.enumerated().map { i, val in
                let x = deltas.count > 1 ? CGFloat(i) / CGFloat(deltas.count - 1) * w : w / 2
                let y = midY - CGFloat(val / maxAbs) * (h * 0.4) // up = overspend, down = saving
                return CGPoint(x: x, y: y)
            }

            if points.count >= 2 {
                let curvePath = catmullRomPath(points: points)
                let fillPath: Path = {
                    var p = curvePath
                    p.addLine(to: CGPoint(x: points.last!.x, y: midY))
                    p.addLine(to: CGPoint(x: points.first!.x, y: midY))
                    p.closeSubpath()
                    return p
                }()

                ZStack {
                    // Zero line
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: midY))
                        p.addLine(to: CGPoint(x: w, y: midY))
                    }
                    .stroke(Color.white.opacity(theme.isDark ? 0.08 : 0.2), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

                    // Gradient fill under curve
                    fillPath
                        .fill(
                            LinearGradient(
                                colors: [pacingColor.opacity(0.25), pacingColor.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    // Smooth line
                    curvePath
                        .stroke(pacingColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                    // End dot
                    Circle()
                        .fill(Color.white)
                        .frame(width: 6, height: 6)
                        .overlay(Circle().stroke(pacingColor, lineWidth: 2))
                        .position(points.last!)
                }
            }
        }
    }

    private func markdownText(_ string: String) -> Text {
        if let attributed = try? AttributedString(markdown: string) {
            return Text(attributed)
        }
        return Text(string)
    }

    /// Catmull-Rom spline → smooth SwiftUI Path through given points.
    private func catmullRomPath(points: [CGPoint], alpha: CGFloat = 0.5) -> Path {
        var path = Path()
        guard points.count >= 2 else { return path }

        path.move(to: points[0])

        for i in 0..<points.count - 1 {
            let p0 = i > 0 ? points[i - 1] : points[i]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = i + 2 < points.count ? points[i + 2] : points[i + 1]

            let cp1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6,
                y: p1.y + (p2.y - p0.y) / 6
            )
            let cp2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6,
                y: p2.y - (p3.y - p1.y) / 6
            )

            path.addCurve(to: p2, control1: cp1, control2: cp2)
        }

        return path
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
        .onTapGesture {
            print("[Tap] Insights → Year in Review")
            navPath.append(InsightsRoute.yearInReview)
        }
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
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        print("[Tap] Insights → What Changed '\(d.name)'")
                                        navPath.append(InsightsRoute.transactionsCategory(d.id))
                                    }
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
                        markdownText(text)
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
                cards.append(L("insights_weekend_higher", "**\(fmtCur(s.weekendAvgSpend))**", "**\(fmtCur(s.weekdayAvgSpend))**"))
            } else if s.weekdayAvgSpend > s.weekendAvgSpend * 1.3 {
                cards.append(L("insights_weekday_higher", "**\(fmtCur(s.weekdayAvgSpend))**", "**\(fmtCur(s.weekendAvgSpend))**"))
            }
        }

        // Projected savings
        if s.projectedMonthlySavings > 50 && s.thisMonthIncome > 0 {
            cards.append(L("insights_projected_save", "**\(fmtCur(s.projectedMonthlySavings))**"))
        }

        // Safe to spend
        if s.safeToSpend > 0 && s.thisMonthIncome > 0 {
            cards.append(L("insights_safe_to_spend", "**\(fmtCur(s.safeToSpend))**"))
        }

        // Top merchant in biggest shifting category
        if let topDelta = s.categoryDeltas.first(where: { abs($0.deltaPercent) > 15 && $0.lastMonth > 0 }),
           let topMerch = s.topMerchantByCategory[topDelta.id] {
            let dir = topDelta.deltaPercent > 0 ? L("insights_higher") : L("insights_lower")
            cards.append(L("insights_cat_trend", "**\(topDelta.name)**", dir, "**\(topMerch.merchant)**"))
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
                Image(systemName: "exclamationmark.triangle.fill")
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
            .contentShape(Rectangle())
            .onTapGesture {
                print("[Tap] Insights → Anomaly '\(anomaly.merchant)'")
                navPath.append(InsightsRoute.transactionsMerchant(anomaly.merchant))
            }
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
            .contentShape(Rectangle())
            .onTapGesture {
                print("[Tap] Insights → Subscription Trend")
                navPath.append(InsightsRoute.subscriptions)
            }
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
