//
//  CategoryBreakdownView.swift
//  Airy
//
//  Analytics: donut chart by category, expandable list with transactions.
//

import SwiftUI

struct CategoryBreakdownView: View {
    var refreshId: Int = 0
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = CategoryBreakdownViewModel()
    @State private var selectedSegmentIndex: Int? = nil
    @State private var selectedCategoryDetail: CategoryDetailDestination? = nil

    var body: some View {
        ZStack {
            OnboardingGradientBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    chartSection
                    if let idx = selectedSegmentIndex, idx < viewModel.segments.count {
                        selectedCategoryTooltip(segment: viewModel.segments[idx])
                    }
                    categoryListSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
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
                Text(viewModel.monthLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(OnboardingDesign.textTertiary)
            }
        }
        .fullScreenCover(item: $selectedCategoryDetail, onDismiss: {
            Task { await viewModel.load() }
        }) { dest in
            CategoryDetailView(destination: dest)
        }
        .task(id: refreshId) { await viewModel.load() }
    }

    // MARK: - Donut Chart

    private var chartSection: some View {
        ZStack {
            chartGlassPanel
            donutChart
            chartCenterText
        }
        .frame(height: 320)
    }

    private var chartGlassPanel: some View {
        RoundedRectangle(cornerRadius: 28)
            .fill(.ultraThinMaterial)
            .overlay(OnboardingDesign.glassBg.opacity(0.5).allowsHitTesting(false))
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .stroke(OnboardingDesign.glassBorder, lineWidth: 1)
                    .allowsHitTesting(false)
            )
            .shadow(color: OnboardingDesign.textPrimary.opacity(0.06), radius: 16, x: 0, y: 8)
    }

    private var donutChart: some View {
        let segments = viewModel.segments
        let strokeWidth: CGFloat = 43       // 10% thinner than 48
        let strokeWidthActive: CGFloat = 47 // 10% thinner than 52

        return GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height, 260)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            ZStack {
                // Background ring (subtle track, drawn separately, same path radius as segments)
                ArcSegmentShape(startAngle: .degrees(0), endAngle: .degrees(359.99))
                    .stroke(
                        Color.white.opacity(0.2),
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: size, height: size)
                    .position(center)
                    .allowsHitTesting(false)

                // Independent arc segments (no overlap, no blending)
                ForEach(Array(segments.enumerated()), id: \.offset) { index, seg in
                    let isActive = selectedSegmentIndex == index
                    ArcSegmentShape(startAngle: seg.startAngle, endAngle: seg.endAngle)
                        .stroke(
                            seg.color,
                            style: StrokeStyle(
                                lineWidth: isActive ? strokeWidthActive : strokeWidth,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                        .frame(width: size, height: size)
                        .position(center)
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.25)) {
                                selectedSegmentIndex = selectedSegmentIndex == index ? nil : index
                            }
                        }
                }
            }
        }
    }

    private var chartCenterText: some View {
        VStack(spacing: 2) {
            Text("Total")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(OnboardingDesign.textTertiary)
            Text(formatCurrencyWhole(viewModel.totalSpent))
                .font(.system(size: 28, weight: .light))
                .tracking(-0.5)
                .foregroundColor(OnboardingDesign.textPrimary)
        }
        .allowsHitTesting(false)
    }

    private func selectedCategoryTooltip(segment: CategorySegment) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(segment.color.opacity(0.8))
                .frame(width: 12, height: 12)
            Text(segment.label)
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(OnboardingDesign.textTertiary)
            Text(formatAmount(segment.amount, "USD"))
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(OnboardingDesign.textPrimary)
            Text("\(Int(segment.percent))%")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(OnboardingDesign.accentGreen)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(OnboardingDesign.bgTop, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
    }

    // MARK: - Category List

    private var categoryListSection: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.segments.enumerated()), id: \.element.categoryId) { index, seg in
                categoryRow(segment: seg, index: index)
                if index < viewModel.segments.count - 1 {
                    Divider()
                        .background(Color.white.opacity(0.3))
                        .padding(.leading, 56)
                }
            }
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .overlay(OnboardingDesign.glassBg.opacity(0.5).allowsHitTesting(false))
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(OnboardingDesign.glassBorder, lineWidth: 1)
                .allowsHitTesting(false)
        )
        .shadow(color: OnboardingDesign.textPrimary.opacity(0.06), radius: 16, x: 0, y: 8)
    }

    private func categoryRow(segment: CategorySegment, index: Int) -> some View {
        let dest = CategoryDetailDestination(
            categoryId: segment.categoryId,
            label: segment.label,
            amount: segment.amount,
            colorHex: segment.colorHex,
            iconName: segment.iconName,
            monthKey: viewModel.monthKey,
            monthLabel: viewModel.monthLabel
        )
        return Button {
            selectedCategoryDetail = dest
        } label: {
            HStack(alignment: .center, spacing: 16) {
                categoryIcon(segment: segment)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(segment.label)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(OnboardingDesign.textPrimary)
                        Spacer()
                        HStack(spacing: 8) {
                            Text(formatAmount(segment.amount, "USD"))
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(OnboardingDesign.textPrimary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(OnboardingDesign.textTertiary)
                        }
                    }
                    progressBar(ratio: segment.ratio, color: segment.color)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func categoryIcon(segment: CategorySegment) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(segment.color.opacity(0.18))
            .frame(width: 36, height: 36)
            .overlay(
                Image(systemName: segment.iconName)
                    .font(.system(size: 17))
                    .foregroundColor(segment.color)
            )
    }

    private func progressBar(ratio: CGFloat, color: Color) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.3))
                    .frame(height: 6)
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(0.8))
                    .frame(width: max(0, g.size.width * ratio), height: 6)
            }
        }
        .frame(height: 6)
    }

    // MARK: - Helpers

    private func formatCurrencyWhole(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = BaseCurrencyStore.baseCurrency
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }

    private func formatAmount(_ amount: Double, _ currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount) \(currency)"
    }
}

