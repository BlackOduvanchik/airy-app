//
//  DatePickerPopoverView.swift
//  Airy
//
//  Compact date picker popover with wheel-style month/day/year.
//

import SwiftUI

private struct WheelRowSnapBehavior: ScrollTargetBehavior {
    let rowHeight: CGFloat = 32

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let proposed = target.rect.origin.y
        let snapped = round(proposed / rowHeight) * rowHeight
        target.rect.origin.y = snapped
    }
}

private let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

struct DatePickerPopoverView: View {
    @Environment(ThemeProvider.self) private var theme
    @Binding var dateTime: Date
    var onDismiss: () -> Void

    private let rowHeight: CGFloat = 32
    private let totalHeight: CGFloat = 120

    @State private var monthIndex: Int
    @State private var dayIndex: Int
    @State private var yearIndex: Int
    @State private var monthScrollId: Int?
    @State private var dayScrollId: Int?
    @State private var yearScrollId: Int?
    private static var yearRange: [Int] {
        let cal = Calendar.current
        let y = cal.component(.year, from: Date())
        return Array(2020...(y + 2))
    }

    init(dateTime: Binding<Date>, onDismiss: @escaping () -> Void) {
        self._dateTime = dateTime
        self.onDismiss = onDismiss
        let cal = Calendar.current
        let m = cal.component(.month, from: dateTime.wrappedValue) - 1
        let d = cal.component(.day, from: dateTime.wrappedValue) - 1
        let years = Self.yearRange
        let y = cal.component(.year, from: dateTime.wrappedValue)
        let yi = years.firstIndex(of: y) ?? 0
        self._monthIndex = State(initialValue: m)
        self._dayIndex = State(initialValue: min(d, daysInMonth(month: m + 1, year: y) - 1))
        self._yearIndex = State(initialValue: yi)
        self._monthScrollId = State(initialValue: m)
        self._dayScrollId = State(initialValue: min(d, daysInMonth(month: m + 1, year: y) - 1))
        self._yearScrollId = State(initialValue: yi)
    }

    var body: some View {
        VStack(spacing: 0) {
            pickerWheels
        }
        .frame(width: 180)
        .padding(12)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.white.opacity(0.5))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(theme.glassBorder, lineWidth: 1)
        )
        .shadow(color: theme.textPrimary.opacity(0.08), radius: 16, x: 0, y: 8)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.9)).combined(with: .offset(y: 10)),
            removal: .opacity
        ))
        .onDisappear { applyDate() }
    }

    private var pickerWheels: some View {
        ZStack(alignment: .center) {
            selectionHighlight

            HStack(spacing: 0) {
                wheelColumn(
                    values: Array(0..<12),
                    scrollId: $monthScrollId,
                    selectedIndex: $monthIndex,
                    formatter: { monthNames[$0] }
                )
                .onChange(of: monthScrollId) { _, id in
                    if let id {
                        monthIndex = id
                        clampDay()
                    }
                }

                Rectangle()
                    .fill(Color.black.opacity(0.05))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)

                wheelColumn(
                    values: Array(1...31),
                    scrollId: $dayScrollId,
                    selectedIndex: $dayIndex,
                    formatter: { String($0) }
                )
                .onChange(of: dayScrollId) { _, id in
                    if let id { dayIndex = id }
                }

                Rectangle()
                    .fill(Color.black.opacity(0.05))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)

                wheelColumn(
                    values: Self.yearRange,
                    scrollId: $yearScrollId,
                    selectedIndex: $yearIndex,
                    formatter: { String($0) }
                )
                .onChange(of: yearScrollId) { _, id in
                    if let id {
                        yearIndex = id
                        clampDay()
                    }
                }
            }
            .frame(height: totalHeight)
        }
    }

    private var selectionHighlight: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.white.opacity(0.4))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
            )
            .frame(height: 34)
            .allowsHitTesting(false)
    }

    private func wheelColumn(
        values: [Int],
        scrollId: Binding<Int?>,
        selectedIndex: Binding<Int>,
        formatter: @escaping (Int) -> String
    ) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(0..<values.count, id: \.self) { i in
                    Text(formatter(values[i]))
                        .font(.system(size: selectedIndex.wrappedValue == i ? 18 : 16, weight: selectedIndex.wrappedValue == i ? .bold : .medium))
                        .foregroundColor(selectedIndex.wrappedValue == i ? theme.textPrimary : theme.textTertiary)
                        .frame(height: rowHeight)
                        .frame(maxWidth: .infinity)
                        .id(i)
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.2)) {
                                scrollId.wrappedValue = i
                                selectedIndex.wrappedValue = i
                                applyDate()
                            }
                        }
                }
            }
            .padding(.vertical, (totalHeight - rowHeight) / 2)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(WheelRowSnapBehavior())
        .scrollPosition(id: scrollId, anchor: .center)
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
    }

    private func clampDay() {
        let month = monthIndex + 1
        let year = Self.yearRange[yearIndex]
        let maxDays = daysInMonth(month: month, year: year)
        if dayIndex >= maxDays {
            dayIndex = maxDays - 1
            dayScrollId = maxDays - 1
        }
    }

    private func applyDate() {
        clampDay()
        let month = monthIndex + 1
        let year = Self.yearRange[yearIndex]
        let maxDays = daysInMonth(month: month, year: year)
        let day = min(dayIndex + 1, maxDays)
        var comp = Calendar.current.dateComponents([.hour, .minute], from: dateTime)
        comp.year = year
        comp.month = month
        comp.day = day
        if let d = Calendar.current.date(from: comp) {
            dateTime = d
        }
    }
}

private func daysInMonth(month: Int, year: Int) -> Int {
    var comp = DateComponents()
    comp.year = year
    comp.month = month
    comp.day = 1
    guard let date = Calendar.current.date(from: comp),
          let range = Calendar.current.range(of: .day, in: .month, for: date) else { return 31 }
    return range.count
}
