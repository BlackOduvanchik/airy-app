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
    @Environment(ThemeProvider.self) private var theme
    @Environment(\.dismiss) private var dismiss
    var showBottomBar: Bool = false
    var initialSearchText: String? = nil
    var initialCategoryFilter: String? = nil
    var onBack: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil
    var onInsights: (() -> Void)? = nil
    var onSettings: (() -> Void)? = nil
    @State private var viewModel = TransactionListViewModel.shared
    @State private var showAddTransaction = false
    @State private var addSheetQuickPickOrder: [String] = []
    @State private var addSheetDidSave = false
    @State private var selectedTransactionForEdit: Transaction? = nil
    @State private var monthPath: [MonthDetailDestination] = []
    @State private var selectedMonth: MonthDetailDestination?
    @FocusState private var isSearchFocused: Bool
    @State private var deletingTransactionIds: Set<String> = []
    @State private var localSearchText = ""
    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        if showBottomBar {
            NavigationStack(path: $monthPath) {
                innerContent
            }
            .offset(x: dragOffset)
            .simultaneousGesture(
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
            )
            .animation(.interactiveSpring, value: dragOffset)
        } else {
            innerContent
        }
    }

    private var innerContent: some View {
        ZStack(alignment: .top) {
            OnboardingGradientBackground()
                .ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
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
            if showBottomBar && AppearanceStore.navigationType == .airyBar {
                transactionsBottomBar
                    .frame(maxWidth: .infinity)
            }
        }
        .ignoresSafeArea(.container, edges: showBottomBar ? .bottom : [])
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    print("[Tap] TransactionList → Back")
                    if let back = onBack { back() }
                    else if let d = onDismiss { d() }
                    else { dismiss() }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
            ToolbarItem(placement: .principal) {
                Text(L("txlist_title"))
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(theme.textTertiary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    print("[Tap] TransactionList → Calendar")
                    let now = Date()
                    let cal = Calendar.current
                    let y = cal.component(.year, from: now)
                    let m = cal.component(.month, from: now)
                    let key = String(format: "%04d-%02d", y, m)
                    let label = AppFormatters.monthYear.string(from: now)
                    let dest = MonthDetailDestination(monthKey: key, monthLabel: label)
                    if showBottomBar {
                        monthPath = [dest]
                    } else {
                        selectedMonth = dest
                    }
                } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
        }
        .modifier(MonthDetailDestinationModifier(
            showBottomBar: showBottomBar,
            monthPath: $monthPath,
            selectedMonth: $selectedMonth,
            theme: theme
        ))
        .sheet(isPresented: $showAddTransaction, onDismiss: {
            if addSheetDidSave {
                Task { await viewModel.load() }
                addSheetDidSave = false
            }
        }) {
            AddTransactionView(initialQuickPickOrder: addSheetQuickPickOrder, onSuccess: {
                addSheetDidSave = true
            })
            .themed(theme)
        }
        .sheet(item: $selectedTransactionForEdit) { tx in
            AddTransactionView(transaction: tx, onSuccess: {
                let editedId = tx.id
                selectedTransactionForEdit = nil
                viewModel.updateLocally(id: editedId)
            })
            .themed(theme)
        }
        .onAppear { print("[Nav] TransactionList (showBottomBar=\(showBottomBar))") }
        .task {
            await viewModel.load()
            if let text = initialSearchText {
                localSearchText = text
                viewModel.searchText = text
                if viewModel.hasMore { await viewModel.loadRemaining() }
            }
            if let catId = initialCategoryFilter {
                viewModel.selectedFilterId = catId
            }
        }
        .task(id: localSearchText) {
            try? await Task.sleep(for: .milliseconds(300))
            viewModel.searchText = localSearchText
            if !localSearchText.trimmingCharacters(in: .whitespaces).isEmpty && viewModel.hasMore {
                await viewModel.loadRemaining()
            }
        }
        .onChange(of: isSearchFocused) { _, focused in
            if focused { print("[Input] TransactionList → Search focused") }
        }
        .onChange(of: viewModel.selectedFilterId) { _, newValue in
            if let id = newValue { print("[Tap] TransactionList → Filter '\(id)'") }
            if newValue != nil && viewModel.hasMore {
                Task { await viewModel.loadRemaining() }
            }
        }
        .sensoryFeedback(.warning, trigger: deletingTransactionIds.count)
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
        Text(L("txlist_header"))
            .font(.system(size: 34, weight: .light))
            .tracking(-0.5)
            .lineSpacing(2)
            .foregroundColor(theme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Search

    private var searchSection: some View {
        ZStack(alignment: .leading) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18))
                .foregroundColor(theme.textTertiary)
                .padding(.leading, 16)
                .accessibilityHidden(true)
            TextField("", text: $localSearchText, prompt: Text(L("txlist_search")).foregroundStyle(theme.textTertiary))
                .font(.system(size: 15))
                .foregroundColor(theme.textPrimary)
                .padding(.horizontal, 16)
                .padding(.leading, 44)
                .padding(.vertical, 14)
                .background(Color.white.opacity(theme.isDark ? 0.05 : 0.3))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(theme.glassBorder, lineWidth: 1)
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
                            .foregroundColor(isActive ? .white : theme.textSecondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(isActive ? theme.accentGreen : theme.glassBg)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(isActive ? theme.accentGreen : theme.glassBorder, lineWidth: 1)
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
                Text(L("txlist_no_transactions"))
                    .font(.system(size: 14))
                    .foregroundColor(theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            } else {
                ForEach(viewModel.groupedByMonth) { group in
                    monthSection(group: group)
                }
                if viewModel.hasMore && viewModel.selectedFilterId == nil && viewModel.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .onAppear {
                            guard !viewModel.isLoadingMore else { return }
                            Task { await viewModel.load(append: true) }
                        }
                }
            }
        }
    }

    // MARK: - Pinned section

    private var pinnedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("txlist_pinned"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(theme.textPrimary)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            ForEach(viewModel.pinnedTransactions.filter { !deletingTransactionIds.contains($0.id) }) { tx in
                pinnedTransactionCard(tx: tx)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.98)),
                        removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .center))
                    ))
                    .onTapGesture {
                        print("[Tap] TransactionList → Transaction '\(tx.merchant ?? tx.category)'")
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
                .fill(Color.white.opacity(theme.isDark ? 0.03 : 0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 32)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                        .foregroundColor(theme.glassBorder)
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
                        .foregroundColor(theme.textPrimary)
                        .lineLimit(1)
                    categoryBadge(tx.category, isSubscription: tx.isSubscription == true)
                    Spacer(minLength: 0)
                }
                Text(subtitleForTransaction(tx))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(theme.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(amountString(tx))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(tx.type.lowercased() == "income" ? theme.incomeColor : theme.expenseColor)
            Image(systemName: "pin.fill")
                .font(.system(size: 10))
                .foregroundColor(theme.textTertiary)
        }
        .padding(16)
        .background(Color.white.opacity(theme.isDark ? 0.08 : 0.6))
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .shadow(color: theme.isDark ? Color.black.opacity(0.3) : theme.textPrimary.opacity(0.04), radius: 20, x: 0, y: 10)
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(theme.glassBorder, lineWidth: 1)
        )
    }

    private func monthSection(group: TransactionMonthGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                print("[Tap] TransactionList → Month '\(group.monthLabel)'")
                let dest = MonthDetailDestination(monthKey: group.id, monthLabel: group.monthLabel)
                if showBottomBar {
                    monthPath = [dest]
                } else {
                    selectedMonth = dest
                }
            } label: {
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
                .foregroundColor(theme.textPrimary)
            Spacer()
            Text(AppFormatters.formatTotal(amount: total, currency: BaseCurrencyStore.baseCurrency))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(theme.textSecondary)
        }
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
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
                        .foregroundColor(theme.textPrimary)
                        .lineLimit(1)
                    categoryBadge(tx.category, isSubscription: tx.isSubscription == true)
                    if tx.isSubscription == true {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 14))
                            .foregroundColor(theme.accentBlue.opacity(0.8))
                    }
                    Spacer(minLength: 0)
                }
                Text(subtitleForTransaction(tx))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(theme.textTertiary)
                    .lineLimit(1)
                if isWarning {
                    Text(L("txlist_possible_duplicate"))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(theme.accentWarning)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .center, spacing: 8) {
                Text(amountString(tx))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(tx.type.lowercased() == "income" ? theme.incomeColor : theme.expenseColor)
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(theme.textTertiary.opacity(0.6))
            }
        }
        .padding(16)
        .modifier(TransactionsGlassModifier())
        .background {
            if isWarning {
                RoundedRectangle(cornerRadius: 28)
                    .fill(theme.accentWarning.opacity(0.08))
            }
        }
        .overlay {
            if isWarning {
                RoundedRectangle(cornerRadius: 28)
                    .stroke(theme.accentWarning.opacity(0.3), lineWidth: 1)
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
            Label(viewModel.isPinned(tx) ? L("txlist_unpin") : L("txlist_pin"), systemImage: "bookmark")
        }
        Button(role: .destructive) {
            let id = tx.id
            try? LocalDataStore.shared.deleteTransaction(id: id)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                viewModel.removeLocally(id: id)
            }
        } label: {
            Label(L("common_delete"), systemImage: "trash")
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
            return (theme.accentWarning.opacity(0.15), theme.accentWarning)
        }
        let color = CategoryIconHelper.color(categoryId: category)
        return (color.opacity(0.15), color)
    }

    private func transactionDisplayName(_ tx: Transaction) -> String {
        CategoryIconHelper.transactionDisplayName(merchant: tx.merchant, subcategory: tx.subcategory, categoryId: tx.category)
    }

    private func subtitleForTransaction(_ tx: Transaction) -> String {
        let dateStr = String(tx.transactionDate.prefix(10))
        guard let d = AppFormatters.inputDate.date(from: dateStr) else { return tx.transactionDate }
        var sub = AppFormatters.shortMonthDay.string(from: d)
        if let note = tx.title, !note.isEmpty {
            sub += " • \(note)"
        }
        return sub
    }

    private func amountString(_ tx: Transaction) -> String {
        AppFormatters.formatTransaction(amount: tx.amountOriginal, currency: tx.currencyOriginal, isIncome: tx.type.lowercased() == "income")
    }
}

