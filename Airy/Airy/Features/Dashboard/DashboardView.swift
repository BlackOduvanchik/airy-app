//
//  DashboardView.swift
//  Airy
//
//  Main home screen after onboarding: total spent, AI summary, category breakdown, recent activity, upcoming bills.
//

import SwiftUI

private enum AnalyticsRoute: Hashable {
    case categoryBreakdown
}

struct DashboardView: View {
    var refreshId: Int = 0
    @Binding var showAllTransactions: Bool
    var onOpenSubscriptions: (() -> Void)? = nil
    var onCloudTapped: (() -> Void)? = nil
    @State private var viewModel = DashboardViewModel()
    @State private var analyticsPath = NavigationPath()
    @State private var pendingTransactionCount = 0

    var body: some View {
        NavigationStack(path: $analyticsPath) {
            ZStack(alignment: .top) {
                OnboardingGradientBackground()

                ScrollView {
                    VStack(spacing: 20) {
                        headerSection
                        aiSummarySection
                        vizSection
                        listSection
                        subsSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 120)
                }
                .scrollIndicators(.hidden)
            }
            .navigationBarHidden(true)
            .navigationDestination(for: AnalyticsRoute.self) { route in
                switch route {
                case .categoryBreakdown:
                    CategoryBreakdownView(refreshId: refreshId)
                }
            }
            .task(id: refreshId) { await viewModel.load() }
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
                    Text("Total spent this month")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(OnboardingDesign.textSecondary)
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
        let isAnalyzing = ImportViewModel.shared.isAnalyzing
        let remaining = ImportViewModel.shared.remainingQueueCount
        let hasUnreviewed = ImportViewModel.shared.hasUnreviewedResults

        let a11yLabel: String = isAnalyzing
            ? (remaining > 0 ? "Analyzing \(remaining) transactions" : "Analyzing transactions")
            : hasUnreviewed ? "Review imported transactions"
            : pendingTransactionCount > 0 ? "\(pendingTransactionCount) transactions pending review"
            : "Import transactions"

        return Button(action: { onCloudTapped?() }) {
            ZStack(alignment: .topTrailing) {
                // Icon — fixed 48×48, halos expand via overlay (don't affect layout)
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.white.opacity(0.9), Color.white.opacity(0.2)],
                                center: .topLeading,
                                startRadius: 0,
                                endRadius: 35
                            )
                        )
                        .frame(width: 48, height: 48)
                        .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1))
                        .shadow(color: OnboardingDesign.accentBlue.opacity(0.3), radius: 8, x: 0, y: 0)
                        .shadow(color: .black.opacity(0.03), radius: 6, x: 0, y: 4)

                    Image(systemName: "cloud.fill")
                        .font(.system(size: 24))
                        .foregroundColor(OnboardingDesign.textPrimary)
                }
                .frame(width: 48, height: 48)
                // Halos expand outward as an overlay — they don't push the badge away
                .overlay {
                    if isAnalyzing {
                        CloudRippleHalosView()
                            .transition(.opacity.animation(.easeInOut(duration: 0.4)))
                            .allowsHitTesting(false)
                    }
                }

                // Badge — anchored to the 48×48 icon's topTrailing corner
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
                            .fill(OnboardingDesign.accentGreen)
                            .frame(width: 16, height: 16)
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .offset(x: 4, y: -4)
                } else if pendingTransactionCount > 0 {
                    ZStack {
                        Circle()
                            .fill(OnboardingDesign.accentBlue)
                            .frame(width: 18, height: 18)
                        Text("\(min(pendingTransactionCount, 99))")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(a11yLabel)
        .accessibilityHint("Tap to manage transaction imports")
        .padding(.bottom, 4)
        .task(id: refreshId) {
            pendingTransactionCount = LocalDataStore.shared.fetchPendingTransactions().count
        }
    }

    private func totalSpentFormatted(_ amount: Double) -> Text {
        let whole = Text(formatCurrencyWhole(amount))
            .font(.system(size: 48, weight: .light))
            .tracking(-1.5)
            .foregroundColor(OnboardingDesign.textPrimary)
        let cents = Text(formatCurrencyCents(amount))
            .font(.system(size: 32, weight: .ultraLight))
            .foregroundColor(OnboardingDesign.textTertiary)
        return Text("\(whole)\(cents)")
    }

    private var totalSpentTitle: some View {
        Group {
            if let month = viewModel.thisMonth {
                totalSpentFormatted(month.totalSpent)
            } else {
                Text(formatCurrencyWithBase(0))
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(OnboardingDesign.textPrimary)
            }
        }
    }

    private var deltaBadgeText: String? {
        guard let month = viewModel.thisMonth else { return nil }
        let diff = month.totalSpent - viewModel.previousMonthSpent
        if diff < 0 {
            return "\(formatCurrency(abs(diff))) less than last month"
        } else if diff > 0 {
            return "\(formatCurrency(diff)) more than last month"
        }
        return nil
    }

    private func deltaBadge(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.down.left")
                .font(.system(size: 14, weight: .medium))
            Text(text)
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundColor(OnboardingDesign.accentGreen)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.5))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(OnboardingDesign.glassHighlight, lineWidth: 1)
        )
    }

    // MARK: - AI Summary

    private var aiSummarySection: some View {
        Group {
            if let line = viewModel.aiSummaryLine {
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 20))
                        .foregroundColor(OnboardingDesign.accentBlue)
                    Text(line)
                        .font(.system(size: 14))
                        .lineSpacing(4)
                        .foregroundColor(OnboardingDesign.textPrimary)
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
            analyticsPath.append(AnalyticsRoute.categoryBreakdown)
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                Text("CATEGORY BREAKDOWN")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(OnboardingDesign.textTertiary)
                vizBar(segments: segments)
                vizLegend(segments: segments)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dashboardGlassStyle()
    }

    private static let fallbackSegments: [(label: String, ratio: CGFloat, color: Color)] = [
        ("Housing", 0.45, OnboardingDesign.accentGreen),
        ("Food", 0.30, OnboardingDesign.accentBlue),
        ("Transit", 0.15, OnboardingDesign.bgBottomRight),
        ("Other", 0.10, Color.white.opacity(0.6))
    ]

    private var categorySegments: [(label: String, ratio: CGFloat, color: Color)] {
        guard let byCat = viewModel.thisMonth?.byCategory, !byCat.isEmpty else {
            return Self.fallbackSegments
        }
        let total = byCat.values.reduce(0, +)
        guard total > 0 else { return Self.fallbackSegments }
        let sorted = byCat.sorted { $0.value > $1.value }
        let fallbackColors: [Color] = [
            OnboardingDesign.accentGreen,
            OnboardingDesign.accentBlue,
            OnboardingDesign.bgBottomRight,
            Color.white.opacity(0.6)
        ]
        return Array(sorted.prefix(4).enumerated().map { i, pair in
            let cat = CategoryStore.byId(pair.key)
            let label = cat?.name ?? pair.key.capitalized
            let color = cat?.color ?? fallbackColors[i % fallbackColors.count]
            return (label: label, ratio: CGFloat(pair.value / total), color: color)
        })
    }

    private func vizBar(segments: [(label: String, ratio: CGFloat, color: Color)]) -> some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, s in
                    RoundedRectangle(cornerRadius: 0)
                        .fill(s.color.opacity(0.8))
                        .frame(width: max(0, geo.size.width * s.ratio))
                }
            }
        }
        .frame(height: 24)
        .background(Color.white.opacity(0.3))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
                        .foregroundColor(OnboardingDesign.textSecondary)
                }
                if segments.last?.label != s.label { Spacer() }
            }
        }
    }

    // MARK: - Recent Activity

    private var listSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("RECENT ACTIVITY")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(OnboardingDesign.textTertiary)
                Spacer()
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16))
                    .foregroundColor(OnboardingDesign.textTertiary)
                    .accessibilityLabel("View all transactions")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
            .accessibilityLabel("Recent activity. View all transactions")
            .onTapGesture {
                showAllTransactions = true
            }

            if viewModel.recentTransactions.isEmpty {
                Text("No recent transactions")
                    .font(.system(size: 14))
                    .foregroundColor(OnboardingDesign.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ForEach(Array(viewModel.recentTransactions.enumerated()), id: \.element.id) { index, tx in
                    VStack(spacing: 0) {
                        recentItem(transaction: tx)
                        if index < viewModel.recentTransactions.count - 1 {
                            Divider()
                                .background(Color.white.opacity(0.3))
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
        let barColor = transaction.isSubscription == true ? OnboardingDesign.accentWarning : CategoryIconHelper.color(categoryId: transaction.category)
        return HStack(alignment: .center, spacing: 16) {
            itemIcon(category: transaction.category, isSubscription: transaction.isSubscription == true)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(CategoryIconHelper.transactionDisplayName(merchant: transaction.merchant, subcategory: transaction.subcategory, categoryId: transaction.category))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(OnboardingDesign.textPrimary)
                    Spacer()
                    Text(formatAmount(transaction.amountOriginal, transaction.currencyOriginal))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(OnboardingDesign.textPrimary)
                }
                GeometryReader { g in
                    let w = g.size.width.isFinite && g.size.width >= 0 ? g.size.width * max(0, barRatio) : 0
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.3))
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
        let iconName = isSubscription ? CategoryIconHelper.subscriptionIconName() : CategoryIconHelper.iconName(categoryId: category)
        let iconColor = isSubscription ? OnboardingDesign.accentWarning : CategoryIconHelper.color(categoryId: category)
        return RoundedRectangle(cornerRadius: 16)
            .fill(Color.white.opacity(0.6))
            .frame(width: 44, height: 44)
            .overlay(
                Image(systemName: iconName)
                    .font(.system(size: 20))
                    .foregroundColor(iconColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(OnboardingDesign.glassHighlight, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.02), radius: 5, x: 0, y: 4)
    }


    // MARK: - Upcoming Bills

    private var subsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("UPCOMING BILLS")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(OnboardingDesign.textTertiary)
                Spacer()
                if onOpenSubscriptions != nil {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16))
                        .foregroundColor(OnboardingDesign.textTertiary)
                        .accessibilityLabel("View all subscriptions")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
            .onTapGesture {
                onOpenSubscriptions?()
            }

            if viewModel.upcomingSubscriptions.isEmpty {
                Text("No upcoming bills")
                    .font(.system(size: 14))
                    .foregroundColor(OnboardingDesign.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.upcomingSubscriptions) { sub in
                            subCard(subscription: sub)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
                }
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 20)
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
                    .foregroundColor(OnboardingDesign.textPrimary)
                    .lineLimit(1)
                Text(monthDay)
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(OnboardingDesign.textTertiary)
            }
            VStack(spacing: 4) {
                Text(formatAmount(subscription.amount, subscription.currency))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(OnboardingDesign.textPrimary)
                if !description.isEmpty {
                    Text(description)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(OnboardingDesign.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(16)
        .frame(width: 110)
        .background(Color.white.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    /// Formats nextBillingDate as month and day only (e.g. "Mar 13").
    private func formatMonthDay(_ dateStr: String) -> String? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        guard let d = f.date(from: String(dateStr.prefix(10))) else { return nil }
        let out = DateFormatter()
        out.dateFormat = "MMM d"
        out.timeZone = TimeZone.current
        return out.string(from: d)
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
        return OnboardingDesign.accentBlue
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
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        guard let d = f.date(from: String(dateStr.prefix(10))) else { return nil }
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInTomorrow(d) { return "Tomorrow" }
        let days = cal.dateComponents([.day], from: Date(), to: d).day ?? 0
        if days > 0 && days <= 7 { return "In \(days) days" }
        let out = DateFormatter()
        out.dateFormat = "MMM d, yyyy"
        out.timeZone = TimeZone.current
        return out.string(from: d)
    }

    // MARK: - Helpers

    private func formatCurrency(_ value: Double) -> String {
        formatCurrencyWithBase(value)
    }

    private func formatCurrencyWithBase(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = BaseCurrencyStore.baseCurrency
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }

    private func formatCurrencyWhole(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = BaseCurrencyStore.baseCurrency
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }

    private func formatCurrencyCents(_ value: Double) -> String {
        let cents = Int((value.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: ".%02d", cents)
    }

    private func formatAmount(_ amount: Double, _ currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount) \(currency)"
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
    let delay: Double
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .stroke(OnboardingDesign.accentBlue.opacity(0.4), lineWidth: 1.5)
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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background(reduceTransparency ? AnyShapeStyle(Color(.secondarySystemGroupedBackground)) : AnyShapeStyle(.ultraThinMaterial))
            .overlay(reduceTransparency ? nil : OnboardingDesign.glassBg.opacity(0.5).allowsHitTesting(false))
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

private extension View {
    func dashboardGlassStyle() -> some View {
        modifier(DashboardGlassModifier())
    }
}

#Preview {
    NavigationStack {
        DashboardView(showAllTransactions: .constant(false))
    }
}
