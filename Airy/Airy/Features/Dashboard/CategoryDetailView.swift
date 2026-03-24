//
//  CategoryDetailView.swift
//  Airy
//
//  Category spending detail: total at top, transactions grouped by day.
//

import SwiftUI

struct CategoryDetailDestination: Hashable, Identifiable {
    let categoryId: String
    let label: String
    let amount: Double
    let colorHex: String
    let iconName: String
    let monthKey: String
    let monthLabel: String
    var isIncome: Bool = false

    var id: String { categoryId + monthKey + (isIncome ? "_income" : "") }

    var color: Color {
        Color(hex: colorHex) ?? OnboardingDesign.accentGreen
    }
}

struct CategoryDetailView: View {
    @Environment(ThemeProvider.self) private var theme
    let destination: CategoryDetailDestination
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = CategoryDetailViewModel()
    @State private var selectedTransactionForEdit: Transaction? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                OnboardingGradientBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        detailHero
                        transactionsByDay
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
                    Button {
                        print("[Tap] CategoryDetail → Back")
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(L("catdetail_title"))
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(theme.textTertiary)
                }
            }
            .sheet(item: $selectedTransactionForEdit) { tx in
                AddTransactionView(
                    transaction: tx,
                    onSuccess: {
                        selectedTransactionForEdit = nil
                        Task { @MainActor in
                            await viewModel.load(categoryId: destination.categoryId, monthKey: destination.monthKey, isIncome: destination.isIncome)
                            if viewModel.groupedByDay.isEmpty {
                                dismiss()
                            }
                        }
                    }
                )
                .themed(theme)
            }
            .onAppear { print("[Nav] CategoryDetail '\(destination.label)' (monthKey=\(destination.monthKey))") }
            .task {
                await viewModel.load(categoryId: destination.categoryId, monthKey: destination.monthKey, isIncome: destination.isIncome)
            }
        }
    }

    // MARK: - Hero

    private var detailHero: some View {
        VStack(spacing: 4) {
            Text(destination.label)
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(theme.textTertiary)
            Text(formatAmount(viewModel.totalAmount > 0 ? viewModel.totalAmount : destination.amount, BaseCurrencyStore.baseCurrency))
                .font(.system(size: 32, weight: .light))
                .tracking(-1)
                .foregroundColor(theme.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Transactions by day

    private var transactionsByDay: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.groupedByDay.isEmpty {
                Text(L("catdetail_empty"))
                    .font(.system(size: 14))
                    .foregroundColor(theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            } else {
                ForEach(viewModel.groupedByDay, id: \.dateKey) { group in
                    groupHeader(group.dateLabel)
                    transactionGroupPanel(transactions: group.transactions)
                }
            }
        }
    }

    private func groupHeader(_ label: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(theme.textSecondary)
            Rectangle()
                .fill(Color.white.opacity(0.2))
                .frame(height: 1)
        }
        .padding(.horizontal, 8)
        .padding(.top, 24)
        .padding(.bottom, 12)
    }

    private func transactionGroupPanel(transactions: [Transaction]) -> some View {
        VStack(spacing: 1) {
            ForEach(Array(transactions.enumerated()), id: \.element.id) { index, tx in
                Button {
                    print("[Tap] CategoryDetail → Transaction '\(tx.merchant ?? tx.category)'")
                    selectedTransactionForEdit = tx
                } label: {
                    transactionItem(tx)
                }
                .buttonStyle(.plain)
            }
        }
        .background(theme.isDark ? AnyShapeStyle(theme.glassBg) : AnyShapeStyle(.ultraThinMaterial))
        .overlay(theme.isDark ? nil : theme.glassBg.opacity(0.5).allowsHitTesting(false))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(theme.glassBorder, lineWidth: 1)
                .allowsHitTesting(false)
        )
        .shadow(color: theme.isDark ? Color.black.opacity(0.4) : theme.textPrimary.opacity(0.06), radius: 16, x: 0, y: 8)
    }

    private func transactionItem(_ tx: Transaction) -> some View {
        let (iconBg, iconFg) = transactionIconColors(tx)
        let iconName = transactionIconName(tx)

        return HStack(alignment: .center, spacing: 14) {
            RoundedRectangle(cornerRadius: 14)
                .fill(iconBg)
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: iconName)
                        .font(.system(size: 20))
                        .foregroundColor(iconFg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(CategoryIconHelper.transactionDisplayName(merchant: tx.merchant, subcategory: tx.subcategory, categoryId: tx.category))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                    Spacer()
                    Text(formatAmount(tx.amountOriginal, tx.currencyOriginal))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                }
                HStack(spacing: 6) {
                    if let subId = tx.subcategory, !subId.isEmpty,
                       let subName = SubcategoryStore.forParent(tx.category).first(where: { $0.id == subId })?.name {
                        Text(subName)
                            .font(.system(size: 10, weight: .bold))
                            .textCase(.uppercase)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.4))
                            .foregroundColor(theme.textSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    if let title = tx.title, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 12))
                            .foregroundColor(theme.textTertiary)
                            .italic()
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.1))
    }

    private func transactionIconName(_ tx: Transaction) -> String {
        tx.isSubscription == true ? CategoryIconHelper.subscriptionIconName() : CategoryIconHelper.iconName(categoryId: tx.category, subcategoryId: tx.subcategory)
    }

    private func transactionIconColors(_ tx: Transaction) -> (Color, Color) {
        CategoryIconHelper.iconColors(categoryId: tx.category, subcategoryId: tx.subcategory, isSubscription: tx.isSubscription == true)
    }

    // MARK: - Helpers

    private func formatAmount(_ amount: Double, _ currency: String) -> String {
        AppFormatters.formatTotal(amount: amount, currency: currency)
    }
}