// MARK: - Glass modifier

private struct TransactionsGlassModifier: ViewModifier {
    @Environment(ThemeProvider.self) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background(reduceTransparency ? AnyShapeStyle(Color(.secondarySystemGroupedBackground)) : theme.isDark ? AnyShapeStyle(theme.glassBg) : AnyShapeStyle(.ultraThinMaterial))
            .overlay(reduceTransparency || theme.isDark ? nil : theme.glassBg.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .stroke(theme.glassBorder, lineWidth: 1)
                    .allowsHitTesting(false)
            )
            .shadow(color: theme.isDark ? Color.black.opacity(0.4) : theme.textPrimary.opacity(0.06), radius: 16, x: 0, y: 8)
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .stroke(Color.white.opacity(theme.isDark ? 0.05 : 0.2), lineWidth: 1)
                    .blur(radius: 0)
                    .offset(y: 1)
                    .allowsHitTesting(false)
            )
    }
}

/// Registers the right navigationDestination variant to avoid duplicate registration warnings.
/// - showBottomBar == true  → path-based (for: MonthDetailDestination) using monthPath
/// - showBottomBar == false → item-based ($selectedMonth binding) for push from parent stack
private struct MonthDetailDestinationModifier: ViewModifier {
    let showBottomBar: Bool
    @Binding var monthPath: [MonthDetailDestination]
    @Binding var selectedMonth: MonthDetailDestination?
    let theme: ThemeProvider

    func body(content: Content) -> some View {
        if showBottomBar {
            content
                .navigationDestination(for: MonthDetailDestination.self) { dest in
                    MonthDetailView(monthKey: dest.monthKey, monthLabel: dest.monthLabel, monthPath: $monthPath)
                        .environment(theme)
                }
        } else {
            content
                .navigationDestination(item: $selectedMonth) { dest in
                    MonthDetailView(monthKey: dest.monthKey, monthLabel: dest.monthLabel)
                        .environment(theme)
                }
        }
    }
}

#Preview {
    TransactionListView()
}
