//
//  TransactionListView.swift
//  Airy
//
//  Transactions tab: search, category filters, spending by month with cards.
//

import SwiftUI

/// Destination for month detail: calendar + transactions by day.
struct MonthDetailDestination: Hashable {
    let monthKey: String
    let monthLabel: String
}

struct TransactionListView: View {
    @State private var viewModel = TransactionListViewModel()
    @State private var showAddTransaction = false
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                OnboardingGradientBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        headerSection
                        searchSection
                        filterPillsSection
                        transactionsContent
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 120)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Transactions")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Transaction.self) { tx in
                TransactionDetailView(transaction: tx)
            }
            .navigationDestination(for: MonthDetailDestination.self) { dest in
                MonthDetailView(monthKey: dest.monthKey, monthLabel: dest.monthLabel)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showAddTransaction = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddTransaction) {
                AddTransactionView()
            }
            .task { await viewModel.load() }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TRANSACTIONS")
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(OnboardingDesign.textTertiary)
            Text("All Spending")
                .font(.system(size: 34, weight: .light))
                .tracking(-0.5)
                .lineSpacing(2)
                .foregroundColor(OnboardingDesign.textPrimary)
        }
        .padding(.top, 10)
    }

    // MARK: - Search

    private var searchSection: some View {
        ZStack(alignment: .leading) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18))
                .foregroundColor(OnboardingDesign.textTertiary)
                .padding(.leading, 16)
            TextField("Search merchants…", text: $viewModel.searchText)
                .font(.system(size: 15))
                .foregroundColor(OnboardingDesign.textPrimary)
                .padding(.horizontal, 16)
                .padding(.leading, 44)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(OnboardingDesign.glassBorder, lineWidth: 1)
                )
        }
    }

    // MARK: - Filter pills

    private var filterPillsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(TransactionCategoryFilter.allCases.enumerated()), id: \.element.rawValue) { index, filter in
                    let isActive = viewModel.selectedFilter == filter
                    Button {
                        viewModel.selectedFilter = filter
                    } label: {
                        Text(filter.rawValue)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(isActive ? .white : OnboardingDesign.textSecondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(isActive ? OnboardingDesign.accentGreen : OnboardingDesign.glassBg)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(isActive ? OnboardingDesign.accentGreen : OnboardingDesign.glassBorder, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 0)
            .padding(.bottom, 4)
        }
        .padding(.horizontal, -20)
        .padding(.leading, 20)
        .padding(.trailing, 20)
    }

    // MARK: - Transactions content

    private var transactionsContent: some View {
        Group {
            if viewModel.isLoading && viewModel.transactions.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else if viewModel.groupedByMonth.isEmpty {
                Text("No transactions yet")
                    .font(.system(size: 14))
                    .foregroundColor(OnboardingDesign.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            } else {
                ForEach(viewModel.groupedByMonth) { group in
                    monthSection(group: group)
                }
            }
        }
    }

    private func monthSection(group: TransactionMonthGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: MonthDetailDestination(monthKey: group.id, monthLabel: group.monthLabel)) {
                sectionHeader(monthLabel: group.monthLabel, total: group.total)
            }
            .buttonStyle(.plain)
            VStack(spacing: 12) {
                ForEach(group.transactions) { tx in
                    NavigationLink(value: tx) {
                        transactionCard(tx: tx, monthTransactions: group.transactions)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sectionHeader(monthLabel: String, total: Double) -> some View {
        HStack {
            Text(monthLabel)
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(OnboardingDesign.textPrimary)
            Spacer()
            Text(formatAmount(total, "USD"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(OnboardingDesign.textSecondary)
        }
        .padding(.horizontal, 4)
    }

    private func transactionCard(tx: Transaction, monthTransactions: [Transaction]) -> some View {
        let isWarning = viewModel.isPossibleDuplicate(tx, inMonthTransactions: monthTransactions)
        return HStack(alignment: .center, spacing: 12) {
            iconCircle(category: tx.category, isSubscription: tx.isSubscription == true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 6) {
                    Text(tx.merchant ?? "Unknown")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(OnboardingDesign.textPrimary)
                        .lineLimit(1)
                    categoryBadge(tx.category, isSubscription: tx.isSubscription == true)
                }
                Text(subtitleForTransaction(tx))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(OnboardingDesign.textTertiary)
                    .lineLimit(1)
                if isWarning {
                    Text("Possible Duplicate")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(OnboardingDesign.accentAmber)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .center, spacing: 8) {
                Text(amountString(tx))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(OnboardingDesign.textPrimary)
                Image(systemName: "pencil")
                    .font(.system(size: 14))
                    .foregroundColor(OnboardingDesign.textTertiary.opacity(0.6))
            }
        }
        .padding(16)
        .modifier(TransactionsGlassModifier())
        .background {
            if isWarning {
                RoundedRectangle(cornerRadius: 28)
                    .fill(OnboardingDesign.accentAmber.opacity(0.08))
            }
        }
        .overlay {
            if isWarning {
                RoundedRectangle(cornerRadius: 28)
                    .stroke(OnboardingDesign.accentAmber.opacity(0.3), lineWidth: 1)
            }
        }
    }

    private func iconCircle(category: String, isSubscription: Bool) -> some View {
        let (bg, fg) = iconColors(category: category, isSubscription: isSubscription)
        return ZStack {
            Circle()
                .fill(bg)
                .frame(width: 40, height: 40)
            Image(systemName: iconName(category: category, isSubscription: isSubscription))
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(fg)
        }
    }

    private func iconName(category: String, isSubscription: Bool) -> String {
        if isSubscription { return "creditcard.fill" }
        let c = category.lowercased()
        if c.contains("food") || c.contains("dining") { return "cup.and.saucer.fill" }
        if c.contains("transport") || c.contains("transit") { return "car.fill" }
        if c.contains("shopping") { return "bag.fill" }
        if c.contains("health") { return "heart.fill" }
        return "dollarsign"
    }

    private func iconColors(category: String, isSubscription: Bool) -> (Color, Color) {
        let c = category.lowercased()
        if c.contains("food") || c.contains("dining") {
            return (OnboardingDesign.accentGreen.opacity(0.2), OnboardingDesign.accentGreen)
        }
        if c.contains("shopping") {
            return (OnboardingDesign.accentBlue.opacity(0.2), OnboardingDesign.accentBlue)
        }
        if isSubscription || c.contains("subscription") {
            return (OnboardingDesign.accentAmber.opacity(0.2), OnboardingDesign.accentAmber)
        }
        if c.contains("transport") || c.contains("transit") {
            return (Color(red: 0.886, green: 0.871, blue: 0.808).opacity(0.6), OnboardingDesign.textSecondary)
        }
        return (Color.white.opacity(0.6), OnboardingDesign.textSecondary)
    }

    private func categoryBadge(_ category: String, isSubscription: Bool) -> some View {
        let label = isSubscription ? "Sub" : categoryDisplayName(category)
        let (bg, fg) = badgeColors(category: category, isSubscription: isSubscription)
        return Text(label)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func categoryDisplayName(_ category: String) -> String {
        let c = category.lowercased()
        if c.contains("food") || c.contains("dining") { return "Dining" }
        if c.contains("transport") || c.contains("transit") { return "Transit" }
        if c.contains("shopping") { return "Shopping" }
        if c.contains("health") { return "Health" }
        return category.prefix(1).uppercased() + category.dropFirst().lowercased()
    }

    private func badgeColors(category: String, isSubscription: Bool) -> (Color, Color) {
        if isSubscription {
            return (Color(red: 0.886, green: 0.871, blue: 0.808).opacity(0.5), OnboardingDesign.textSecondary)
        }
        let c = category.lowercased()
        if c.contains("food") || c.contains("dining") {
            return (OnboardingDesign.accentGreen.opacity(0.15), OnboardingDesign.accentGreen)
        }
        if c.contains("shopping") {
            return (OnboardingDesign.accentBlue.opacity(0.15), OnboardingDesign.accentBlue)
        }
        return (Color(red: 0.886, green: 0.871, blue: 0.808).opacity(0.5), OnboardingDesign.textSecondary)
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
        }
        return sub
    }

    private func amountString(_ tx: Transaction) -> String {
        let amount = tx.amountOriginal
        let formatted = formatAmount(amount, tx.currencyOriginal)
        return tx.type.lowercased() == "income" ? "+\(formatted)" : "-\(formatted)"
    }

    private func formatAmount(_ amount: Double, _ currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: abs(amount))) ?? "\(abs(amount)) \(currency)"
    }
}

// MARK: - Glass modifier

private struct TransactionsGlassModifier: ViewModifier {
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
    TransactionListView()
}
