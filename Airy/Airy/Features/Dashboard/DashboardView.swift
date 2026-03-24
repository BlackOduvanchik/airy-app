//
//  DashboardView.swift
//  Airy
//
//  Main home screen after onboarding: total spent, AI summary, category breakdown, recent activity, upcoming bills.
//

import SwiftUI

private enum AnalyticsRoute: Hashable, Identifiable {
    case categoryBreakdown
    case allTransactions
    var id: Self { self }
}

// MARK: - DashboardView (NavigationStack path-based push navigation)

struct DashboardView: View {
    @Environment(ThemeProvider.self) private var theme
    var refreshId: Int = 0
    var navResetId: Int = 0
    @Binding var showAllTransactions: Bool
    @Binding var subscriptionsRequested: Bool
    @Binding var cloudTapRequested: Bool
    @State private var path = NavigationPath()
    @State private var editingTransaction: Transaction?
    @State private var editingSubscription: Subscription?

    var body: some View {
        NavigationStack(path: $path) {
            DashboardScrollContent(
                refreshId: refreshId,
                path: $path,
                subscriptionsRequested: $subscriptionsRequested,
                cloudTapRequested: $cloudTapRequested,
                editingTransaction: $editingTransaction,
                editingSubscription: $editingSubscription
            )
            .navigationDestination(for: AnalyticsRoute.self) { route in
                switch route {
                case .categoryBreakdown:
                    CategoryBreakdownView(refreshId: refreshId)
                        .environment(theme)
                case .allTransactions:
                    TransactionListView()
                        .environment(theme)
                }
            }
        }
        .id(navResetId)
        .onChange(of: showAllTransactions) { _, show in
            if show {
                showAllTransactions = false
                path.append(AnalyticsRoute.allTransactions)
            }
        }
        .sheet(item: $editingTransaction) { tx in
            AddTransactionView(transaction: tx, onSuccess: {
                DashboardViewModel.invalidateSubCheck()
                Task { await DashboardViewModel.shared.load() }
            })
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .themed(theme)
        }
        .sheet(item: $editingSubscription) { sub in
            EditSubscriptionView(
                subscription: sub,
                onSave: { DashboardViewModel.invalidateSubCheck(); Task { await DashboardViewModel.shared.load() } },
                onCancel: { DashboardViewModel.invalidateSubCheck(); Task { await DashboardViewModel.shared.load() } }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .themed(theme)
        }
        .environment(theme)
    }
}

// MARK: - DashboardScrollContent (isolates @Observable reads)

private struct DashboardScrollContent: View {
    @Environment(ThemeProvider.self) private var theme
    @State private var viewModel = DashboardViewModel.shared
    var refreshId: Int
    @Binding var path: NavigationPath
    @Binding var subscriptionsRequested: Bool
    @Binding var cloudTapRequested: Bool
    @Binding var editingTransaction: Transaction?
    @Binding var editingSubscription: Subscription?
    @State private var pendingTransactionCount = 0
    @State private var colorVersion = 0

