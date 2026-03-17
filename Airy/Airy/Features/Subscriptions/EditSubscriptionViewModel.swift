//
//  EditSubscriptionViewModel.swift
//  Airy
//
//  ViewModel for editing a subscription: icon, color, reminder, cancel.
//

import SwiftUI
@preconcurrency import UserNotifications

private let designColors: [String] = [
    // Row 1: bright
    "#E50914", "#1DB954", "#0061FF", "#FF9900",
    "#9B51E0", "#00A67E", "#E07A5F", "#000000",
    // Row 2: muted analogues
    "#C4956A", "#67A082", "#3D5A80", "#E8A838",
    "#9B7EC8", "#7B9DAB", "#E07A7A", "#5E7A6B",
]

@MainActor @Observable
final class EditSubscriptionViewModel {
    let subscription: Subscription
    var iconLetter: String
    var selectedColorHex: String
    var reminderEnabled: Bool = false
    let randomLetters: [String]

    var displayName: String {
        subscription.merchant
    }

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

    /// Estimated annual price (20% discount).
    var annualPrice: Double {
        monthlyAmount * 12 * 0.8
    }

    /// Monthly savings if switching to annual.
    var monthlySavings: Double {
        monthlyAmount * 0.2
    }

    var formattedAnnualPrice: String {
        formatCurrency(annualPrice) + "/year"
    }

    var formattedMonthlySavings: String {
        formatCurrency(monthlySavings) + "/mo savings"
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
        self.iconLetter = subscription.iconLetter ?? String(subscription.merchant.prefix(1)).uppercased()
        self.selectedColorHex = subscription.colorHex ?? Self.defaultColorHex(for: subscription.merchant)

        let current = subscription.iconLetter ?? String(subscription.merchant.prefix(1)).uppercased()
        var letters = (65...90).map { String(UnicodeScalar($0)) }.filter { $0 != current }
        letters.shuffle()
        self.randomLetters = Array(letters.prefix(3))
    }

    /// Fetches the template LocalTransaction and converts to Transaction for edit sheet.
    func templateTransaction() -> Transaction? {
        guard let templateId = subscription.templateTransactionId else { return nil }
        let all = LocalDataStore.shared.fetchTransactions(limit: 500)
        return all.first { $0.id == templateId }
    }

    func save() {
        guard let templateId = subscription.templateTransactionId else { return }
        LocalDataStore.shared.updateSubscriptionTemplate(
            templateId: templateId,
            iconLetter: iconLetter,
            colorHex: selectedColorHex
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
