//
//  CalendarPickerSheetView.swift
//  Airy
//
//  Full-screen calendar picker: swipe months/years, select day or month, highlights days with transactions.
//

import SwiftUI

struct CalendarPickerSheetView: View {
    let initialMonthKey: String
    let initialMonthLabel: String
    let onSelect: (MonthDetailDestination, Int?) -> Void
    let onCancel: () -> Void

    @State private var currentYear: Int
    @State private var currentMonth: Int
    @State private var selectedDay: Int?
    @State private var selectWholeMonth: Bool = false
    @State private var daysWithTransactions: Set<Int> = []
    @State private var isLoading = false

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

    init(monthKey: String, monthLabel: String, onSelect: @escaping (MonthDetailDestination, Int?) -> Void, onCancel: @escaping () -> Void) {
        self.initialMonthKey = monthKey
        self.initialMonthLabel = monthLabel
        self.onSelect = onSelect
        self.onCancel = onCancel
        let parts = monthKey.split(separator: "-")
        let y = parts.count >= 1 ? Int(parts[0]) ?? Calendar.current.component(.year, from: Date()) : Calendar.current.component(.year, from: Date())
        let m = parts.count >= 2 ? Int(parts[1]) ?? Calendar.current.component(.month, from: Date()) : Calendar.current.component(.month, from: Date())
        _currentYear = State(initialValue: y)
        _currentMonth = State(initialValue: m)
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

    private var calendarContent: some View {
        VStack(spacing: 24) {
            headerRow
            calendarGrid
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .overlay(OnboardingDesign.glassBg.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(OnboardingDesign.glassBorder, lineWidth: 1)
        )
        .shadow(color: OnboardingDesign.textPrimary.opacity(0.06), radius: 16, x: 0, y: 8)
    }

    private var headerRow: some View {
        HStack {
            Button {
                prevMonth()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(OnboardingDesign.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.3))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()
            Text(currentMonthLabel)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(OnboardingDesign.textPrimary)
            Spacer()

            Button {
                nextMonth()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(OnboardingDesign.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.3))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

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
                    .foregroundColor(OnboardingDesign.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 4)
            }
            ForEach(calendarDays, id: \.offset) { item in
                if let day = item.day {
                    let hasActivity = item.hasActivity
                    let isPrevNext = item.isPrevMonth
                    let isSelected = selectWholeMonth ? false : (selectedDay == day && !isPrevNext)
                    let isToday = isCurrentMonth && day == today && !isPrevNext
                    dayCell(day: day, hasActivity: hasActivity, isPrevNext: isPrevNext, isSelected: isSelected, isToday: isToday)
                } else {
                    Color.clear
                        .frame(minHeight: 40)
                }
            }
        }
    }

    private func dayCell(day: Int, hasActivity: Bool, isPrevNext: Bool, isSelected: Bool, isToday: Bool) -> some View {
        Button {
            if !isPrevNext {
                selectedDay = day
                selectWholeMonth = false
            }
        } label: {
            ZStack(alignment: .bottom) {
                Text("\(day)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(foregroundFor(day: day, isPrevNext: isPrevNext, isSelected: isSelected, isToday: isToday))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(backgroundColor(isSelected: isSelected, isToday: isToday))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isToday && !isSelected ? OnboardingDesign.accentGreen : Color.clear, lineWidth: 1.5)
                    )
                    .shadow(color: isSelected ? OnboardingDesign.accentGreen.opacity(0.3) : .clear, radius: 6, x: 0, y: 4)
                if hasActivity && !isSelected {
                    Circle()
                        .fill(OnboardingDesign.accentGreen)
                        .frame(width: 4, height: 4)
                        .padding(.bottom, 4)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isPrevNext)
    }

    private func foregroundFor(day: Int, isPrevNext: Bool, isSelected: Bool, isToday: Bool) -> Color {
        if isSelected { return .white }
        if isPrevNext { return OnboardingDesign.textTertiary.opacity(0.5) }
        if isToday { return OnboardingDesign.accentGreen }
        return OnboardingDesign.textPrimary
    }

    private func backgroundColor(isSelected: Bool, isToday: Bool) -> Color {
        if isSelected { return OnboardingDesign.accentGreen }
        return Color.clear
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                selectWholeMonth = true
                selectedDay = nil
                confirmSelection()
            } label: {
                Text("Select whole month")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(OnboardingDesign.accentGreen)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            HStack(spacing: 12) {
                Button { onCancel() } label: {
                    Text("Cancel")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(OnboardingDesign.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.white.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)

                Button { confirmSelection() } label: {
                    Text("Select Date")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(OnboardingDesign.accentGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 24)
    }

    private func prevMonth() {
        if currentMonth == 1 {
            currentYear -= 1
            currentMonth = 12
        } else {
            currentMonth -= 1
        }
        selectedDay = nil
        selectWholeMonth = false
    }

    private func nextMonth() {
        if currentMonth == 12 {
            currentYear += 1
            currentMonth = 1
        } else {
            currentMonth += 1
        }
        selectedDay = nil
        selectWholeMonth = false
    }

    private func confirmSelection() {
        let dest = MonthDetailDestination(monthKey: currentMonthKey, monthLabel: currentMonthLabel)
        let day = selectWholeMonth ? nil : selectedDay
        onSelect(dest, day)
    }

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
