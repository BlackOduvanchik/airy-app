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

    var id: String { categoryId + monthKey }

    var color: Color {
        Color(hex: colorHex) ?? OnboardingDesign.accentGreen
    }
}

struct CategoryDetailView: View {
    let destination: CategoryDetailDestination
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = CategoryDetailViewModel()
    @State private var selectedTransactionForEdit: Transaction? = nil

    var body: some View {
        ZStack {
            OnboardingGradientBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    detailHero
                    transactionsByDay
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
        }
        .navigationBarHidden(true)
        .sheet(item: $selectedTransactionForEdit) { tx in
            AddTransactionView(
                transaction: tx,
                onSuccess: {
                    selectedTransactionForEdit = nil
                    Task { await viewModel.load(categoryId: destination.categoryId, monthKey: destination.monthKey) }
                }
            )
        }
        .task {
            await viewModel.load(categoryId: destination.categoryId, monthKey: destination.monthKey)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(OnboardingDesign.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.4))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(OnboardingDesign.glassHighlight, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()
            Text("Category Details")
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(OnboardingDesign.textPrimary)
            Spacer()
            Color.clear
                .frame(width: 40, height: 40)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Hero

    private var detailHero: some View {
        VStack(spacing: 4) {
            Text(destination.label)
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(OnboardingDesign.textTertiary)
            Text(formatAmount(destination.amount, "USD"))
                .font(.system(size: 32, weight: .light))
                .tracking(-1)
                .foregroundColor(OnboardingDesign.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Transactions by day

    private var transactionsByDay: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.groupedByDay.isEmpty {
                Text("No transactions in this category")
                    .font(.system(size: 14))
                    .foregroundColor(OnboardingDesign.textSecondary)
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
                .foregroundColor(OnboardingDesign.textSecondary)
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
                    selectedTransactionForEdit = tx
                } label: {
                    transactionItem(tx)
                }
                .buttonStyle(.plain)
            }
        }
        .background(.ultraThinMaterial)
        .overlay(OnboardingDesign.glassBg.opacity(0.5).allowsHitTesting(false))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(OnboardingDesign.glassBorder, lineWidth: 1)
                .allowsHitTesting(false)
        )
        .shadow(color: OnboardingDesign.textPrimary.opacity(0.06), radius: 16, x: 0, y: 8)
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
                    Text(tx.merchant ?? tx.category.capitalized)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(OnboardingDesign.textPrimary)
                    Spacer()
                    Text(formatAmount(tx.amountOriginal, tx.currencyOriginal))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(OnboardingDesign.textPrimary)
                }
                HStack(spacing: 6) {
                    if let sub = tx.subcategory, !sub.isEmpty {
                        Text(sub)
                            .font(.system(size: 10, weight: .bold))
                            .textCase(.uppercase)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.4))
                            .foregroundColor(OnboardingDesign.textSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    if let title = tx.title, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 12))
                            .foregroundColor(OnboardingDesign.textTertiary)
                            .italic()
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.1))
    }

    private func transactionIconName(_ tx: Transaction) -> String {
        if let cat = CategoryStore.byId(tx.category), let icon = cat.iconName { return icon }
        let c = tx.category.lowercased()
        if c.contains("food") || c.contains("dining") || c.contains("grocer") { return "cup.and.saucer.fill" }
        if c.contains("transport") || c.contains("transit") { return "car.fill" }
        if c.contains("housing") || c.contains("rent") { return "house.fill" }
        if c.contains("shopping") { return "bag.fill" }
        if c.contains("health") { return "heart.fill" }
        if c.contains("bills") { return "doc.text.fill" }
        return "dollarsign"
    }

    private func transactionIconColors(_ tx: Transaction) -> (Color, Color) {
        if tx.isSubscription == true {
            return (OnboardingDesign.accentWarning.opacity(0.2), OnboardingDesign.accentWarning)
        }
        let color = CategoryStore.byId(tx.category)?.color ?? destination.color
        return (color.opacity(0.18), color)
    }

    // MARK: - Helpers

    private func formatAmount(_ amount: Double, _ currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount) \(currency)"
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
    var isLoading = true

    func load(categoryId: String, monthKey: String) async {
        isLoading = true
        defer { Task { @MainActor in isLoading = false } }
        await MainActor.run {
            let parts = monthKey.split(separator: "-")
            guard parts.count >= 2,
                  let year = Int(parts[0]),
                  let month = Int(parts[1]) else { return }
            let monthStr = String(format: "%02d", month)
            let yearStr = String(year)

            let all = LocalDataStore.shared.fetchTransactions(limit: 500, month: monthStr, year: yearStr)
            let filtered = all.filter { $0.type.lowercased() != "income" && $0.category == categoryId }
            let sorted = filtered.sorted { $0.transactionDate > $1.transactionDate }

            var byDay: [String: [Transaction]] = [:]
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            dateFormatter.timeZone = TimeZone(identifier: "UTC")
            let outFormatter = DateFormatter()
            outFormatter.dateFormat = "MMM d"

            for tx in sorted {
                let dateStr = String(tx.transactionDate.prefix(10))
                byDay[dateStr, default: []].append(tx)
            }

            groupedByDay = byDay.sorted { $0.key > $1.key }.map { dateKey, txs in
                let date = dateFormatter.date(from: dateKey) ?? Date()
                let label = outFormatter.string(from: date)
                return DayGroup(id: dateKey, dateKey: dateKey, dateLabel: label, transactions: txs)
            }
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
