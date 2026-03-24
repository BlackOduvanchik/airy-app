//
//  MonthDetailView.swift
//  Airy
//
//  When user selects a month: calendar with days that have spending highlighted, list of transactions by day.
//

import SwiftUI

struct MonthDetailView: View {
    @Environment(ThemeProvider.self) private var theme
    let monthKey: String
    let monthLabel: String
    @Binding var monthPath: [MonthDetailDestination]
    @State private var viewModel: MonthDetailViewModel
    @State private var showCalendarPicker = false
    @State private var showEditSheet = false
    @State private var selectedTransactionForEdit: Transaction? = nil
    @State private var filterStartDay: Int? = nil
    @State private var filterEndDay: Int? = nil
    @Environment(\.dismiss) private var dismiss

    init(monthKey: String, monthLabel: String, monthPath: Binding<[MonthDetailDestination]> = .constant([])) {
        self.monthKey = monthKey
        self.monthLabel = monthLabel
        _monthPath = monthPath
        _viewModel = State(initialValue: MonthDetailViewModel(monthKey: monthKey, monthLabel: monthLabel))
    }

    /// Transactions filtered by the selected day range (if any).
    private var displayedTransactions: [Transaction] {
        guard let start = filterStartDay else { return viewModel.transactions }
        let lo = min(start, filterEndDay ?? start)
        let hi = max(start, filterEndDay ?? start)
        return viewModel.transactions.filter { tx in
            let dateStr = String(tx.transactionDate.prefix(10))
            guard let date = AppFormatters.inputDate.date(from: dateStr) else { return false }
            let day = Calendar.current.component(.day, from: date)
            return day >= lo && day <= hi
        }
    }

    private var displayedTotal: Double {
        displayedTransactions
            .filter { $0.type.lowercased() != "income" }
            .reduce(0) { acc, tx in
                acc + CurrencyService.amountInBase(amountOriginal: abs(tx.amountOriginal), currencyOriginal: tx.currencyOriginal, amountBase: tx.amountBase, baseCurrency: tx.baseCurrency)
            }
    }

