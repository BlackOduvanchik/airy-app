//
//  YearInReviewView.swift
//  Airy
//
//  Year in Review: period picker, dual income/expense charts, top categories, 6 tiers of insights.
//

import SwiftUI

struct YearInReviewView: View {
    @Environment(ThemeProvider.self) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = YearInReviewViewModel()
    @State private var dragIndex: Int? = nil

    var body: some View {
        ZStack(alignment: .top) {
            OnboardingGradientBackground()

            ScrollView(.vertical) {
                VStack(spacing: 16) {
                    headerSection
                    periodPicker
                    chartSection
                    totalsRow
                    topCategoriesSection
                    insightsSection
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
                Text(L("yr_toolbar_title"))
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(theme.textTertiary)
            }
        }
        .task { await viewModel.load() }
    }

    // MARK: - Header

    private var headerSection: some View {
        Text(L("yr_header"))
            .font(.system(size: 34, weight: .light))
            .tracking(-0.5)
            .lineSpacing(4)
            .foregroundColor(theme.textPrimary)
            .multilineTextAlignment(.center)
    }

    // MARK: - Period Picker

    private var periodPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                periodPill(id: "all", label: L("yr_all_time"))
                ForEach(viewModel.availableYears, id: \.self) { year in
                    periodPill(id: year, label: year)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
    }

    private func periodPill(id: String, label: String) -> some View {
        let isSelected = viewModel.selectedPeriod == id
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.selectedPeriod = id
                viewModel.selectedMonthIndex = nil
                dragIndex = nil
                viewModel.recompute()
            }
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isSelected ? .white : theme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? theme.accentGreen : Color.white.opacity(theme.isDark ? 0.06 : 0.3))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isSelected ? Color.clear : Color.white.opacity(theme.isDark ? 0.08 : 0.4), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Chart Section

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L("yr_chart_title"))
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.8)
                    .foregroundColor(theme.textTertiary)
                Spacer()
                chartModeToggle
            }
            .padding(.horizontal, 24)

            dragTooltip
                .padding(.horizontal, 24)

            if viewModel.chartMode == .all {
                allModeChart
                    .frame(height: 180)
                    .padding(.leading, 24)
                    .clipped()
            } else {
                monthModeChart
                    .frame(height: 180)
                    .padding(.leading, 24)
                    .clipped()
            }

            monthLabels
                .padding(.leading, 24)
                .padding(.trailing, 24)

            filterToggles
                .padding(.horizontal, 24)
        }
        .padding(.vertical, 24)
        .modifier(InsightsGlassModifier())
    }

    private var chartModeToggle: some View {
        HStack(spacing: 0) {
            ForEach(YRChartMode.allCases, id: \.rawValue) { mode in
                let isActive = viewModel.chartMode == mode
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.chartMode = mode
                        if mode == .all { viewModel.selectedMonthIndex = nil }
                        dragIndex = nil
                        viewModel.recompute()
                    }
                } label: {
                    Text(mode == .all ? L("yr_all") : L("yr_month"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isActive ? .white : theme.textTertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isActive ? theme.accentGreen.opacity(0.8) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.white.opacity(theme.isDark ? 0.06 : 0.3))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - All Mode (Line Chart)

    private var allModeChart: some View {
        GeometryReader { geo in
            let data = viewModel.displayedMonthlyData
            let w = geo.size.width
            let h = geo.size.height
            let chartW = w - 23
            let allValues = data.flatMap { [viewModel.showIncome ? $0.income : 0, viewModel.showExpense ? $0.expense : 0] }
            let maxVal = max(allValues.max() ?? 1, 1)

            if data.count >= 2 {
                ZStack {
                    yAxisGridOverlay(maxVal: maxVal, height: h)

                    if viewModel.showIncome {
                        lineArea(data: data.map { $0.income }, maxVal: maxVal, w: chartW, h: h,
                                 color: theme.incomeColor)
                    }
                    if viewModel.showExpense {
                        lineArea(data: data.map { $0.expense }, maxVal: maxVal, w: chartW, h: h,
                                 color: theme.expenseColor)
                    }

                    // Drag indicator
                    if let di = dragIndex, di < data.count {
                        let xPos = CGFloat(di) / CGFloat(max(data.count - 1, 1)) * chartW
                        Path { p in
                            p.move(to: CGPoint(x: xPos, y: 0))
                            p.addLine(to: CGPoint(x: xPos, y: h))
                        }
                        .stroke(theme.textPrimary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

                        if viewModel.showIncome {
                            Circle().fill(theme.incomeColor)
                                .frame(width: 8, height: 8)
                                .position(x: xPos, y: (1 - CGFloat(data[di].income / maxVal)) * h)
                        }
                        if viewModel.showExpense {
                            Circle().fill(theme.expenseColor)
                                .frame(width: 8, height: 8)
                                .position(x: xPos, y: (1 - CGFloat(data[di].expense / maxVal)) * h)
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let count = data.count
                            guard count >= 2 else { return }
                            let x = min(max(value.location.x, 0), chartW)
                            let step = chartW / CGFloat(count - 1)
                            dragIndex = min(count - 1, max(0, Int((x / step).rounded())))
                        }
                        .onEnded { _ in }
                )
            } else {
                emptyChartPlaceholder
            }
        }
    }

    private func lineArea(data: [Double], maxVal: Double, w: CGFloat, h: CGFloat, color: Color) -> some View {
        let points: [CGPoint] = data.enumerated().map { i, v in
            let x = data.count > 1 ? CGFloat(i) / CGFloat(data.count - 1) * w : w / 2
            let y = (1 - CGFloat(v / maxVal)) * h
            return CGPoint(x: x, y: y)
        }

        return ZStack {
            // Fill
            Path { p in
                guard points.count >= 2 else { return }
                p.move(to: points[0])
                for pt in points.dropFirst() { p.addLine(to: pt) }
                p.addLine(to: CGPoint(x: points.last!.x, y: h))
                p.addLine(to: CGPoint(x: points[0].x, y: h))
                p.closeSubpath()
            }
            .fill(LinearGradient(colors: [color.opacity(0.3), color.opacity(0)], startPoint: .top, endPoint: .bottom))

            // Line
            Path { p in
                guard points.count >= 2 else { return }
                p.move(to: points[0])
                for pt in points.dropFirst() { p.addLine(to: pt) }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
    }

    // MARK: - Month Mode (Bar Chart)

    private var monthModeChart: some View {
        GeometryReader { geo in
            let data = viewModel.displayedMonthlyData
            let w = geo.size.width
            let h = geo.size.height
            let chartW = w - 23
            let allValues = data.flatMap { [$0.income, $0.expense] }
            let maxVal = max(allValues.max() ?? 1, 1)
            let count = max(data.count, 1)
            let groupWidth = chartW / CGFloat(count)
            let barWidth = max(4, (groupWidth - 6) / 2)

            ZStack(alignment: .bottomLeading) {
                yAxisGridOverlay(maxVal: maxVal, height: h)

                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(Array(data.enumerated()), id: \.element.id) { index, month in
                        let isActive = dragIndex == index || (dragIndex == nil && viewModel.selectedMonthIndex == index)
                        HStack(alignment: .bottom, spacing: 2) {
                            if viewModel.showIncome {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(theme.incomeColor.opacity(isActive ? 1 : 0.6))
                                    .frame(width: barWidth, height: max(2, h * CGFloat(month.income / maxVal)))
                            }
                            if viewModel.showExpense {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(theme.expenseColor.opacity(isActive ? 1 : 0.6))
                                    .frame(width: barWidth, height: max(2, h * CGFloat(month.expense / maxVal)))
                            }
                        }
                        .frame(width: groupWidth)
                        .scaleEffect(isActive ? 1.05 : 1.0, anchor: .bottom)
                    }
                }
                .frame(width: chartW)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard count >= 1 else { return }
                        let x = min(max(value.location.x, 0), chartW)
                        dragIndex = min(data.count - 1, max(0, Int(x / groupWidth)))
                    }
                    .onEnded { value in
                        let dist = abs(value.translation.width) + abs(value.translation.height)
                        if dist < 10, let di = dragIndex {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.selectedMonthIndex = viewModel.selectedMonthIndex == di ? nil : di
                                viewModel.recompute()
                            }
                        }
                    }
            )
        }
    }

    // MARK: - Month Labels

    @ViewBuilder
    private var monthLabels: some View {
        let data = viewModel.displayedMonthlyData
        if viewModel.selectedPeriod == "all" && data.count > 12 {
            // All Time — show year labels positioned at January of each year
            GeometryReader { geo in
                let w = geo.size.width
                let count = max(data.count - 1, 1)
                ForEach(Array(data.enumerated()), id: \.element.id) { index, month in
                    if month.monthKey.hasSuffix("-01") || index == 0 {
                        let x = viewModel.chartMode == .all
                            ? CGFloat(index) / CGFloat(count) * w
                            : (CGFloat(index) + 0.5) / CGFloat(data.count) * w
                        Text("'" + String(month.monthKey.prefix(4).suffix(2)))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(theme.textTertiary)
                            .position(x: x, y: 6)
                    }
                }
            }
            .frame(height: 14)
        } else {
            HStack(spacing: 0) {
                ForEach(Array(data.enumerated()), id: \.element.id) { index, month in
                    Text(String(month.label.prefix(1)))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(dragIndex == index || viewModel.selectedMonthIndex == index ? theme.textPrimary : theme.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Filter Toggles

    private var filterToggles: some View {
        HStack(spacing: 10) {
            filterChip(label: L("yr_income"), color: theme.incomeColor, isOn: viewModel.showIncome) {
                viewModel.showIncome.toggle(); viewModel.recompute()
            }
            filterChip(label: L("yr_expense"), color: theme.expenseColor, isOn: viewModel.showExpense) {
                viewModel.showExpense.toggle(); viewModel.recompute()
            }
            filterChip(label: L("yr_sub"), color: theme.accentAmber, isOn: !viewModel.excludeSubscriptions) {
                viewModel.excludeSubscriptions.toggle(); viewModel.recompute()
            }
            Spacer()
        }
    }

    private func filterChip(label: String, color: Color, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isOn ? color : color.opacity(0.3))
                    .frame(width: 8, height: 8)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isOn ? theme.textPrimary : theme.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(theme.isDark ? 0.06 : 0.3))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Totals Row

    private var totalsRow: some View {
        HStack(spacing: 10) {
            totalTile(caption: L("yr_income"), amount: viewModel.totalIncome, color: theme.incomeColor)
            totalTile(caption: L("yr_expense"), amount: viewModel.totalExpense, color: theme.expenseColor)
            totalTile(caption: L("yr_net"), amount: viewModel.totalNet, color: viewModel.totalNet >= 0 ? theme.incomeColor : theme.expenseColor)
        }
    }

    private func totalTile(caption: String, amount: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(caption.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(theme.textTertiary)
            Text((amount < 0 ? "\u{2011}" : "") + AppFormatters.formatTotal(amount: amount, currency: BaseCurrencyStore.baseCurrency, fractionDigits: 0))
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .modifier(InsightsGlassModifier())
    }

    // MARK: - Top Categories

    private var topCategoriesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("yr_top_categories"))
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(theme.textTertiary)

            if viewModel.topCategories.isEmpty {
                Text(L("yr_no_data"))
                    .font(.system(size: 14))
                    .foregroundColor(theme.textTertiary)
                    .padding(.vertical, 8)
            } else {
                let topAmount = viewModel.topCategories.first?.amount ?? 1
                ForEach(viewModel.topCategories) { cat in
                    categoryRow(cat: cat, topAmount: topAmount)
                }
            }
        }
        .padding(20)
        .modifier(InsightsGlassModifier())
    }

    private func categoryRow(cat: YRCategorySummary, topAmount: Double) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: cat.iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(cat.color)
                    .clipShape(Circle())

                Text(cat.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(theme.textPrimary)

                Spacer()

                Text(AppFormatters.formatTotal(amount: cat.amount, currency: BaseCurrencyStore.baseCurrency, fractionDigits: 0))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(theme.textPrimary)

                Text(String(format: "%.0f%%", cat.share * 100))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(theme.textTertiary)
                    .frame(width: 36, alignment: .trailing)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(theme.isDark ? 0.05 : 0.3))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(cat.color.opacity(0.8))
                        .frame(width: topAmount > 0 ? geo.size.width * CGFloat(cat.amount / topAmount) : 0, height: 6)
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: - Insights

    private var insightsSection: some View {
        ForEach(viewModel.activeSections) { group in
            VStack(alignment: .leading, spacing: 12) {
                Text(group.section.displayName.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.8)
                    .foregroundColor(theme.textTertiary)
                    .padding(.leading, 4)

                ForEach(group.cards) { card in
                    insightCard(card)
                }
            }
        }
    }

    private func insightCard(_ card: YRInsightCard) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: card.icon)
                .font(.system(size: 18))
                .foregroundColor(card.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(theme.textPrimary)
                parseBoldText(card.body)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .foregroundColor(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .modifier(InsightsGlassModifier())
    }

    // MARK: - Rich Text Parser
    // Markers: **bold** (neutral), ++green++ (income), --red-- (expense)

    private func parseBoldText(_ text: String) -> Text {
        var result = Text("")
        var remaining = text[...]

        while !remaining.isEmpty {
            // Find the earliest marker by position
            var earliest: (range: Range<Substring.Index>, marker: String)?
            for m in ["++", "--", "**"] {
                if let r = remaining.range(of: m) {
                    if earliest == nil || r.lowerBound < earliest!.range.lowerBound {
                        earliest = (r, m)
                    }
                }
            }

            guard let found = earliest else {
                result = Text("\(result)\(Text(remaining))")
                break
            }

            let plain = remaining[remaining.startIndex..<found.range.lowerBound]
            if !plain.isEmpty { result = Text("\(result)\(Text(plain))") }

            remaining = remaining[found.range.upperBound...]
            if let close = remaining.range(of: found.marker) {
                let inner = String(remaining[remaining.startIndex..<close.lowerBound])
                let color: Color = found.marker == "++" ? theme.incomeColor : found.marker == "--" ? theme.expenseColor : theme.textPrimary
                result = Text("\(result)\(Text(inner).fontWeight(.semibold).foregroundColor(color))")
                remaining = remaining[close.upperBound...]
            }
        }
        return result
    }

    // MARK: - Drag Tooltip

    private var dragTooltip: some View {
        let data = viewModel.displayedMonthlyData
        let di = dragIndex
        let hasData = di != nil && di! < data.count
        let month = hasData ? data[di!] : nil

        return HStack(spacing: 12) {
            Text(month?.fullLabel ?? " ")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(theme.textPrimary)
            if viewModel.showExpense {
                Text(AppFormatters.formatTotal(amount: month?.expense ?? 0, currency: BaseCurrencyStore.baseCurrency, fractionDigits: 0))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(theme.expenseColor)
            }
            if viewModel.showIncome {
                Text(AppFormatters.formatTotal(amount: month?.income ?? 0, currency: BaseCurrencyStore.baseCurrency, fractionDigits: 0))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(theme.incomeColor)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity)
        .opacity(hasData ? 1 : 0)
    }

    // MARK: - Y-Axis Grid

    /// Compute "nice" Y-axis tick values: 3-5 evenly-spaced round numbers from 0 to ≥ maxVal.
    private func yAxisTicks(maxVal: Double) -> [Double] {
        guard maxVal > 0 else { return [] }
        let rawStep = maxVal / 5
        let magnitude = pow(10, floor(log10(rawStep)))
        let normalized = rawStep / magnitude
        let niceStep: Double
        if normalized <= 1.0 { niceStep = 1.0 * magnitude }
        else if normalized <= 2.0 { niceStep = 2.0 * magnitude }
        else if normalized <= 2.5 { niceStep = 2.5 * magnitude }
        else if normalized <= 5.0 { niceStep = 5.0 * magnitude }
        else { niceStep = 10.0 * magnitude }

        var ticks: [Double] = []
        var v = niceStep
        while v <= maxVal && ticks.count < 5 {
            ticks.append(v)
            v += niceStep
        }
        return ticks
    }

    /// Format axis label: compact (1K, 2.5K, 1M) with currency symbol.
    private func axisLabel(_ value: Double) -> String {
        let symbol = AppFormatters.currencySymbol(for: BaseCurrencyStore.baseCurrency)
        if value >= 1_000_000 {
            let m = value / 1_000_000
            return m.truncatingRemainder(dividingBy: 1) == 0
                ? "\(symbol)\(Int(m))M"
                : String(format: "\(symbol)%.1fM", m)
        } else if value >= 1_000 {
            let k = value / 1_000
            return k.truncatingRemainder(dividingBy: 1) == 0
                ? "\(symbol)\(Int(k))K"
                : String(format: "\(symbol)%.1fK", k)
        } else {
            return "\(symbol)\(Int(value))"
        }
    }

    private func yAxisGridOverlay(maxVal: Double, height: CGFloat) -> some View {
        let ticks = yAxisTicks(maxVal: maxVal)
        return GeometryReader { geo in
            let w = geo.size.width
            let chartW = w - 23
            ForEach(ticks, id: \.self) { tick in
                let y = (1 - CGFloat(tick / maxVal)) * height
                Path { p in
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: chartW, y: y))
                }
                .stroke(theme.textTertiary.opacity(0.12), style: StrokeStyle(lineWidth: 0.5, dash: [4, 3]))

                Text(axisLabel(tick))
                    .font(.system(size: 8, weight: .medium).monospacedDigit())
                    .foregroundColor(theme.textTertiary)
                    .position(x: w - 12, y: y - 7)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Empty state

    private var emptyChartPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 28))
                .foregroundColor(theme.textTertiary.opacity(0.5))
            Text(L("yr_no_data"))
                .font(.system(size: 13))
                .foregroundColor(theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
