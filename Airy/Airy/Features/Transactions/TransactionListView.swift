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
    var showBottomBar: Bool = false
    var onDismiss: (() -> Void)? = nil
    var onInsights: (() -> Void)? = nil
    var onSettings: (() -> Void)? = nil
    @State private var viewModel = TransactionListViewModel()
    @State private var showAddTransaction = false
    @State private var addSheetQuickPickOrder: [String] = []
    @State private var selectedTransactionForEdit: Transaction? = nil
    @State private var monthPath: [MonthDetailDestination] = []
    @FocusState private var isSearchFocused: Bool
    @State private var deletingTransactionIds: Set<String> = []
    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        NavigationStack(path: $monthPath) {
            ZStack(alignment: .top) {
                OnboardingGradientBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        titleSection
                        if !viewModel.pinnedTransactions.isEmpty {
                            pinnedSection
                                .transition(.asymmetric(
                                    insertion: .opacity
                                        .combined(with: .scale(scale: 0.88, anchor: .top))
                                        .combined(with: .offset(y: -36)),
                                    removal: .opacity
                                        .combined(with: .scale(scale: 0.92, anchor: .top))
                                        .combined(with: .offset(y: -16))
                                ))
                        }
                        searchSection
                        filterPillsSection
                        transactionsContent
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 120)
                }
                .scrollIndicators(.hidden)
            }
            .overlay(alignment: .bottom) {
                if showBottomBar {
                    transactionsBottomBar
                        .frame(maxWidth: .infinity)
                }
            }
            .ignoresSafeArea(edges: showBottomBar ? .bottom : [])
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                if showBottomBar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { onDismiss?() } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("TRANSACTIONS")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(OnboardingDesign.textTertiary)
                }
                if !showBottomBar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: {
                            addSheetQuickPickOrder = LastUsedCategoriesStore.forQuickPick()
                            showAddTransaction = true
                        }) {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .navigationDestination(for: MonthDetailDestination.self) { dest in
                MonthDetailView(monthKey: dest.monthKey, monthLabel: dest.monthLabel, monthPath: $monthPath)
            }
            .sheet(isPresented: $showAddTransaction, onDismiss: {
                Task { await viewModel.load() }
            }) {
                AddTransactionView(initialQuickPickOrder: addSheetQuickPickOrder)
            }
            .sheet(item: $selectedTransactionForEdit) { tx in
                AddTransactionView(transaction: tx, onSuccess: {
                    selectedTransactionForEdit = nil
                    Task { await viewModel.load() }
                })
            }
            .task { await viewModel.load() }
            .onChange(of: viewModel.selectedFilterId) { _, newValue in
                if newValue != nil && viewModel.hasMore {
                    Task { await viewModel.loadRemaining() }
                }
            }
            .sensoryFeedback(.warning, trigger: deletingTransactionIds.count)
        }
        .offset(x: showBottomBar ? dragOffset : 0)
        .simultaneousGesture(
            showBottomBar ?
            DragGesture()
                .updating($dragOffset) { value, state, _ in
                    if value.startLocation.x < 40 && value.translation.width > 0 {
                        state = value.translation.width
                    }
                }
                .onEnded { value in
                    if value.startLocation.x < 40 && value.translation.width > 100 {
                        onDismiss?()
                    }
                }
            : nil
        )
        .animation(.interactiveSpring, value: dragOffset)
    }

    // MARK: - Bottom bar (when presented as modal) — same as Dashboard

    private var transactionsBottomBar: some View {
        BottomNavBarView(
            onInsights: { onInsights?() },
            onFab: {
                addSheetQuickPickOrder = LastUsedCategoriesStore.forQuickPick()
                showAddTransaction = true
            },
            onSettings: { onSettings?() },
            useDashboardButton: true,
            onDashboard: { onDismiss?() },
            insightsActive: false,
            settingsActive: false
        )
    }

    // MARK: - Title (scrollable)

    private var titleSection: some View {
        Text("All Spending")
            .font(.system(size: 34, weight: .light))
            .tracking(-0.5)
            .lineSpacing(2)
            .foregroundColor(OnboardingDesign.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Search

    private var searchSection: some View {
        ZStack(alignment: .leading) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18))
                .foregroundColor(OnboardingDesign.textTertiary)
                .padding(.leading, 16)
                .accessibilityHidden(true)
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
                ForEach(viewModel.categoryFilters) { filter in
                    let isActive = (filter.id == "all" && viewModel.selectedFilterId == nil) || viewModel.selectedFilterId == filter.id
                    Button {
                        viewModel.selectedFilterId = filter.id == "all" ? nil : filter.id
                    } label: {
                        Text(filter.label)
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
            .padding(.horizontal, 20)
            .padding(.bottom, 4)
        }
        .padding(.horizontal, -20)
    }

    // MARK: - Transactions content

    private var transactionsContent: some View {
        Group {
            if viewModel.isLoading && viewModel.transactions.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else if viewModel.groupedByMonth.isEmpty && viewModel.pinnedTransactions.isEmpty {
                Text("No transactions yet")
                    .font(.system(size: 14))
                    .foregroundColor(OnboardingDesign.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            } else {
                ForEach(viewModel.groupedByMonth) { group in
                    monthSection(group: group)
                }
                if viewModel.hasMore && viewModel.selectedFilterId == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .onAppear {
                            Task { await viewModel.load(append: true) }
                        }
                }
            }
        }
    }

    // MARK: - Pinned section

    private var pinnedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PINNED ITEMS")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(OnboardingDesign.textPrimary)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            ForEach(viewModel.pinnedTransactions.filter { !deletingTransactionIds.contains($0.id) }) { tx in
                pinnedTransactionCard(tx: tx)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.98)),
                        removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .center))
                    ))
                    .onTapGesture {
                        selectedTransactionForEdit = tx
                    }
                    .contextMenu {
                        contextMenuActions(tx: tx)
                    }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.86), value: deletingTransactionIds)
        }
        .padding(16)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 32)
                .fill(Color.white.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 32)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                        .foregroundColor(OnboardingDesign.glassBorder)
                )
        )
    }

    private func pinnedTransactionCard(tx: Transaction) -> some View {
        HStack(alignment: .center, spacing: 12) {
            iconCircle(category: tx.category, isSubscription: tx.isSubscription == true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 6) {
                    Text(transactionDisplayName(tx))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(OnboardingDesign.textPrimary)
                        .lineLimit(1)
                    categoryBadge(tx.category, isSubscription: tx.isSubscription == true)
                    Spacer(minLength: 0)
                }
                Text(subtitleForTransaction(tx))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(OnboardingDesign.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(amountString(tx))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(OnboardingDesign.textPrimary)
            Image(systemName: "pin.fill")
                .font(.system(size: 10))
                .foregroundColor(OnboardingDesign.textTertiary)
        }
        .padding(16)
        .background(Color.white.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .shadow(color: OnboardingDesign.textPrimary.opacity(0.04), radius: 20, x: 0, y: 10)
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(OnboardingDesign.glassBorder, lineWidth: 1)
        )
    }

    private func monthSection(group: TransactionMonthGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: MonthDetailDestination(monthKey: group.id, monthLabel: group.monthLabel)) {
                sectionHeader(monthLabel: group.monthLabel, total: group.total)
            }
            .buttonStyle(.plain)
            VStack(spacing: 12) {
                ForEach(group.transactions.filter { !deletingTransactionIds.contains($0.id) }) { tx in
                    transactionCard(tx: tx, monthTransactions: group.transactions)
                            .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.98)),
                            removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .center))
                        ))
                        .onTapGesture {
                            selectedTransactionForEdit = tx
                        }
                        .contextMenu {
                            contextMenuActions(tx: tx)
                        }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.86), value: deletingTransactionIds)
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
        return ZStack(alignment: .topTrailing) {
            HStack(alignment: .center, spacing: 12) {
            iconCircle(category: tx.category, isSubscription: tx.isSubscription == true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 6) {
                    Text(transactionDisplayName(tx))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(OnboardingDesign.textPrimary)
                        .lineLimit(1)
                    categoryBadge(tx.category, isSubscription: tx.isSubscription == true)
                    if tx.isSubscription == true {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 14))
                            .foregroundColor(OnboardingDesign.accentBlue.opacity(0.8))
                    }
                    Spacer(minLength: 0)
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
                        .background(OnboardingDesign.accentWarning)
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
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(OnboardingDesign.textTertiary.opacity(0.6))
            }
        }
        .padding(16)
        .modifier(TransactionsGlassModifier())
        .background {
            if isWarning {
                RoundedRectangle(cornerRadius: 28)
                    .fill(OnboardingDesign.accentWarning.opacity(0.08))
            }
        }
        .overlay {
            if isWarning {
                RoundedRectangle(cornerRadius: 28)
                    .stroke(OnboardingDesign.accentWarning.opacity(0.3), lineWidth: 1)
            }
        }
        }
    }

    @ViewBuilder
    private func contextMenuActions(tx: Transaction) -> some View {
        Button {
            let willPin = !viewModel.isPinned(tx)
            LocalDataStore.shared.setPinned(id: tx.id, pinned: willPin)
            // Delay state update to let context menu dismiss first
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                    viewModel.pinnedIds = LocalDataStore.shared.pinnedTransactionIds()
                }
            }
        } label: {
            Label(viewModel.isPinned(tx) ? "Unpin" : "Pin to Top", systemImage: "bookmark")
        }
        Button(role: .destructive) {
            let id = tx.id
            _ = withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                deletingTransactionIds.insert(id)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                try? LocalDataStore.shared.deleteTransaction(id: id)
                deletingTransactionIds.remove(id)
                Task { @MainActor in await viewModel.load() }
            }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func iconCircle(category: String, isSubscription: Bool) -> some View {
        let iconName = CategoryIconHelper.iconName(categoryId: category)
        let (bg, fg) = CategoryIconHelper.iconColors(categoryId: category)
        return ZStack {
            Circle()
                .fill(bg)
                .frame(width: 40, height: 40)
            Image(systemName: iconName)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(fg)
        }
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
        CategoryIconHelper.displayName(categoryId: category)
    }

    private func badgeColors(category: String, isSubscription: Bool) -> (Color, Color) {
        if isSubscription {
            return (OnboardingDesign.accentWarning.opacity(0.15), OnboardingDesign.accentWarning)
        }
        let color = CategoryIconHelper.color(categoryId: category)
        return (color.opacity(0.15), color)
    }

    private func transactionDisplayName(_ tx: Transaction) -> String {
        CategoryIconHelper.transactionDisplayName(merchant: tx.merchant, subcategory: tx.subcategory, categoryId: tx.category)
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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background(reduceTransparency ? AnyShapeStyle(Color(.secondarySystemGroupedBackground)) : AnyShapeStyle(.ultraThinMaterial))
            .overlay(reduceTransparency ? nil : OnboardingDesign.glassBg.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .stroke(OnboardingDesign.glassBorder, lineWidth: 1)
                    .allowsHitTesting(false)
            )
            .shadow(color: OnboardingDesign.textPrimary.opacity(0.06), radius: 16, x: 0, y: 8)
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    .blur(radius: 0)
                    .offset(y: 1)
                    .allowsHitTesting(false)
            )
    }
}

#Preview {
    TransactionListView()
}