    var body: some View {
        contentView()
            .background(OnboardingGradientBackground())
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
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
                    Text(viewModel.monthLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(theme.textTertiary)
                }
            }
            .fullScreenCover(isPresented: $showCalendarPicker) {
                CalendarPickerSheetView(
                    monthKey: viewModel.monthKey,
                    monthLabel: viewModel.monthLabel,
                    onSelect: { dest, startDay, endDay in
                        showCalendarPicker = false
                        if dest.monthKey != viewModel.monthKey {
                            viewModel.monthKey = dest.monthKey
                            viewModel.monthLabel = dest.monthLabel
                            filterStartDay = startDay
                            filterEndDay = endDay
                            Task { await viewModel.load() }
                        } else {
                            filterStartDay = startDay
                            filterEndDay = endDay
                        }
                    },
                    onCancel: { showCalendarPicker = false }
                )
                .themed(theme)
            }
            .sheet(isPresented: $showEditSheet, onDismiss: {
                selectedTransactionForEdit = nil
            }) {
                if let tx = selectedTransactionForEdit {
                    AddTransactionView(transaction: tx, onSuccess: {
                        showEditSheet = false
                        Task { await viewModel.load() }
                    })
                    .themed(theme)
                }
            }
            .task { await viewModel.load() }
    }

    private func contentView() -> some View {
        Group {
            if viewModel.isLoading && viewModel.transactions.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 60)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        billSummarySection(total: filterStartDay != nil ? displayedTotal : viewModel.totalSpent)
                        calendarSection()
                        if filterStartDay != nil {
                            clearFilterChip
                        }
                        billListSection()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 120)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var clearFilterChip: some View {
        Button {
            filterStartDay = nil
            filterEndDay = nil
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                let label: String = {
                    guard let s = filterStartDay else { return "" }
                    if let e = filterEndDay, e != s {
                        return "Showing \(min(s, e))–\(max(s, e))"
                    }
                    return "Showing day \(s)"
                }()
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(theme.accentGreen)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(theme.accentGreen.opacity(0.12))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bill summary

    private func billSummarySection(total: Double) -> some View {
        VStack(spacing: 4) {
            Text(L("month_spent"))
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(theme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(formatCurrencyWhole(total))
                    .font(.system(size: 36, weight: .light))
                    .tracking(-1)
                    .foregroundColor(theme.textPrimary)
                Text(formatCents(total))
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.bottom, 8)
    }

    // MARK: - Calendar

    private func calendarSection() -> some View {
        let calendarDays = buildCalendarDays(monthKey: viewModel.monthKey, daysWithActivity: viewModel.daysWithTransactions)
        let txCount = displayedTransactions.count
        return Button {
            showCalendarPicker = true
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(L("month_calendar"))
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(theme.textTertiary)
                    Spacer()
                    Text("\(txCount) \(txCount == 1 ? L("month_transaction") : L("month_transactions"))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(theme.accentGreen)
                }
                .padding(.horizontal, 4)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                    ForEach(["month_su", "month_mo", "month_tu", "month_we", "month_th", "month_fr", "month_sa"], id: \.self) { key in
                        Text(L(key))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(theme.textTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 8)
                    }
                    ForEach(calendarDays, id: \.offset) { item in
                        if let day = item.day {
                            let hasActivity = item.hasActivity
                            let isPrevMonth = item.isPrevMonth
                            let rangeState = inlineCalendarRangeState(day: day, isPrevMonth: isPrevMonth)
                            let isEndpoint = rangeState == .start || rangeState == .end
                            let isInRange = rangeState == .inRange
                            ZStack(alignment: .bottom) {
                                Text("\(day)")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(isEndpoint ? .white : isInRange ? theme.accentGreen : isPrevMonth ? theme.textTertiary : theme.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .frame(minHeight: 36)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(isEndpoint ? theme.accentGreen : isInRange ? theme.accentGreen.opacity(0.12) : Color.clear)
                                    )
                                if hasActivity && !isEndpoint {
                                    let dotColor = isDayInFuture(day: day, monthKey: viewModel.monthKey)
                                        ? theme.accentAmber
                                        : theme.accentGreen
                                    Circle()
                                        .fill(dotColor)
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
        }
        .buttonStyle(.plain)
    }

    private enum InlineRangeState { case none, start, end, inRange }

    private func inlineCalendarRangeState(day: Int, isPrevMonth: Bool) -> InlineRangeState {
        guard !isPrevMonth, let start = filterStartDay else { return .none }
        let lo = min(start, filterEndDay ?? start)
        let hi = max(start, filterEndDay ?? start)
        if day == lo { return .start }
        if day == hi && lo != hi { return .end }
        if day > lo && day < hi { return .inRange }
        return .none
    }

    private func isDayInFuture(day: Int, monthKey: String) -> Bool {
        let parts = monthKey.split(separator: "-")
        guard parts.count >= 2,
              let y = Int(parts[0]),
              let m = Int(parts[1]) else { return false }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var comp = DateComponents()
        comp.year = y
        comp.month = m
        comp.day = day
        guard let cellDate = cal.date(from: comp) else { return false }
        return cellDate > today
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

    private func billListSection() -> some View {
        let txList = displayedTransactions
        return VStack(alignment: .leading, spacing: 0) {
            if txList.isEmpty {
                Text(filterStartDay != nil ? L("month_no_selected") : L("month_no_this"))
                    .font(.system(size: 14))
                    .foregroundColor(theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ForEach(Array(txList.enumerated()), id: \.element.id) { index, tx in
                    Button {
                        selectedTransactionForEdit = tx
                        showEditSheet = true
                    } label: {
                        billRow(transaction: tx)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    if index < txList.count - 1 {
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
                Text(CategoryIconHelper.transactionDisplayName(merchant: transaction.merchant, subcategory: transaction.subcategory, categoryId: transaction.category))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(theme.textPrimary)
                Text(subtitleForTransaction(transaction))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(theme.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(AppFormatters.formatTransaction(amount: transaction.amountOriginal, currency: transaction.currencyOriginal, isIncome: transaction.type.lowercased() == "income"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(transaction.type.lowercased() == "income" ? theme.incomeColor : theme.expenseColor)
        }
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }

    private func transactionIconName(_ tx: Transaction) -> String {
        tx.isSubscription == true ? CategoryIconHelper.subscriptionIconName() : CategoryIconHelper.iconName(categoryId: tx.category, subcategoryId: tx.subcategory)
    }

    private func transactionIconColors(_ tx: Transaction) -> (Color, Color) {
        CategoryIconHelper.iconColors(categoryId: tx.category, subcategoryId: tx.subcategory, isSubscription: tx.isSubscription == true)
    }

    private func subtitleForTransaction(_ tx: Transaction) -> String {
        let dateStr = String(tx.transactionDate.prefix(10))
        guard let d = AppFormatters.inputDate.date(from: dateStr) else { return tx.transactionDate }
        var sub = AppFormatters.shortMonthDay.string(from: d)
        if let note = tx.title, !note.isEmpty {
            sub += " • \(note)"
        } else if tx.isSubscription == true {
            sub += " • Auto-pay"
        }
        return sub
    }

    private func formatCurrencyWhole(_ value: Double) -> String {
        AppFormatters.formatTotalWhole(amount: value, currency: BaseCurrencyStore.baseCurrency)
    }

    private func formatCents(_ value: Double) -> String {
        AppFormatters.formatTotalCents(value)
    }

    private func formatAmount(_ amount: Double, _ currency: String) -> String {
        AppFormatters.formatTotal(amount: amount, currency: currency)
    }
}

// MARK: - Glass modifier

private struct MonthDetailGlassModifier: ViewModifier {
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
    NavigationStack {
        MonthDetailView(monthKey: "2025-10", monthLabel: "October 2025")
    }
}
