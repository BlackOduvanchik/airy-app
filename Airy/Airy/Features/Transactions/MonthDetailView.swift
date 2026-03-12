//
//  MonthDetailView.swift
//  Airy
//
//  When user selects a month: calendar with days that have spending highlighted, list of transactions by day.
//

import SwiftUI

struct MonthDetailView: View {
    let monthKey: String
    let monthLabel: String
    @Binding var monthPath: [MonthDetailDestination]
    @State private var viewModel: MonthDetailViewModel
    @State private var showCalendarPicker = false
    @Environment(\.dismiss) private var dismiss

    init(monthKey: String, monthLabel: String, monthPath: Binding<[MonthDetailDestination]> = .constant([])) {
        self.monthKey = monthKey
        self.monthLabel = monthLabel
        _monthPath = monthPath
        _viewModel = State(initialValue: MonthDetailViewModel(monthKey: monthKey, monthLabel: monthLabel))
    }

    var body: some View {
        contentView(viewModel: viewModel)
            .background(OnboardingGradientBackground())
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(OnboardingDesign.textPrimary)
                            .frame(width: 44, height: 44)
                            .background(OnboardingDesign.glassBg)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(OnboardingDesign.glassBorder, lineWidth: 1))
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(monthLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(OnboardingDesign.textPrimary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 18))
                            .foregroundColor(OnboardingDesign.textPrimary)
                            .frame(width: 44, height: 44)
                    }
                }
            }
            .fullScreenCover(isPresented: $showCalendarPicker) {
                CalendarPickerSheetView(
                    monthKey: monthKey,
                    monthLabel: monthLabel,
                    onSelect: { dest, _ in
                        showCalendarPicker = false
                        monthPath = [dest]
                    },
                    onCancel: { showCalendarPicker = false }
                )
            }
            .task { await viewModel.load() }
    }

    private func contentView(viewModel: MonthDetailViewModel) -> some View {
        Group {
            if viewModel.isLoading && viewModel.transactions.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 60)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        billSummarySection(total: viewModel.totalSpent)
                        calendarSection(viewModel: viewModel)
                        billListSection(viewModel: viewModel)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 120)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    // MARK: - Bill summary

    private func billSummarySection(total: Double) -> some View {
        VStack(spacing: 4) {
            Text("Spent this month")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(OnboardingDesign.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(formatCurrencyWhole(total))
                    .font(.system(size: 36, weight: .light))
                    .tracking(-1)
                    .foregroundColor(OnboardingDesign.textPrimary)
                Text(formatCents(total))
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(OnboardingDesign.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.bottom, 8)
    }

    // MARK: - Calendar

    private func calendarSection(viewModel: MonthDetailViewModel) -> some View {
        let calendarDays = buildCalendarDays(monthKey: monthKey, daysWithActivity: viewModel.daysWithTransactions)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("SPENDING CALENDAR")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(OnboardingDesign.textTertiary)
                Spacer()
                Text("\(viewModel.transactions.count) \(viewModel.transactions.count == 1 ? "Transaction" : "Transactions")")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(OnboardingDesign.accentGreen)
            }
            .padding(.horizontal, 4)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"], id: \.self) { label in
                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(OnboardingDesign.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 8)
                }
                ForEach(calendarDays, id: \.offset) { item in
                    if let day = item.day {
                        let hasActivity = item.hasActivity
                        let isPrevMonth = item.isPrevMonth
                        ZStack(alignment: .bottom) {
                            Text("\(day)")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(isPrevMonth ? OnboardingDesign.textTertiary : OnboardingDesign.textPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 36)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.clear)
                                )
                            if hasActivity {
                                Circle()
                                    .fill(OnboardingDesign.accentGreen)
                                    .frame(width: 4, height: 4)
                                    .padding(.bottom, 4)
                            }
                        }
                    } else {
                        Color.clear
                            .frame(minHeight: 36)
                    }
                }
            }
            .padding(.top, 20)
        }
        .padding(24)
        .modifier(MonthDetailGlassModifier())
        .contentShape(Rectangle())
        .onTapGesture {
            showCalendarPicker = true
        }
    }

    /// Builds (day number or nil, hasActivity, isPrevMonth) for the month grid. Sunday first (Su Mo Tu We Th Fr Sa).
    private func buildCalendarDays(monthKey: String, daysWithActivity: Set<Int>) -> [(offset: Int, day: Int?, hasActivity: Bool, isPrevMonth: Bool)] {
        let parts = monthKey.split(separator: "-")
        guard parts.count >= 2,
              let y = Int(parts[0]),
              let m = Int(parts[1]) else { return [] }
        var cal = Calendar.current
        cal.firstWeekday = 1
        var comp = DateComponents()
        comp.year = y
        comp.month = m
        comp.day = 1
        guard let first = cal.date(from: comp),
              let range = cal.range(of: .day, in: .month, for: first) else { return [] }
        let lastDay = range.count
        let weekday = cal.component(.weekday, from: first)
        let startOffset = weekday - 1
        var result: [(Int, Int?, Bool, Bool)] = []
        if startOffset > 0, let prevMonth = cal.date(byAdding: .month, value: -1, to: first),
           let prevRange = cal.range(of: .day, in: .month, for: prevMonth) {
            let prevLastDay = prevRange.count
            for i in 0..<startOffset {
                let d = prevLastDay - startOffset + i + 1
                result.append((result.count, d, false, true))
            }
        } else {
            for _ in 0..<startOffset {
                result.append((result.count, nil, false, false))
            }
        }
        for d in 1...lastDay {
            result.append((result.count, d, daysWithActivity.contains(d), false))
        }
        let totalCells = startOffset + lastDay
        let remainder = totalCells % 7
        if remainder > 0 {
            let nextMonthCount = 7 - remainder
            for i in 1...nextMonthCount {
                result.append((result.count, i, false, true))
            }
        }
        return result.map { ($0.0, $0.1, $0.2, $0.3) }
    }

    // MARK: - Bill list

    private func billListSection(viewModel: MonthDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.transactions.isEmpty {
                Text("No transactions this month")
                    .font(.system(size: 14))
                    .foregroundColor(OnboardingDesign.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ForEach(Array(viewModel.transactions.enumerated()), id: \.element.id) { index, tx in
                    NavigationLink(value: tx) {
                        billRow(transaction: tx)
                    }
                    .buttonStyle(.plain)
                    if index < viewModel.transactions.count - 1 {
                        Divider()
                            .background(Color.white.opacity(0.3))
                            .padding(.leading, 56)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 20)
        .modifier(MonthDetailGlassModifier())
    }

    private func billRow(transaction: Transaction) -> some View {
        let iconName = transactionIconName(transaction)
        let (iconBg, iconFg) = transactionIconColors(transaction)
        return HStack(alignment: .center, spacing: 16) {
            RoundedRectangle(cornerRadius: 12)
                .fill(iconBg)
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: iconName)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(iconFg)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.merchant ?? "Unknown")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(OnboardingDesign.textPrimary)
                Text(subtitleForTransaction(transaction))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(OnboardingDesign.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(formatAmount(transaction.amountOriginal, transaction.currencyOriginal))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(OnboardingDesign.textPrimary)
        }
        .padding(.vertical, 16)
    }

    private func transactionIconName(_ tx: Transaction) -> String {
        if tx.isSubscription == true { return "creditcard.fill" }
        let c = tx.category.lowercased()
        if c.contains("food") || c.contains("dining") { return "cup.and.saucer.fill" }
        if c.contains("transport") || c.contains("transit") { return "car.fill" }
        if c.contains("shopping") { return "bag.fill" }
        if c.contains("health") { return "heart.fill" }
        return "dollarsign"
    }

    private func transactionIconColors(_ tx: Transaction) -> (Color, Color) {
        if tx.isSubscription == true {
            return (OnboardingDesign.accentWarning.opacity(0.2), OnboardingDesign.accentWarning)
        }
        let c = tx.category.lowercased()
        if c.contains("food") || c.contains("dining") {
            return (OnboardingDesign.accentGreen.opacity(0.2), OnboardingDesign.accentGreen)
        }
        if c.contains("shopping") {
            return (OnboardingDesign.accentBlue.opacity(0.2), OnboardingDesign.accentBlue)
        }
        if c.contains("transport") || c.contains("transit") {
            return (Color(red: 0.886, green: 0.871, blue: 0.808).opacity(0.6), OnboardingDesign.textSecondary)
        }
        return (Color.white.opacity(0.6), OnboardingDesign.textSecondary)
    }

    private func subtitleForTransaction(_ tx: Transaction) -> String {
        let dateStr = String(tx.transactionDate.prefix(10))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        guard let d = formatter.date(from: dateStr) else { return tx.transactionDate }
        let out = DateFormatter()
        out.dateFormat = "MMM d"
        var sub = out.string(from: d)
        if let note = tx.title, !note.isEmpty {
            sub += " • \(note)"
        } else if tx.isSubscription == true {
            sub += " • Auto-pay"
        }
        return sub
    }

    private func formatCurrencyWhole(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }

    private func formatCents(_ value: Double) -> String {
        let cents = Int((value.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: ".%02d", abs(cents))
    }

    private func formatAmount(_ amount: Double, _ currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount) \(currency)"
    }
}

// MARK: - Glass modifier

private struct MonthDetailGlassModifier: ViewModifier {
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
    NavigationStack {
        MonthDetailView(monthKey: "2025-10", monthLabel: "October 2025")
    }
}