// MARK: - Arc Segment Shape (manual arc path, explicit angles)

private struct ArcSegmentShape: Shape {
    let startAngle: Angle
    let endAngle: Angle

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let size = min(rect.width, rect.height)
        let radius = size / 2 - 24  // keep stroke inside bounds
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle - .degrees(90),
            endAngle: endAngle - .degrees(90),
            clockwise: false
        )
        return path
    }
}

// MARK: - ViewModel

struct CategorySegment: Identifiable {
    let id: String
    let categoryId: String
    let label: String
    let amount: Double
    let ratio: CGFloat
    let percent: Double
    let color: Color
    let colorHex: String
    let iconName: String
    let startAngle: Angle
    let endAngle: Angle
}

@Observable
final class CategoryBreakdownViewModel {
    var segments: [CategorySegment] = []
    var totalSpent: Double = 0
    var monthLabel: String = ""
    var monthKey: String = ""
    var transactionsByCategory: [String: [Transaction]] = [:]
    var isLoading = true

    private let fallbackColors: [Color] = [
        OnboardingDesign.accentGreen,
        OnboardingDesign.accentBlue,
        OnboardingDesign.bgBottomRight,
        Color.white.opacity(0.6)
    ]

    func load() async {
        isLoading = true
        defer { Task { @MainActor in isLoading = false } }
        await MainActor.run {
            let cal = Calendar.current
            let now = Date()
            let year = cal.component(.year, from: now)
            let month = cal.component(.month, from: now)
            let monthStr = String(format: "%02d", month)
            let yearStr = String(year)

            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            var comp = DateComponents()
            comp.year = year
            comp.month = month
            comp.day = 1
            monthKey = String(format: "%d-%02d", year, month)
            monthLabel = (Calendar.current.date(from: comp).map { formatter.string(from: $0) }) ?? "\(month)/\(year)"

            let transactions = LocalDataStore.shared.fetchTransactions(limit: 500, month: monthStr, year: yearStr)
            let nonSubExpenseMerchants = Set(transactions.filter { $0.type.lowercased() != "income" && $0.isSubscription != true }.map { $0.merchant ?? "" })
            let expenseOnly = transactions.filter { tx in
                guard tx.type.lowercased() != "income" else { return false }
                if tx.isSubscription != true { return true }
                return !nonSubExpenseMerchants.contains(tx.merchant ?? "")
            }
            totalSpent = expenseOnly.reduce(0) { acc, tx in
                acc + CurrencyService.amountInBase(amountOriginal: abs(tx.amountOriginal), currencyOriginal: tx.currencyOriginal, amountBase: tx.amountBase, baseCurrency: tx.baseCurrency)
            }

            var byCat: [String: Double] = [:]
            var byCatTx: [String: [Transaction]] = [:]
            for tx in expenseOnly {
                let inBase = CurrencyService.amountInBase(amountOriginal: abs(tx.amountOriginal), currencyOriginal: tx.currencyOriginal, amountBase: tx.amountBase, baseCurrency: tx.baseCurrency)
                byCat[tx.category, default: 0] += inBase
                byCatTx[tx.category, default: []].append(tx)
            }
            for (cat, list) in byCatTx {
                byCatTx[cat] = list.sorted { $0.transactionDate > $1.transactionDate }
            }

            let sorted = byCat.sorted { $0.value > $1.value }
            guard totalSpent > 0 else {
                segments = []
                transactionsByCategory = [:]
                return
            }

            let n = sorted.count
            let fillRatio: Double = {
                switch n {
                case 1: return 1.0
                case 2: return 0.85
                case 3: return 0.75
                case 4: return 0.70
                case 5: return 0.60
                default: return 0.40
                }
            }()
            let usableAngle: Double = 360 * fillRatio
            let gapAngle: Double = n > 1 ? (360 - usableAngle) / Double(n) : 0

            var currentAngle: Double = 0
            let newSegments = Array(sorted.enumerated().map { i, pair in
                let normalizedValue = pair.value / totalSpent
                let segmentAngle = usableAngle * normalizedValue
                let start = currentAngle
                let end = start + segmentAngle
                currentAngle = end + gapAngle
                let cat = CategoryStore.byId(pair.key)
                let label = cat?.name ?? pair.key.capitalized
                let color = cat?.color ?? fallbackColors[i % fallbackColors.count]
                let colorHex = cat?.colorHex ?? color.toHex()
                let icon = categoryIconName(pair.key)
                return CategorySegment(
                    id: pair.key,
                    categoryId: pair.key,
                    label: label,
                    amount: pair.value,
                    ratio: CGFloat(normalizedValue),
                    percent: normalizedValue * 100,
                    color: color,
                    colorHex: colorHex,
                    iconName: icon,
                    startAngle: .degrees(start),
                    endAngle: .degrees(end)
                )
            })
            withAnimation(.easeInOut(duration: 0.35)) {
                segments = newSegments
                transactionsByCategory = byCatTx
            }
        }
    }

    private func categoryIconName(_ categoryId: String) -> String {
        CategoryIconHelper.iconName(categoryId: categoryId)
    }
}

#Preview {
    NavigationStack {
        CategoryBreakdownView()
    }
}