// MARK: - ViewModel

struct DayGroup: Identifiable {
    let id: String
    let dateKey: String
    let dateLabel: String
    let transactions: [Transaction]
}

@Observable
final class CategoryDetailViewModel {
    var groupedByDay: [DayGroup] = []
    var totalAmount: Double = 0
    var isLoading = true

    func load(categoryId: String, monthKey: String, isIncome: Bool = false) async {
        let perfStart = CFAbsoluteTimeGetCurrent()
        isLoading = true
        defer { Task { @MainActor in isLoading = false } }
        await MainActor.run {
            let parts = monthKey.split(separator: "-")
            let all: [Transaction]
            if parts.count >= 2, let year = Int(parts[0]), let month = Int(parts[1]) {
                // Month mode: "YYYY-MM"
                let monthStr = String(format: "%02d", month)
                let yearStr = String(year)
                all = LocalDataStore.shared.fetchTransactions(limit: 500, month: monthStr, year: yearStr)
            } else if let year = Int(monthKey) {
                // Year mode: "YYYY"
                all = LocalDataStore.shared.fetchTransactions(from: "\(year)-01-01", to: "\(year)-12-31")
            } else {
                return
            }
            let filtered = all.filter {
                (isIncome ? $0.type.lowercased() == "income" : $0.type.lowercased() != "income")
                && $0.category == categoryId
            }
            let sorted = filtered.sorted { $0.transactionDate > $1.transactionDate }

            var byDay: [String: [Transaction]] = [:]
            let dateFormatter = AppFormatters.inputDate
            let outFormatter = AppFormatters.shortMonthDay

            for tx in sorted {
                let dateStr = String(tx.transactionDate.prefix(10))
                byDay[dateStr, default: []].append(tx)
            }

            groupedByDay = byDay.sorted { $0.key > $1.key }.map { dateKey, txs in
                let date = dateFormatter.date(from: dateKey) ?? Date()
                let label = outFormatter.string(from: date)
                return DayGroup(id: dateKey, dateKey: dateKey, dateLabel: label, transactions: txs)
            }
            totalAmount = groupedByDay.flatMap { $0.transactions }.reduce(0) { acc, tx in
                acc + CurrencyService.amountInBase(amountOriginal: abs(tx.amountOriginal), currencyOriginal: tx.currencyOriginal, amountBase: tx.amountBase, baseCurrency: tx.baseCurrency)
            }
            let perfEnd = CFAbsoluteTimeGetCurrent()
            print("[Perf] CategoryDetailVM.load() took \(String(format: "%.1f", (perfEnd - perfStart) * 1000))ms")
        }
    }
}

#Preview {
    NavigationStack {
        CategoryDetailView(destination: CategoryDetailDestination(
            categoryId: "food",
            label: "Food & Dining",
            amount: 853.65,
            colorHex: "#67A082",
            iconName: "cup.and.saucer.fill",
            monthKey: "2025-03",
            monthLabel: "March 2025"
        ))
    }
}
