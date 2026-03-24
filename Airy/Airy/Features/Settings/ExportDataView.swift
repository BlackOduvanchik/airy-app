//
//  ExportDataView.swift
//  Airy
//
//  Export Data page: period selection, transaction preview, column picker, CSV export.
//

import SwiftUI
import UIKit

// MARK: - Share Sheet

private struct ExportShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Main View

struct ExportDataView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeProvider.self) private var theme
    @State private var viewModel = ExportDataViewModel()
    @State private var showCalendarSheet = false
    @State private var showInfoAlert = false
    @State private var shareURL: URL?
    @State private var showShareSheet = false

    var body: some View {
        ZStack {
            OnboardingGradientBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    periodSection
                    transactionsSection
                    columnsSection
                    exportButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
        }
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
                Text(L("export_title"))
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(theme.textTertiary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showInfoAlert = true } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16))
                        .foregroundColor(theme.textTertiary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
        }
        .alert(L("settings_export"), isPresented: $showInfoAlert) {
            Button(L("common_ok"), role: .cancel) {}
        } message: {
            Text(L("export_info"))
        }
        .sheet(isPresented: $showCalendarSheet) {
            ExportCalendarSheet(
                startDate: $viewModel.customStartDate,
                endDate: $viewModel.customEndDate
            )
            .themed(theme)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showShareSheet, onDismiss: { shareURL = nil }) {
            if let url = shareURL {
                ExportShareSheet(url: url)
                    .themed(theme)
            }
        }
        .onAppear { viewModel.loadTransactions() }
        .onChange(of: viewModel.selectedPeriod) { _, _ in viewModel.loadTransactions() }
        .onChange(of: viewModel.customStartDate) { _, _ in
            if viewModel.selectedPeriod == .custom { viewModel.loadTransactions() }
        }
        .onChange(of: viewModel.customEndDate) { _, _ in
            if viewModel.selectedPeriod == .custom { viewModel.loadTransactions() }
        }
    }

    // MARK: - Period Selection

    private var periodSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionCaption(L("export_period"))
            glassPanel {
                ForEach(Array(ExportDataViewModel.Period.allCases.enumerated()), id: \.element) { index, period in
                    let isSelected = viewModel.selectedPeriod == period
                    let isLast = index == ExportDataViewModel.Period.allCases.count - 1
                    periodRow(period: period, isSelected: isSelected, showBottomBorder: !isLast)
                }
            }
        }
    }

    private func periodRow(period: ExportDataViewModel.Period, isSelected: Bool, showBottomBorder: Bool) -> some View {
        Button {
            viewModel.selectedPeriod = period
            if period == .custom {
                showCalendarSheet = true
            }
        } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(period.displayName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(theme.textPrimary)
                    Text(period.subtitle(customStart: viewModel.customStartDate, customEnd: viewModel.customEndDate))
                        .font(.system(size: 12))
                        .foregroundColor(theme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if period == .custom {
                    Button {
                        showCalendarSheet = true
                    } label: {
                        Image(systemName: "calendar")
                            .font(.system(size: 16))
                            .foregroundColor(theme.accentGreen)
                            .frame(width: 32, height: 32)
                    }
                }

                ZStack {
                    Circle()
                        .stroke(isSelected ? theme.accentGreen : theme.textTertiary, lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(theme.accentGreen)
                            .frame(width: 10, height: 10)
                    }
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 72)
            .contentShape(Rectangle())
            .overlay(
                Group {
                    if showBottomBorder {
                        Rectangle()
                            .fill(Color.white.opacity(theme.isDark ? 0.06 : 0.3))
                            .frame(height: 1)
                    }
                },
                alignment: .bottom
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Transactions

    private var transactionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionCaption(L("export_preview"))
            NavigationLink {
                ExportTransactionPreviewView(transactions: viewModel.transactions)
            } label: {
                glassPanel {
                    HStack {
                        Text(L("export_transactions"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(theme.textPrimary)
                        Spacer()
                        HStack(spacing: 8) {
                            Text("\(viewModel.transactions.count) \(L("export_transactions_count"))")
                                .font(.system(size: 13))
                                .foregroundColor(theme.textSecondary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(theme.textTertiary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 64)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Columns

    private var columnsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink {
                ExportColumnPickerView(viewModel: viewModel)
            } label: {
                glassPanel {
                    HStack {
                        Text(L("export_columns"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(theme.textPrimary)
                        Spacer()
                        HStack(spacing: 8) {
                            Text("\(viewModel.selectedColumnIds.count) \(L("export_of")) \(ExportDataViewModel.allColumns.count)")
                                .font(.system(size: 13))
                                .foregroundColor(theme.textSecondary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(theme.textTertiary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 64)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Export Button

    private var exportButton: some View {
        Button {
            if let url = viewModel.exportToFile() {
                shareURL = url
                showShareSheet = true
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                Text(L("export_button"))
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(theme.accentGreen)
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .shadow(color: theme.accentGreen.opacity(0.3), radius: 12, x: 0, y: 6)
        }
        .padding(.top, 8)
        .disabled(viewModel.transactions.isEmpty)
        .opacity(viewModel.transactions.isEmpty ? 0.5 : 1)
    }

    // MARK: - Helpers

    private func sectionCaption(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.5)
            .foregroundColor(theme.textTertiary)
            .padding(.bottom, 8)
    }

    private func glassPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
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

// MARK: - Calendar Sheet

struct ExportCalendarSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeProvider.self) private var theme
    @Binding var startDate: Date?
    @Binding var endDate: Date?

    @State private var displayedMonth: Date = Date()
    @State private var tapFirst: Date?
    @State private var tapSecond: Date?

    var body: some View {
        ZStack {
            OnboardingGradientBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text(L("export_date_range"))
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(theme.textTertiary)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(theme.textTertiary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 8)

                // Month navigation
                HStack {
                    Button {
                        withAnimation { displayedMonth = Calendar.current.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(theme.textPrimary)
                            .frame(width: 44, height: 44)
                    }

                    Spacer()

                    Text(monthYearLabel)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(theme.textPrimary)

                    Spacer()

                    Button {
                        withAnimation { displayedMonth = Calendar.current.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(theme.textPrimary)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, 20)

                // Calendar grid
                calendarGrid
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Spacer()

                // Apply button
                Button {
                    if let first = tapFirst {
                        if let second = tapSecond {
                            startDate = min(first, second)
                            endDate = max(first, second)
                        } else {
                            startDate = first
                            endDate = first
                        }
                    }
                    dismiss()
                } label: {
                    Text(L("common_apply"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(theme.accentGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 26))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .disabled(tapFirst == nil)
                .opacity(tapFirst == nil ? 0.5 : 1)
            }
        }
        .onAppear {
            tapFirst = startDate
            tapSecond = endDate
            if let s = startDate {
                displayedMonth = s
            }
        }
    }

    private var monthYearLabel: String {
        AppFormatters.monthYear.string(from: displayedMonth)
    }

    // MARK: - Calendar Grid

    private var calendarGrid: some View {
        let days = buildCalendarDays()
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(["month_su", "month_mo", "month_tu", "month_we", "month_th", "month_fr", "month_sa"], id: \.self) { key in
                Text(L(key))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 8)
            }
            ForEach(days, id: \.offset) { item in
                if let day = item.day, !item.isOtherMonth {
                    let cellDate = dateFor(day: day)
                    let rangeState = rangeStateFor(cellDate)
                    let isEndpoint = rangeState == .start || rangeState == .end
                    let isInRange = rangeState == .inRange

                    Button {
                        handleTap(cellDate)
                    } label: {
                        Text("\(day)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(isEndpoint ? .white : isInRange ? theme.accentGreen : theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(isEndpoint ? theme.accentGreen : isInRange ? theme.accentGreen.opacity(0.12) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                } else if let day = item.day {
                    Text("\(day)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(theme.textTertiary.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 36)
                } else {
                    Color.clear.frame(minHeight: 36)
                }
            }
        }
    }

    private func handleTap(_ date: Date) {
        if tapFirst == nil {
            tapFirst = date
            tapSecond = nil
        } else if tapSecond == nil {
            tapSecond = date
        } else {
            tapFirst = date
            tapSecond = nil
        }
    }

    private enum RangeState { case none, start, end, inRange }

    private func rangeStateFor(_ date: Date) -> RangeState {
        guard let first = tapFirst else { return .none }
        let cal = Calendar.current
        if tapSecond == nil {
            return cal.isDate(date, inSameDayAs: first) ? .start : .none
        }
        guard let second = tapSecond else { return .none }
        let lo = min(first, second)
        let hi = max(first, second)
        if cal.isDate(date, inSameDayAs: lo) { return .start }
        if cal.isDate(date, inSameDayAs: hi) { return .end }
        if date > lo && date < hi { return .inRange }
        return .none
    }

    private func dateFor(day: Int) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: displayedMonth)
        var dc = DateComponents()
        dc.year = comps.year
        dc.month = comps.month
        dc.day = day
        return cal.date(from: dc) ?? displayedMonth
    }

    // MARK: - Build Calendar Days

    private struct CalendarDay {
        let offset: Int
        let day: Int?
        let isOtherMonth: Bool
    }

    private func buildCalendarDays() -> [CalendarDay] {
        var cal = Calendar.current
        cal.firstWeekday = 1
        let comps = cal.dateComponents([.year, .month], from: displayedMonth)
        var dc = DateComponents()
        dc.year = comps.year
        dc.month = comps.month
        dc.day = 1
        guard let first = cal.date(from: dc),
              let range = cal.range(of: .day, in: .month, for: first) else { return [] }
        let lastDay = range.count
        let weekday = cal.component(.weekday, from: first)
        let startOffset = weekday - 1

        var result: [CalendarDay] = []
        if startOffset > 0, let prevMonth = cal.date(byAdding: .month, value: -1, to: first),
           let prevRange = cal.range(of: .day, in: .month, for: prevMonth) {
            let prevLastDay = prevRange.count
            for i in 0..<startOffset {
                let d = prevLastDay - startOffset + i + 1
                result.append(CalendarDay(offset: result.count, day: d, isOtherMonth: true))
            }
        }
        for d in 1...lastDay {
            result.append(CalendarDay(offset: result.count, day: d, isOtherMonth: false))
        }
        let totalCells = startOffset + lastDay
        let remainder = totalCells % 7
        if remainder > 0 {
            for i in 1...(7 - remainder) {
                result.append(CalendarDay(offset: result.count, day: i, isOtherMonth: true))
            }
        }
        return result
    }
}
