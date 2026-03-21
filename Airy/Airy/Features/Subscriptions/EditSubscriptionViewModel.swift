//
//  EditSubscriptionViewModel.swift
//  Airy
//
//  ViewModel for editing a subscription: icon, color, reminder, cancel.
//

import SwiftUI
@preconcurrency import UserNotifications

private let designColors: [String] = [
    // Pastel
    "#BFE8D2", "#C9D8C5", "#BFE7E3", "#C7DBF7", "#D1D7FA", "#DCCEF8",
    "#F6D1DC", "#F8D6BF", "#F6E7B8", "#EBC9B8", "#D8D2E8", "#E7D1C8",
    // Vivid
    "#34C27A", "#4D8F63", "#22B8B0", "#4A90E2", "#6C7CF0", "#9B6DF2",
    "#EC6FA9", "#F28A6A", "#E9B949", "#D9825B", "#B85FD6", "#D97C8E",
    // Bold
    "#111111", "#FF3B30", "#2F80FF", "#7ED957", "#FF4FA3", "#FF7A1A",
]

@MainActor @Observable
final class EditSubscriptionViewModel {
    let subscription: Subscription
    var iconLetter: String
    var selectedColorHex: String
    var reminderEnabled: Bool = false
    let randomLetters: [String]

    var displayName: String

    var monthlyAmount: Double {
        let interval = subscription.interval.lowercased()
        if interval.hasPrefix("year") || interval.hasPrefix("annual") {
            return subscription.amount / 12
        } else if interval.hasPrefix("week") {
            return subscription.amount * (52.0 / 12.0)
        }
        return subscription.amount
    }