    var body: some View {
        ZStack(alignment: .top) {
            OnboardingGradientBackground()

            ScrollView {
                VStack(spacing: 20) {
                    GeometryReader { geo in
                        Color.clear
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    let frame = geo.frame(in: .global)
                                    let safe = geo.safeAreaInsets
                                    print("[Layout] Dashboard SETTLED: frame.y=\(frame.origin.y) safeArea.top=\(safe.top) frame.size=\(frame.size)")
                                }
                            }
                    }
                    .frame(height: 0)
                    headerSection
                    aiSummarySection
                    vizSection
                    listSection
                    subsSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear { print("[Nav] Dashboard") }
        .task(id: refreshId) {
            await viewModel.load()
            await TransactionListViewModel.shared.preload()
        }
        .onChange(of: path.count) { _, newCount in
            if newCount == 0 {
                colorVersion += 1
            }
        }
    }

    // MARK: - Header (mascot, total spent, badge)

    private var headerSection: some View {
        Group {
            if viewModel.isLoading && viewModel.thisMonth == nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else {
                VStack(spacing: 12) {
                    mascotView
                    Text(L("dashboard_total_spent"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(theme.textSecondary)
                    totalSpentTitle
                    if let deltaText = deltaBadgeText {
                        deltaBadge(deltaText)
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 10)
            }
        }
    }

    private var mascotView: some View {
        ImportStatusBadge(
            pendingCount: pendingTransactionCount,
            refreshId: refreshId,
            onTap: { cloudTapRequested = true },
            onPendingCountLoaded: { pendingTransactionCount = $0 }
        )
        .frame(height: 56)
        .padding(.bottom, 4)
    }

    private func totalSpentFormatted(_ amount: Double) -> Text {
        let whole = Text(formatCurrencyWhole(amount))
            .font(.system(size: 48, weight: .light))
            .tracking(-1.5)
            .foregroundColor(theme.textPrimary)
        let cents = Text(formatCurrencyCents(amount))
            .font(.system(size: 32, weight: .ultraLight))
            .foregroundColor(theme.textTertiary)
        return Text("\(whole)\(cents)")
    }

    private var totalSpentTitle: some View {
        Group {
            if let month = viewModel.thisMonth {
                totalSpentFormatted(month.totalSpent)
            } else {
                Text(formatCurrencyWithBase(0))
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(theme.textPrimary)
            }
        }
    }

    private var deltaBadgeText: String? {
        guard let month = viewModel.thisMonth else { return nil }
        let diff = month.totalSpent - viewModel.previousMonthSpent
        if diff < 0 {
            return L("dashboard_less_than_last", formatCurrency(abs(diff)))
        } else if diff > 0 {
            return L("dashboard_more_than_last", formatCurrency(diff))
        }
        return nil
    }

    private func deltaBadge(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.down.left")
                .font(.system(size: 14, weight: .medium))
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundColor(theme.accentGreen)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.white.opacity(theme.isDark ? 0.08 : 0.5))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(theme.glassHighlight, lineWidth: 1)
        )
    }

    // MARK: - AI Summary

    private var aiSummarySection: some View {
        Group {
            if let line = viewModel.aiSummaryLine {
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 20))
                        .foregroundColor(theme.accentBlue)
                    markdownText(line)
                        .font(.system(size: 14))
                        .lineSpacing(4)
                        .foregroundColor(theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(18)
                .padding(.horizontal, 2)
                .dashboardGlassStyle()
            }
        }
    }

    // MARK: - Category breakdown

    private var vizSection: some View {
        let segments = categorySegments
        return Button {
            print("[Tap] Dashboard → Category Breakdown")
            path.append(AnalyticsRoute.categoryBreakdown)
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(L("dashboard_category_breakdown"))
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(theme.textTertiary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16))
                        .foregroundColor(theme.textTertiary)
                }
                vizBar(segments: segments)
                vizLegend(segments: Array(segments.prefix(4)))
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dashboardGlassStyle()
    }

    private var fallbackSegments: [(label: String, ratio: CGFloat, color: Color)] {
        [
            (L("category_housing"), 0.45, theme.accentGreen),
            (L("category_food"), 0.30, theme.accentBlue),
            (L("category_transit"), 0.15, theme.bgBottomRight),
            (L("category_other"), 0.10, Color.orange.opacity(theme.isDark ? 0.5 : 0.6))
        ]
    }

    private var categorySegments: [(label: String, ratio: CGFloat, color: Color)] {
        _ = colorVersion // force re-evaluation when colors change
        guard let byCat = viewModel.thisMonth?.byCategory, !byCat.isEmpty else {
            return fallbackSegments
        }
        let total = byCat.values.reduce(0, +)
        guard total > 0 else { return fallbackSegments }
        let sorted = byCat.sorted { $0.value > $1.value }
        let fallbackColors: [Color] = [
            theme.accentGreen,
            theme.accentBlue,
            theme.bgBottomRight,
            Color.orange.opacity(theme.isDark ? 0.5 : 0.6),
            Color.purple.opacity(theme.isDark ? 0.5 : 0.6),
            Color.pink.opacity(theme.isDark ? 0.5 : 0.6)
        ]
        return Array(sorted.enumerated().map { i, pair in
            let cat = CategoryStore.byId(pair.key)
            let label = cat?.name ?? pair.key.capitalized
            let color = cat?.color ?? fallbackColors[i % fallbackColors.count]
            return (label: label, ratio: CGFloat(pair.value / total), color: color)
        })
    }

