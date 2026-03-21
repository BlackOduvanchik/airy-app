//
//  CalendarPickerSheetView.swift
//  Airy
//
//  Full-screen calendar picker: swipe months/years, select day range or month, highlights days with transactions.
//

import SwiftUI

// MARK: - Wheel snap behavior (reused from DatePickerPopoverView)

private struct CalendarWheelSnap: ScrollTargetBehavior {
    let rowHeight: CGFloat = 32
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let proposed = target.rect.origin.y
        let snapped = round(proposed / rowHeight) * rowHeight
        target.rect.origin.y = snapped
    }
}

private let calMonthNames = ["January", "February", "March", "April", "May", "June",
                              "July", "August", "September", "October", "November", "December"]

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

    // Month/year wheel state
    @State private var pickerMonthIndex: Int
    @State private var pickerYearIndex: Int
    @State private var pickerMonthScrollId: Int?
    @State private var pickerYearScrollId: Int?
    private static var yearRange: [Int] {
        let y = Calendar.current.component(.year, from: Date())
        return Array(2020...(y + 2))
    }

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
        _pickerMonthIndex = State(initialValue: m - 1)
        _pickerYearIndex = State(initialValue: Self.yearRange.firstIndex(of: y) ?? 0)
        _pickerMonthScrollId = State(initialValue: m - 1)
        _pickerYearScrollId = State(initialValue: Self.yearRange.firstIndex(of: y) ?? 0)
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

            // Month/Year picker overlay
            if showMonthYearPicker {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { applyMonthYearPicker() }

                monthYearPickerPopup
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.9)).combined(with: .offset(y: -10)),
                        removal: .opacity
                    ))
            }
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

            // Tappable month/year label → opens wheel picker
            Button {
                pickerMonthIndex = currentMonth - 1
                pickerMonthScrollId = currentMonth - 1
                pickerYearIndex = Self.yearRange.firstIndex(of: currentYear) ?? 0
                pickerYearScrollId = Self.yearRange.firstIndex(of: currentYear) ?? 0
                withAnimation(.easeOut(duration: 0.25)) { showMonthYearPicker = true }
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

    // MARK: - Month/Year wheel picker popup

    private let wheelRowHeight: CGFloat = 32
    private let wheelVisibleHeight: CGFloat = 120

    private var monthYearPickerPopup: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .center) {
                // Selection highlight
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(theme.isDark ? 0.08 : 0.4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(theme.isDark ? 0.10 : 0.5), lineWidth: 1)
                    )
                    .frame(height: 34)
                    .allowsHitTesting(false)

                HStack(spacing: 0) {
                    // Month wheel
                    monthWheel
                    Rectangle()
                        .fill(theme.isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.05))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                    // Year wheel
                    yearWheel
                }
                .frame(height: wheelVisibleHeight)
            }

            Button {
                applyMonthYearPicker()
            } label: {
                Text("Done")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(theme.isDark ? Color.white.opacity(0.15) : theme.accentGreen)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .frame(width: 220)
        .padding(16)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(theme.isDark ? AnyShapeStyle(theme.glassBg) : AnyShapeStyle(.ultraThinMaterial))
                if !theme.isDark {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.white.opacity(0.5))
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(theme.glassBorder, lineWidth: 1)
        )
        .shadow(color: Color(red: 0.118, green: 0.176, blue: 0.141).opacity(0.08), radius: 16, x: 0, y: 8)
    }

    private var monthWheel: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(0..<12, id: \.self) { i in
                    Text(calMonthNames[i])
                        .font(.system(size: pickerMonthIndex == i ? 18 : 16, weight: pickerMonthIndex == i ? .bold : .medium))
                        .foregroundColor(pickerMonthIndex == i ? theme.textPrimary : theme.textTertiary)
                        .frame(height: wheelRowHeight)
                        .frame(maxWidth: .infinity)
                        .id(i)
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.2)) {
                                pickerMonthScrollId = i
                                pickerMonthIndex = i
                            }
                        }
                }
            }
            .padding(.vertical, (wheelVisibleHeight - wheelRowHeight) / 2)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(CalendarWheelSnap())
        .scrollPosition(id: $pickerMonthScrollId, anchor: .center)
        .scrollViewNoBounce()
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.35),
                    .init(color: .black, location: 0.65),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .frame(maxWidth: .infinity)
        .onChange(of: pickerMonthScrollId) { _, id in
            if let id { pickerMonthIndex = id }
        }
    }

    private var yearWheel: some View {
        let years = Self.yearRange
        return ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(0..<years.count, id: \.self) { i in
                    Text(String(years[i]))
                        .font(.system(size: pickerYearIndex == i ? 18 : 16, weight: pickerYearIndex == i ? .bold : .medium))
                        .foregroundColor(pickerYearIndex == i ? theme.textPrimary : theme.textTertiary)
                        .frame(height: wheelRowHeight)
                        .frame(maxWidth: .infinity)
                        .id(i)
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.2)) {
                                pickerYearScrollId = i
                                pickerYearIndex = i
                            }
                        }
                }
            }
            .padding(.vertical, (wheelVisibleHeight - wheelRowHeight) / 2)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(CalendarWheelSnap())
        .scrollPosition(id: $pickerYearScrollId, anchor: .center)
        .scrollViewNoBounce()
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.35),
                    .init(color: .black, location: 0.65),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .frame(maxWidth: .infinity)
        .onChange(of: pickerYearScrollId) { _, id in
            if let id { pickerYearIndex = id }
        }
    }

    private func applyMonthYearPicker() {
        withAnimation(.easeOut(duration: 0.25)) { showMonthYearPicker = false }
        let newMonth = pickerMonthIndex + 1
        let newYear = Self.yearRange[pickerYearIndex]
        if newMonth != currentMonth || newYear != currentYear {
            currentMonth = newMonth
            currentYear = newYear
            rangeStart = nil
            rangeEnd = nil
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