    var formattedMonthlyAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = subscription.currency
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: monthlyAmount)) ?? "\(monthlyAmount)"
    }

    var billDayString: String {
        guard let dateStr = subscription.nextBillingDate, !dateStr.isEmpty else { return "" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        guard let d = f.date(from: String(dateStr.prefix(10))) else { return "" }
        let cal = Calendar.current
        let day = cal.component(.day, from: d)
        return "Bill date \(day)\(daySuffix(day))"
    }

    var isMonthly: Bool {
        let i = subscription.interval.lowercased()
        return !i.hasPrefix("year") && !i.hasPrefix("annual") && !i.hasPrefix("week")
    }

    // MARK: - Insight

    struct InsightItem {
        let icon: String
        let title: String
        let body: String
        enum Style { case savings, tip, stat }
        let style: Style
    }

    var insight: InsightItem? {
        // 1. GPT savings — compute actual savings; skip free plans (price == 0)
        if let gpt = SubscriptionInsightStore.shared.forMerchant(subscription.merchant),
           let best = gpt.alternatives.first(where: { $0.price > 0 }) {
            let altMonthly = Self.normalizeToMonthly(price: best.price, interval: best.interval)
            let actualSavings = monthlyAmount - altMonthly
            if actualSavings > 0.50 {
                let savings = formatCurrency(actualSavings)
                let yearly = formatCurrency(actualSavings * 12)
                return InsightItem(
                    icon: "sparkles",
                    title: "\(best.planName): \(formatCurrency(best.price))/\(best.interval)",
                    body: L("editsub_insight_switch_save", savings, yearly),
                    style: .savings
                )
            }
        }

        // 2. GPT tip only
        if let gpt = SubscriptionInsightStore.shared.forMerchant(subscription.merchant),
           !gpt.tip.isEmpty {
            return InsightItem(icon: "lightbulb.fill", title: gpt.tip, body: "", style: .tip)
        }

        // 3-5. Local stats
        return bestLocalInsight()
    }

    /// Normalize any plan price to monthly equivalent.
    private static func normalizeToMonthly(price: Double, interval: String) -> Double {
        let i = interval.lowercased()
        if i.hasPrefix("year") || i.hasPrefix("annual") { return price / 12 }
        if i.hasPrefix("week") { return price * (52.0 / 12.0) }
        return price
    }

    private func bestLocalInsight() -> InsightItem? {
        let allSubs = LocalDataStore.shared.subscriptionsFromTransactions()

        // 3. Total lifetime cost
        let months = monthsSinceStart()
        if months >= 2 {
            let total = monthlyAmount * Double(months)
            return InsightItem(
                icon: "chart.bar.fill",
                title: L("editsub_insight_total", formatCurrency(total)),
                body: L("editsub_insight_months", "\(months)"),
                style: .stat
            )
        }

        // 4. Share of budget
        if allSubs.count >= 2 {
            let totalMonthly = allSubs.reduce(0.0) { $0 + Self.normalizeMonthly($1) }
            let share = totalMonthly > 0 ? monthlyAmount / totalMonthly * 100 : 0
            if share >= 5 {
                return InsightItem(
                    icon: "chart.pie.fill",
                    title: L("editsub_insight_share", "\(Int(share))"),
                    body: L("editsub_insight_share_detail", formatCurrency(monthlyAmount), formatCurrency(totalMonthly)),
                    style: .stat
                )
            }
        }

        // 5. Rank
        if allSubs.count >= 3 {
            let sorted = allSubs.map { Self.normalizeMonthly($0) }.sorted(by: >)
            if let idx = sorted.firstIndex(where: { abs($0 - monthlyAmount) < 0.01 }) {
                let rank = idx + 1
                if rank <= 3 {
                    return InsightItem(
                        icon: "arrow.up.right",
                        title: L("editsub_insight_rank", "\(rank)"),
                        body: "",
                        style: .stat
                    )
                } else if rank == sorted.count {
                    return InsightItem(
                        icon: "arrow.down.right",
                        title: L("editsub_insight_cheapest"),
                        body: "",
                        style: .stat
                    )
                }
            }
        }

        return nil
    }

    private func monthsSinceStart() -> Int {
        guard let dateStr = subscription.nextBillingDate, !dateStr.isEmpty else { return 0 }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        guard let nextDate = f.date(from: String(dateStr.prefix(10))) else { return 0 }
        let cal = Calendar.current
        // nextBillingDate is the NEXT payment — subtract one interval to get last payment
        let interval = subscription.interval.lowercased()
        let lastPayment: Date
        if interval.hasPrefix("year") || interval.hasPrefix("annual") {
            lastPayment = cal.date(byAdding: .year, value: -1, to: nextDate) ?? nextDate
        } else if interval.hasPrefix("week") {
            lastPayment = cal.date(byAdding: .weekOfYear, value: -1, to: nextDate) ?? nextDate
        } else {
            lastPayment = cal.date(byAdding: .month, value: -1, to: nextDate) ?? nextDate
        }
        // Rough estimate: months from lastPayment to now gives 1 cycle; for lifetime we don't know exact start
        // Use createdAt of the template transaction if available
        let months = max(1, cal.dateComponents([.month], from: lastPayment, to: Date()).month ?? 1)
        return months
    }

    private static func normalizeMonthly(_ sub: Subscription) -> Double {
        let interval = sub.interval.lowercased()
        if interval.hasPrefix("year") || interval.hasPrefix("annual") {
            return sub.amount / 12
        } else if interval.hasPrefix("week") {
            return sub.amount * (52.0 / 12.0)
        }
        return sub.amount
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = subscription.currency
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    var iconColor: Color {
        Color(hex: selectedColorHex) ?? OnboardingDesign.accentBlue
    }

    /// True if iconLetter is an SF Symbol name (contains a dot or is multi-char non-letter).
    var iconIsSFSymbol: Bool {
        iconLetter.count > 1
    }

    static var availableColors: [String] { designColors }

    init(subscription: Subscription) {
        self.subscription = subscription
        self.displayName = subscription.merchant
        self.iconLetter = subscription.iconLetter ?? String(subscription.merchant.prefix(1)).uppercased()
        self.selectedColorHex = subscription.colorHex ?? Self.defaultColorHex(for: subscription.merchant)

        let current = subscription.iconLetter ?? String(subscription.merchant.prefix(1)).uppercased()
        var letters = (65...90).map { String(UnicodeScalar($0)) }.filter { $0 != current }
        letters.shuffle()
        self.randomLetters = [current] + Array(letters.prefix(3))
    }

    /// Fetches the template LocalTransaction and converts to Transaction for edit sheet.
    func templateTransaction() -> Transaction? {
        guard let templateId = subscription.templateTransactionId else { return nil }
        let all = LocalDataStore.shared.fetchTransactions(limit: 500)
        return all.first { $0.id == templateId }
    }

    func save() {
        guard let templateId = subscription.templateTransactionId else { return }
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let merchantToSave = trimmedName.isEmpty ? nil : (trimmedName == subscription.merchant ? nil : trimmedName)
        LocalDataStore.shared.updateSubscriptionTemplate(
            templateId: templateId,
            iconLetter: iconLetter,
            colorHex: selectedColorHex,
            merchant: merchantToSave
        )
    }

    func cancelSubscription() {
        guard let templateId = subscription.templateTransactionId else { return }
        LocalDataStore.shared.cancelSubscription(templateId: templateId)
        cancelReminder()
    }

    func scheduleReminder() {
        guard let dateStr = subscription.nextBillingDate, !dateStr.isEmpty else { return }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        guard let billingDate = f.date(from: String(dateStr.prefix(10))) else { return }
        guard let reminderDate = Calendar.current.date(byAdding: .day, value: -2, to: billingDate) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Upcoming Payment"
        content.body = "\(subscription.merchant) — \(formattedMonthlyAmount) in 2 days"
        content.sound = .default

        var comps = Calendar.current.dateComponents([.year, .month, .day], from: reminderDate)
        comps.hour = 10
        comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: reminderIdentifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            UNUserNotificationCenter.current().add(request)
        }
    }

    func cancelReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reminderIdentifier])
    }

    private var reminderIdentifier: String {
        "sub-reminder-\(subscription.templateTransactionId ?? subscription.id)"
    }

    private func daySuffix(_ day: Int) -> String {
        switch day {
        case 1, 21, 31: return "st"
        case 2, 22: return "nd"
        case 3, 23: return "rd"
        default: return "th"
        }
    }

    private static func defaultColorHex(for merchant: String) -> String {
        let m = merchant.lowercased()
        if m.contains("netflix") { return "#E50914" }
        if m.contains("spotify") { return "#1DB954" }
        if m.contains("chatgpt") || m.contains("openai") { return "#00A67E" }
        if m.contains("headspace") { return "#E07A5F" }
        if m.contains("adobe") { return "#3D5A80" }
        if m.contains("nyt") || m.contains("new york") { return "#000000" }
        return "#7B9DAB"
    }
}
