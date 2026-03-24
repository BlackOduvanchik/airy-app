//
//  CalendarPickerSheetView.swift
//  Airy
//
//  Full-screen calendar picker: swipe months/years, select day range or month, highlights days with transactions.
//

import SwiftUI

struct CalendarPickerSheetView: View {
    @Environment(ThemeProvider.self) private var theme
    let initialMonthKey: String
    let initialMonthLabel: String
    let onSelect: (MonthDetailDestination, Int?, Int?) -> Void   // (dest, startDay, endDay)
    let onCancel: () -> Void

    @State private var currentYear: Int
    @State private var currentMonth: Int
    @State private var rangeStart: Int? = nil
    @State private var rangeEnd: Int? = nil
    @State private var daysWithTransactions: Set<Int> = []
    @State private var isLoading = false
    @State private var showMonthYearPicker = false

    // Month/year picker state
    @State private var pickerMonth: Int
    @State private var pickerYear: Int
    private static let minYear = 2020
    private static var maxYear: Int { Calendar.current.component(.year, from: Date()) + 2 }

    private var currentMonthKey: String {
        String(format: "%d-%02d", currentYear, currentMonth)
    }

    private var currentMonthLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        var comp = DateComponents()
        comp.year = currentYear
        comp.month = currentMonth
        comp.day = 1
        guard let date = Calendar.current.date(from: comp) else { return "\(currentMonth)/\(currentYear)" }
        return formatter.string(from: date)
    }

    init(monthKey: String, monthLabel: String, onSelect: @escaping (MonthDetailDestination, Int?, Int?) -> Void, onCancel: @escaping () -> Void) {
        self.initialMonthKey = monthKey
        self.initialMonthLabel = monthLabel
        self.onSelect = onSelect
        self.onCancel = onCancel
        let parts = monthKey.split(separator: "-")
        let y = parts.count >= 1 ? Int(parts[0]) ?? Calendar.current.component(.year, from: Date()) : Calendar.current.component(.year, from: Date())
        let m = parts.count >= 2 ? Int(parts[1]) ?? Calendar.current.component(.month, from: Date()) : Calendar.current.component(.month, from: Date())
        _currentYear = State(initialValue: y)
        _currentMonth = State(initialValue: m)
        _pickerMonth = State(initialValue: m)
        _pickerYear = State(initialValue: y)
    }

    var body: some View {
        ZStack {
            OnboardingGradientBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                calendarContent
                Spacer(minLength: 0)
                actionButtons
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 40)

        }
        .task(id: "\(currentYear)-\(currentMonth)") { await loadDaysWithTransactions() }
    }

    // MARK: - Calendar content

    private var calendarContent: some View {
        VStack(spacing: 24) {
            headerRow
            calendarGrid
        }
        .padding(24)
        .background(theme.isDark ? AnyShapeStyle(theme.glassBg) : AnyShapeStyle(.ultraThinMaterial))
        .overlay(theme.isDark ? nil : theme.glassBg.opacity(0.5).allowsHitTesting(false))
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(theme.glassBorder, lineWidth: 1)
                .allowsHitTesting(false)
        )
        .shadow(color: theme.textPrimary.opacity(0.06), radius: 16, x: 0, y: 8)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Button { prevMonth() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(theme.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(theme.isDark ? 0.08 : 0.3))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            // Tappable month/year label → opens wheel picker popover
            Button {
                pickerMonth = currentMonth
                pickerYear = currentYear
                showMonthYearPicker = true
            } label: {
                HStack(spacing: 4) {
                    Text(currentMonthLabel)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(theme.textPrimary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(theme.textTertiary)
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showMonthYearPicker, arrowEdge: .top) {
                monthYearPickerPopover
                    .presentationCompactAdaptation(.popover)
            }

            Spacer()

            Button { nextMonth() } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(theme.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(theme.isDark ? 0.08 : 0.3))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Calendar grid

    private var calendarGrid: some View {
        let calendarDays = buildCalendarDays()
        let today = Calendar.current.component(.day, from: Date())
        let todayMonth = Calendar.current.component(.month, from: Date())
        let todayYear = Calendar.current.component(.year, from: Date())
        let isCurrentMonth = currentYear == todayYear && currentMonth == todayMonth

        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
            ForEach(["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"], id: \.self) { label in
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 4)
            }
            ForEach(calendarDays, id: \.offset) { item in
                if let day = item.day {
                    let hasActivity = item.hasActivity
                    let isPrevNext = item.isPrevMonth
                    let rangeState = dayRangeState(day: day, isPrevNext: isPrevNext)
                    let isToday = isCurrentMonth && day == today && !isPrevNext
                    dayCell(day: day, hasActivity: hasActivity, isPrevNext: isPrevNext, rangeState: rangeState, isToday: isToday)
                } else {
                    Color.clear
                        .frame(minHeight: 40)
                }
            }
        }
    }

    // MARK: - Range state

    private enum DayRangeState {
        case none, start, end, inRange
    }

    private func dayRangeState(day: Int, isPrevNext: Bool) -> DayRangeState {
        guard !isPrevNext else { return .none }
        guard let start = rangeStart else { return .none }

        if let end = rangeEnd {
            let lo = min(start, end)
            let hi = max(start, end)
            if day == lo { return .start }
            if day == hi { return .end }
            if day > lo && day < hi { return .inRange }
            return .none
        } else {
            return day == start ? .start : .none
        }
    }

    // MARK: - Day cell

    private func dayCell(day: Int, hasActivity: Bool, isPrevNext: Bool, rangeState: DayRangeState, isToday: Bool) -> some View {
        let isEndpoint = rangeState == .start || rangeState == .end
        let isInRange = rangeState == .inRange

        return Button {
            if !isPrevNext { handleDayTap(day) }
        } label: {
            ZStack(alignment: .bottom) {
                Text("\(day)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(dayForeground(isPrevNext: isPrevNext, isEndpoint: isEndpoint, isInRange: isInRange, isToday: isToday))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(dayBackground(isEndpoint: isEndpoint, isInRange: isInRange, isToday: isToday))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isToday && !isEndpoint ? theme.accentGreen : Color.clear, lineWidth: 1.5)
                    )
                    .shadow(color: isEndpoint ? theme.accentGreen.opacity(0.3) : .clear, radius: 6, x: 0, y: 4)
                if hasActivity && !isEndpoint {
                    let dotColor = isDayInFuture(day: day)
                        ? theme.accentAmber
                        : theme.accentGreen
                    Circle()
                        .fill(dotColor)
                        .frame(width: 4, height: 4)
                        .padding(.bottom, 4)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isPrevNext)
    }

    private func dayForeground(isPrevNext: Bool, isEndpoint: Bool, isInRange: Bool, isToday: Bool) -> Color {
        if isEndpoint { return .white }
        if isInRange { return theme.accentGreen }
        if isPrevNext { return theme.textTertiary.opacity(0.5) }
        if isToday { return theme.accentGreen }
        return theme.textPrimary
    }

    private func dayBackground(isEndpoint: Bool, isInRange: Bool, isToday: Bool) -> Color {
        if isEndpoint { return theme.accentGreen }
        if isInRange { return theme.accentGreen.opacity(0.12) }
        return Color.clear
    }

    // MARK: - Tap logic

    private func handleDayTap(_ day: Int) {
        if rangeStart == nil {
            // First tap: set start
            rangeStart = day
            rangeEnd = nil
        } else if rangeEnd == nil {
            // Second tap: set end (or swap if before start)
            if day == rangeStart {
                // Tapped same day again — keep single selection
                return
            }
            rangeEnd = day
        } else {
            // Third tap: reset to new start
            rangeStart = day
            rangeEnd = nil
        }
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                // Select whole month
                rangeStart = nil
                rangeEnd = nil
                confirmSelection()
            } label: {
                Text("Select whole month")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(theme.accentGreen)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            HStack(spacing: 12) {
                Button { onCancel() } label: {
                    Text("Cancel")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.white.opacity(theme.isDark ? 0.08 : 0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)

                Button { confirmSelection() } label: {
                    Text(buttonLabel)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(theme.isDark ? Color.white.opacity(0.15) : theme.accentGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 24)
    }

    private var buttonLabel: String {
        if rangeStart != nil && rangeEnd != nil { return "Select Range" }
        if rangeStart != nil { return "Select Date" }
        return "Select Date"
    }

    // MARK: - Month/Year picker popover (native wheel style)

    private var monthYearPickerPopover: some View {
        HStack(spacing: 0) {
            Picker("", selection: $pickerMonth) {
                ForEach(1...12, id: \.self) { m in
                    Text(Calendar.current.monthSymbols[m - 1]).tag(m)
                }
            }
            .pickerStyle(.wheel)
            .frame(width: 140)

            Picker("", selection: $pickerYear) {
                ForEach(Self.minYear...Self.maxYear, id: \.self) { y in
                    Text(String(y)).tag(y)
                }
            }
            .pickerStyle(.wheel)
            .frame(width: 90)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .onChange(of: pickerMonth) { _, newMonth in
            if newMonth != currentMonth || pickerYear != currentYear {
                currentMonth = newMonth
                currentYear = pickerYear
                rangeStart = nil
                rangeEnd = nil
            }
        }
        .onChange(of: pickerYear) { _, newYear in
            if pickerMonth != currentMonth || newYear != currentYear {
                currentMonth = pickerMonth
                currentYear = newYear
                rangeStart = nil
                rangeEnd = nil
            }
        }
    }

    // MARK: - Navigation

    private func prevMonth() {
        if currentMonth == 1 {
            currentYear -= 1
            currentMonth = 12
        } else {
            currentMonth -= 1
        }
        rangeStart = nil
        rangeEnd = nil
    }

    private func nextMonth() {
        if currentMonth == 12 {
            currentYear += 1
            currentMonth = 1
        } else {
            currentMonth += 1
        }
        rangeStart = nil
        rangeEnd = nil
    }

    // MARK: - Confirm

    private func confirmSelection() {
        let dest = MonthDetailDestination(monthKey: currentMonthKey, monthLabel: currentMonthLabel)
        let start: Int? = rangeStart
        let end: Int? = rangeEnd
        onSelect(dest, start, end)
    }

    // MARK: - Data loading

    private func loadDaysWithTransactions() async {
        let monthStr = String(format: "%02d", currentMonth)
        let yearStr = String(currentYear)
        let txList = LocalDataStore.shared.fetchTransactions(limit: 200, month: monthStr, year: yearStr)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        var set: Set<Int> = []
        for tx in txList {
            let dateStr = String(tx.transactionDate.prefix(10))
            guard let date = formatter.date(from: dateStr) else { continue }
            let day = Calendar.current.component(.day, from: date)
            set.insert(day)
        }
        await MainActor.run { daysWithTransactions = set }
    }

    private func isDayInFuture(day: Int) -> Bool {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var comp = DateComponents()
        comp.year = currentYear
        comp.month = currentMonth
        comp.day = day
        guard let cellDate = cal.date(from: comp) else { return false }
        return cellDate > today
    }

    // MARK: - Calendar builder

    private func buildCalendarDays() -> [(offset: Int, day: Int?, hasActivity: Bool, isPrevMonth: Bool)] {
        var cal = Calendar.current
        cal.firstWeekday = 1
        var comp = DateComponents()
        comp.year = currentYear
        comp.month = currentMonth
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
            result.append((result.count, d, daysWithTransactions.contains(d), false))
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
}
