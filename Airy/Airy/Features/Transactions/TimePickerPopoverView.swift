//
//  TimePickerPopoverView.swift
//  Airy
//
//  Compact time picker popover with wheel-style hours/minutes.
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

struct TimePickerPopoverView: View {
    @Binding var dateTime: Date
    var onDismiss: () -> Void

    private let rowHeight: CGFloat = 32
    private let totalHeight: CGFloat = 120

    @State private var hourIndex: Int
    @State private var minuteIndex: Int
    @State private var hourScrollId: Int?
    @State private var minuteScrollId: Int?
    init(dateTime: Binding<Date>, onDismiss: @escaping () -> Void) {
        self._dateTime = dateTime
        self.onDismiss = onDismiss
        let cal = Calendar.current
        let h = cal.component(.hour, from: dateTime.wrappedValue)
        let m = cal.component(.minute, from: dateTime.wrappedValue)
        self._hourIndex = State(initialValue: h)
        self._minuteIndex = State(initialValue: m)
        self._hourScrollId = State(initialValue: h)
        self._minuteScrollId = State(initialValue: m)
    }

    var body: some View {
        VStack(spacing: 0) {
            pickerWheels
        }
        .frame(width: 140)
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
                .stroke(OnboardingDesign.glassBorder, lineWidth: 1)
        )
        .shadow(color: Color(red: 0.118, green: 0.176, blue: 0.141).opacity(0.08), radius: 16, x: 0, y: 8)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.9)).combined(with: .offset(y: 10)),
            removal: .opacity
        ))
        .onDisappear { applyTime() }
    }

    private var pickerWheels: some View {
        ZStack(alignment: .center) {
            selectionHighlight

            HStack(spacing: 0) {
                wheelColumn(
                    values: Array(0..<24),
                    scrollId: $hourScrollId,
                    selectedIndex: $hourIndex
                )
                .onChange(of: hourScrollId) { _, id in
                    if let id { hourIndex = id }
                }

                Rectangle()
                    .fill(Color.black.opacity(0.05))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)

                wheelColumn(
                    values: Array(0..<60),
                    scrollId: $minuteScrollId,
                    selectedIndex: $minuteIndex
                )
                .onChange(of: minuteScrollId) { _, id in
                    if let id { minuteIndex = id }
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
        selectedIndex: Binding<Int>
    ) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(0..<values.count, id: \.self) { i in
                    Text(String(format: "%02d", values[i]))
                        .font(.system(size: selectedIndex.wrappedValue == i ? 18 : 16, weight: selectedIndex.wrappedValue == i ? .bold : .medium))
                        .foregroundColor(selectedIndex.wrappedValue == i ? OnboardingDesign.textPrimary : OnboardingDesign.textTertiary)
                        .frame(height: rowHeight)
                        .frame(maxWidth: .infinity)
                        .id(i)
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.2)) {
                                scrollId.wrappedValue = i
                                selectedIndex.wrappedValue = i
                                applyTime()
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

    private func applyTime() {
        var comp = Calendar.current.dateComponents([.year, .month, .day], from: dateTime)
        comp.hour = hourIndex
        comp.minute = minuteIndex
        if let d = Calendar.current.date(from: comp) {
            dateTime = d
        }
    }
}