    private func vizBar(segments: [(label: String, ratio: CGFloat, color: Color)]) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                ForEach(Array(segments.enumerated().reversed()), id: \.offset) { index, s in
                    Capsule()
                        .fill(s.color)
                        .frame(
                            width: max(24, segments.prefix(index + 1).reduce(CGFloat(0)) { $0 + geo.size.width * $1.ratio }),
                            height: 24
                        )
                }
            }
        }
        .frame(height: 24)
        .background(Color.white.opacity(theme.isDark ? 0.05 : 0.3))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(theme.isDark ? 0.05 : 0.4), lineWidth: 1)
        )
    }

    private func vizLegend(segments: [(label: String, ratio: CGFloat, color: Color)]) -> some View {
        HStack {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, s in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(s.color.opacity(0.8))
                        .frame(width: 8, height: 8)
                    Text(s.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(theme.textSecondary)
                }
                if segments.last?.label != s.label { Spacer() }
            }
        }
    }

    // MARK: - Recent Activity

    private var listSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L("dashboard_recent_activity"))
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(theme.textTertiary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16))
                    .foregroundColor(theme.textTertiary)
                    .accessibilityLabel(L("dashboard_view_all_transactions"))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
            .accessibilityLabel(L("dashboard_recent_activity_hint"))
            .onTapGesture {
                print("[Tap] Dashboard → All Transactions")
                path.append(AnalyticsRoute.allTransactions)
            }

            if viewModel.recentTransactions.isEmpty {
                Text(L("dashboard_no_recent"))
                    .font(.system(size: 14))
                    .foregroundColor(theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ForEach(Array(viewModel.recentTransactions.enumerated()), id: \.element.id) { index, tx in
                    VStack(spacing: 0) {
                        recentItem(transaction: tx)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                print("[Tap] Dashboard → Edit Transaction '\(tx.merchant ?? tx.category)'")
                                editingTransaction = tx
                            }
                        if index < viewModel.recentTransactions.count - 1 {
                            Divider()
                                .background(Color.white.opacity(theme.isDark ? 0.06 : 0.3))
                                .padding(.leading, 76)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .dashboardGlassStyle()
    }

    private func recentItem(transaction: Transaction) -> some View {
        let total = viewModel.thisMonth?.totalSpent ?? 1
        let txInBase = CurrencyService.amountInBase(amountOriginal: abs(transaction.amountOriginal), currencyOriginal: transaction.currencyOriginal, amountBase: transaction.amountBase, baseCurrency: transaction.baseCurrency)
        let pct = total > 0 ? CGFloat(txInBase / total) : 0.2
        let barRatio = (pct.isFinite && pct >= 0) ? min(1, pct * 3) : 0.2
        let barColor = CategoryIconHelper.color(categoryId: transaction.category)
        return HStack(alignment: .center, spacing: 16) {
            itemIcon(category: transaction.category, isSubscription: transaction.isSubscription == true)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(CategoryIconHelper.transactionDisplayName(merchant: transaction.merchant, subcategory: transaction.subcategory, categoryId: transaction.category))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(theme.textPrimary)
                    Spacer()
                    Text(AppFormatters.formatTransaction(amount: transaction.amountOriginal, currency: transaction.currencyOriginal, isIncome: transaction.type.lowercased() == "income"))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(transaction.type.lowercased() == "income" ? theme.incomeColor : theme.expenseColor)
                }
                GeometryReader { g in
                    let w = g.size.width.isFinite && g.size.width >= 0 ? g.size.width * max(0, barRatio) : 0
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(theme.isDark ? 0.05 : 0.3))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(barColor.opacity(0.8))
                            .frame(width: max(0, w), height: 4)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func itemIcon(category: String, isSubscription: Bool = false) -> some View {
        let iconName = CategoryIconHelper.iconName(categoryId: category)
        let iconColor = CategoryIconHelper.color(categoryId: category)
        return RoundedRectangle(cornerRadius: 16)
            .fill(Color.white.opacity(theme.isDark ? 0.08 : 0.6))
            .frame(width: 44, height: 44)
            .overlay(
                Image(systemName: iconName)
                    .font(.system(size: 20))
                    .foregroundColor(iconColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(theme.glassHighlight, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.02), radius: 5, x: 0, y: 4)
    }


    // MARK: - Upcoming Bills

    private var subsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L("dashboard_upcoming_bills"))
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(theme.textTertiary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16))
                    .foregroundColor(theme.textTertiary)
                    .accessibilityLabel(L("dashboard_view_all_subscriptions"))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
            .onTapGesture {
                subscriptionsRequested = true
            }

            if viewModel.upcomingSubscriptions.isEmpty {
                Text(L("dashboard_no_upcoming"))
                    .font(.system(size: 14))
                    .foregroundColor(theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.upcomingSubscriptions) { sub in
                            subCard(subscription: sub)
                                .onTapGesture {
                                    print("[Tap] Dashboard → Edit Subscription '\(sub.merchant)'")
                                    editingSubscription = sub
                                }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
                }
            }
        }
        .padding(.vertical, 8)
        .dashboardGlassStyle()
    }

    private func subCard(subscription: Subscription) -> some View {
        let monthDay = subscription.nextBillingDate.flatMap { formatMonthDay($0) } ?? "—"
        let subColor = subscription.colorHex.flatMap { Color(hex: $0) } ?? subscriptionFallbackColor(subscription.merchant)
        let subIcon = subscription.iconLetter ?? String(subscription.merchant.prefix(1)).uppercased()
        let isSFSymbol = subIcon.count > 1
        let displayTitle = subscriptionDisplayTitle(subscription: subscription)
        let description = (subscription.title ?? "").trimmingCharacters(in: .whitespaces)
        return VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(subColor)
                .frame(width: 36, height: 36)
                .overlay(
                    Group {
                        if isSFSymbol {
                            Image(systemName: subIcon)
                                .font(.system(size: 16, weight: .bold))
                        } else {
                            Text(subIcon)
                                .font(.system(size: 16, weight: .bold))
                        }
                    }
                    .foregroundColor(.white)
                )
                .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
            VStack(spacing: 2) {
                Text(displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(1)
                Text(monthDay)
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(theme.textTertiary)
            }
            VStack(spacing: 4) {
                Text(formatAmount(subscription.amount, subscription.currency))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(theme.expenseColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !description.isEmpty {
                    Text(description)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(theme.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(16)
        .frame(width: 110, height: 160)
        .background(Color.white.opacity(theme.isDark ? 0.05 : 0.35))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func markdownText(_ string: String) -> Text {
        if let attributed = try? AttributedString(markdown: string) {
            return Text(attributed)
        }
        return Text(string)
    }

    /// Formats nextBillingDate as month and day only (e.g. "Mar 13").
    private func formatMonthDay(_ dateStr: String) -> String? {
        guard let d = AppFormatters.inputDate.date(from: String(dateStr.prefix(10))) else { return nil }
        return AppFormatters.shortMonthDay.string(from: d)
    }

    /// Display name for subscription card: merchant if set, else subcategory name, else category name.
    private func subscriptionFallbackColor(_ merchant: String) -> Color {
        let m = merchant.lowercased()
        if m.contains("netflix") { return Color(red: 0.898, green: 0.035, blue: 0.078) }
        if m.contains("spotify") { return Color(red: 0.114, green: 0.725, blue: 0.329) }
        if m.contains("chatgpt") || m.contains("openai") { return Color(red: 0, green: 0.651, blue: 0.494) }
        if m.contains("headspace") { return Color(red: 0.98, green: 0.365, blue: 0.365) }
        if m.contains("adobe") { return Color(red: 0.176, green: 0.243, blue: 0.314) }
        if m.contains("nyt") || m.contains("new york") { return Color(red: 0.071, green: 0.071, blue: 0.071) }
        return theme.accentBlue
    }

    private func subscriptionDisplayTitle(subscription: Subscription) -> String {
        let m = subscription.merchant.trimmingCharacters(in: .whitespaces)
        if !m.isEmpty, m.lowercased() != "unknown" { return m }
        if let subId = subscription.subcategoryId,
           let name = SubcategoryStore.load().first(where: { $0.id == subId })?.name,
           !name.isEmpty {
            return name
        }
        let catId = subscription.categoryId ?? ""
        let catName = CategoryIconHelper.displayName(categoryId: catId)
        if !catName.isEmpty, catName != "Unknown" { return catName }
        return "Unknown"
    }

    private func formatNextBilling(_ dateStr: String) -> String? {
        guard let d = AppFormatters.inputDate.date(from: String(dateStr.prefix(10))) else { return nil }
        let cal = Calendar.current
        if cal.isDateInToday(d) { return L("common_today") }
        if cal.isDateInTomorrow(d) { return L("common_tomorrow") }
        let days = cal.dateComponents([.day], from: Date(), to: d).day ?? 0
        if days > 0 && days <= 7 { return L("dashboard_in_days", "\(days)") }
        return AppFormatters.monthDayYear.string(from: d)
    }

    // MARK: - Helpers

    private func formatCurrency(_ value: Double) -> String {
        formatCurrencyWithBase(value)
    }

    private func formatCurrencyWithBase(_ value: Double) -> String {
        let formatter = AppFormatters.currency(code: BaseCurrencyStore.baseCurrency, fractionDigits: 0)
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }

    private func formatCurrencyWhole(_ value: Double) -> String {
        AppFormatters.formatTotalWhole(amount: value, currency: BaseCurrencyStore.baseCurrency)
    }

    private func formatCurrencyCents(_ value: Double) -> String {
        AppFormatters.formatTotalCents(value)
    }

    private func formatAmount(_ amount: Double, _ currency: String) -> String {
        AppFormatters.formatTotal(amount: amount, currency: currency)
    }
}

// MARK: - Cloud ripple halos (shown while analyzing)

private struct CloudRippleHalosView: View {
    var body: some View {
        ZStack {
            RippleRingView(delay: 0.0)
            RippleRingView(delay: 0.55)
            RippleRingView(delay: 1.1)
        }
        .frame(width: 120, height: 120)
        .allowsHitTesting(false)
    }
}

private struct RippleRingView: View {
    @Environment(ThemeProvider.self) private var theme
    let delay: Double
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .stroke(theme.accentBlue.opacity(0.4), lineWidth: 1.5)
            .frame(width: 48, height: 48)
            .scaleEffect(isAnimating ? 2.6 : 1.0)
            .opacity(isAnimating ? 0 : 0.55)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(.easeOut(duration: 1.7).repeatForever(autoreverses: false)) {
                        isAnimating = true
                    }
                }
            }
    }
}

// MARK: - Glass panel style for dashboard

private struct DashboardGlassModifier: ViewModifier {
    @Environment(ThemeProvider.self) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background(reduceTransparency ? AnyShapeStyle(Color(.secondarySystemGroupedBackground)) : theme.isDark ? AnyShapeStyle(theme.glassBg) : AnyShapeStyle(.ultraThinMaterial))
            .overlay(reduceTransparency || theme.isDark ? nil : theme.glassBg.opacity(0.5).allowsHitTesting(false))
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

private extension View {
    func dashboardGlassStyle() -> some View {
        modifier(DashboardGlassModifier())
    }
}

// MARK: - Import Status Badge (isolates ImportViewModel @Observable reads)

private struct ImportStatusBadge: View {
    @Environment(ThemeProvider.self) private var theme
    let pendingCount: Int
    let refreshId: Int
    let onTap: () -> Void
    let onPendingCountLoaded: (Int) -> Void

    // These reads are isolated to THIS view's body — only this badge re-renders when ImportViewModel changes
    private var isAnalyzing: Bool { ImportViewModel.shared.isAnalyzing }
    private var remaining: Int { ImportViewModel.shared.remainingQueueCount }
    private var hasUnreviewed: Bool { ImportViewModel.shared.hasUnreviewedResults }

    var body: some View {
        let a11yLabel: String = isAnalyzing
            ? (remaining > 0 ? L("badge_analyzing_count", "\(remaining)") : L("badge_analyzing"))
            : hasUnreviewed ? L("badge_review_imported")
            : pendingCount > 0 ? L("badge_pending_review", "\(pendingCount)")
            : L("badge_import")

        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: theme.isDark
                                    ? [Color.white.opacity(0.15), Color.white.opacity(0.05)]
                                    : [Color.white.opacity(0.9), Color.white.opacity(0.2)],
                                center: .topLeading,
                                startRadius: 0,
                                endRadius: 35
                            )
                        )
                        .frame(width: 48, height: 48)
                        .overlay(Circle().stroke(Color.white.opacity(theme.isDark ? 0.08 : 0.5), lineWidth: 1))
                        .shadow(color: theme.accentBlue.opacity(0.3), radius: 8, x: 0, y: 0)
                        .shadow(color: .black.opacity(0.03), radius: 6, x: 0, y: 4)

                    Image(systemName: "cloud.fill")
                        .font(.system(size: 24))
                        .foregroundColor(theme.textPrimary)
                }
                .frame(width: 48, height: 48)
                .overlay {
                    if isAnalyzing {
                        CloudRippleHalosView()
                            .allowsHitTesting(false)
                    }
                }

                if isAnalyzing && remaining > 0 {
                    ZStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 18, height: 18)
                        Text("\(remaining)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .offset(x: 4, y: -4)
                } else if hasUnreviewed {
                    ZStack {
                        Circle()
                            .fill(theme.accentGreen)
                            .frame(width: 16, height: 16)
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .offset(x: 4, y: -4)
                } else if pendingCount > 0 {
                    ZStack {
                        Circle()
                            .fill(theme.accentBlue)
                            .frame(width: 18, height: 18)
                        Text("\(min(pendingCount, 99))")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .offset(x: 4, y: -4)
                }
            }
            .frame(width: 56, height: 56)
        }
        .buttonStyle(.plain)
        .animation(nil, value: isAnalyzing)
        .accessibilityLabel(a11yLabel)
        .accessibilityHint(L("badge_import_hint"))
        .task(id: refreshId) {
            onPendingCountLoaded(LocalDataStore.shared.fetchPendingTransactions().count)
        }
    }
}

#Preview {
    DashboardView(showAllTransactions: .constant(false), subscriptionsRequested: .constant(false), cloudTapRequested: .constant(false))
}
