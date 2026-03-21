//
//  SettingsView.swift
//  Airy
//
//  Settings screen: Pro card, Display, Data, Notifications, Security, Support, Account.
//

import SwiftUI
import UserNotifications

private enum SettingsDesign {
    static let textDanger = Color(red: 0.84, green: 0.43, blue: 0.43) // #D66E6E
}

struct SettingsView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(ThemeProvider.self) private var theme
    @State private var showPaywall = false
    @State private var iCloudSyncOn: Bool
    @State private var monthlySummaryOn: Bool
    @State private var subscriptionAlertsOn: Bool
    @State private var showDeleteConfirmation = false
    @State private var baseCurrency: String = BaseCurrencyStore.baseCurrency
    @State private var themeName: String = AppearanceStore.colorTheme.displayName

    init() {
        _iCloudSyncOn = State(initialValue: UserDefaults.standard.object(forKey: "airy.settings.icloudSync") as? Bool ?? true)
        _monthlySummaryOn = State(initialValue: UserDefaults.standard.object(forKey: "airy.settings.monthlySummary") as? Bool ?? true)
        _subscriptionAlertsOn = State(initialValue: UserDefaults.standard.object(forKey: "airy.settings.subAlerts") as? Bool ?? true)
    }

    var body: some View {
        ZStack(alignment: .top) {
            OnboardingGradientBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    proCardSection
                    displaySection
                    dataSection
                    notificationsSection
                    securitySection
                    supportSection
                    accountSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(L("settings_title"))
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(theme.textTertiary)
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environment(theme)
        }
        .alert(L("settings_delete_all"), isPresented: $showDeleteConfirmation) {
            Button(L("common_delete"), role: .destructive) {
                LocalDataStore.shared.deleteAllData()
                authStore.logout()
            }
            Button(L("common_cancel"), role: .cancel) {}
        } message: {
            Text(L("settings_delete_confirm"))
        }
        .onAppear {
            baseCurrency = BaseCurrencyStore.baseCurrency
            themeName = AppearanceStore.colorTheme.displayName
        }
        .onChange(of: baseCurrency) { _, v in BaseCurrencyStore.baseCurrency = v }
        .onChange(of: iCloudSyncOn) { _, on in
            UserDefaults.standard.set(on, forKey: "airy.settings.icloudSync")
            Self.setICloudBackupExclusion(!on)
        }
        .onChange(of: monthlySummaryOn) { _, on in
            UserDefaults.standard.set(on, forKey: "airy.settings.monthlySummary")
            if on { Self.scheduleMonthlySummaryNotification() }
            else { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["airy.monthly-summary"]) }
        }
        .onChange(of: subscriptionAlertsOn) { _, on in
            UserDefaults.standard.set(on, forKey: "airy.settings.subAlerts")
            if !on { Self.cancelAllSubscriptionReminders() }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        Text(L("settings_header"))
            .font(.system(size: 40, weight: .light))
            .tracking(-1)
            .foregroundColor(theme.textPrimary)
            .padding(.top, 4)
            .padding(.bottom, 10)
    }

    // MARK: - Pro card

    private var proCardSection: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(theme.isDark ? 0.10 : 1))
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 24))
                        .foregroundColor(theme.accentBlue)
                )
                .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(L("settings_pro_title"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(theme.textPrimary)
                Text(L("settings_pro_subtitle"))
                    .font(.system(size: 13))
                    .foregroundColor(theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(L("settings_pro_button")) {
                showPaywall = true
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(theme.isDark ? Color.white.opacity(0.15) : theme.accentGreen)
            .clipShape(Capsule())
        }
        .padding(24)
        .background(Color.white.opacity(theme.isDark ? 0.08 : 0.45))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(
                    LinearGradient(
                        colors: [theme.accentBlue, theme.accentGreen],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .shadow(color: theme.textPrimary.opacity(0.06), radius: 16, x: 0, y: 8)
    }

    // MARK: - Display

    private static let currencyNames: [String: String] = [
        "AED": "UAE Dirham", "ARS": "Argentine Peso", "AUD": "Australian Dollar",
        "BRL": "Brazilian Real", "CAD": "Canadian Dollar", "CHF": "Swiss Franc",
        "CNY": "Chinese Yuan", "CZK": "Czech Koruna", "DKK": "Danish Krone",
        "EUR": "Euro", "GBP": "British Pound", "HKD": "Hong Kong Dollar",
        "HUF": "Hungarian Forint", "IDR": "Indonesian Rupiah", "ILS": "Israeli Shekel",
        "INR": "Indian Rupee", "JPY": "Japanese Yen", "KRW": "South Korean Won",
        "MXN": "Mexican Peso", "MYR": "Malaysian Ringgit", "NOK": "Norwegian Krone",
        "NZD": "New Zealand Dollar", "PHP": "Philippine Peso", "PLN": "Polish Zloty",
        "RON": "Romanian Leu", "RUB": "Russian Ruble", "SAR": "Saudi Riyal",
        "SEK": "Swedish Krona", "SGD": "Singapore Dollar", "THB": "Thai Baht",
        "TRY": "Turkish Lira", "TWD": "Taiwan Dollar", "UAH": "Ukrainian Hryvnia",
        "USD": "US Dollar", "VND": "Vietnamese Dong", "ZAR": "South African Rand"
    ]

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionCaption(L("settings_display"))
            settingsGroup {
                NavigationLink {
                    CurrencyPickerView(baseCurrency: $baseCurrency)
                } label: {
                    settingsRow(
                        icon: { Image(systemName: "dollarsign.circle").font(.system(size: 18)).foregroundColor(theme.textSecondary) },
                        title: L("settings_display_currency"),
                        showBottomBorder: true,
                        trailing: { rowControl("\(baseCurrency) · \(Self.currencyNames[baseCurrency] ?? baseCurrency)") }
                    )
                }
                .buttonStyle(.plain)
                NavigationLink {
                    AppearanceView()
                } label: {
                    settingsRow(
                        icon: { themeDotsIcon },
                        title: L("settings_appearance"),
                        showBottomBorder: true,
                        trailing: { rowControl(themeName) }
                    )
                }
                .buttonStyle(.plain)
                NavigationLink {
                    LanguagePickerView()
                } label: {
                    settingsRow(
                        icon: { Image(systemName: "globe").font(.system(size: 18)).foregroundColor(theme.textSecondary) },
                        title: L("settings_language"),
                        showBottomBorder: false,
                        trailing: { rowControl("\(LanguageManager.shared.current.flag) \(LanguageManager.shared.current.nativeName)") }
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 10)
    }

    private var themeDotsIcon: some View {
        HStack(spacing: 4) {
            Circle().fill(theme.bgBottomLeft).frame(width: 8, height: 8)
            Circle().fill(theme.bgTop).frame(width: 8, height: 8)
            Circle().fill(theme.accentBlue).frame(width: 8, height: 8)
        }
        .frame(width: 32, height: 32)
        .background(Color.white.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Data

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionCaption(L("settings_data"))
            settingsGroup {
                NavigationLink {
                    ExportDataView()
                } label: {
                    settingsRow(
                        icon: { Image(systemName: "square.and.arrow.up").font(.system(size: 18)).foregroundColor(theme.textSecondary) },
                        title: L("settings_export"),
                        showBottomBorder: true,
                        trailing: { chevronOnly }
                    )
                }
                .buttonStyle(.plain)
                NavigationLink {
                    ImportDataView()
                } label: {
                    settingsRow(
                        icon: { Image(systemName: "square.and.arrow.down").font(.system(size: 18)).foregroundColor(theme.textSecondary) },
                        title: L("settings_import"),
                        showBottomBorder: true,
                        trailing: { chevronOnly }
                    )
                }
                .buttonStyle(.plain)
                NavigationLink {
                    ManageCategoriesView()
                } label: {
                    settingsRow(
                        icon: { Image(systemName: "folder.fill").font(.system(size: 18)).foregroundColor(theme.textSecondary) },
                        title: L("settings_manage_categories"),
                        showBottomBorder: true,
                        trailing: { chevronOnly }
                    )
                }
                .buttonStyle(.plain)
                settingsRow(
                    icon: { Image(systemName: "cloud.fill").font(.system(size: 18)).foregroundColor(theme.textSecondary) },
                    title: L("settings_icloud"),
                    showBottomBorder: false,
                    trailing: { Toggle("", isOn: $iCloudSyncOn).labelsHidden().tint(theme.accentGreen) }
                )
            }
        }
        .padding(.top, 10)
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionCaption(L("settings_notifications"))
            settingsGroup {
                settingsRow(
                    icon: { Image(systemName: "bell").font(.system(size: 18)).foregroundColor(theme.textSecondary) },
                    title: L("settings_monthly_summary"),
                    showBottomBorder: true,
                    trailing: { Toggle("", isOn: $monthlySummaryOn).labelsHidden().tint(theme.accentGreen) }
                )
                settingsRow(
                    icon: { Image(systemName: "clock").font(.system(size: 18)).foregroundColor(theme.textSecondary) },
                    title: L("settings_sub_alerts"),
                    showBottomBorder: false,
                    trailing: { Toggle("", isOn: $subscriptionAlertsOn).labelsHidden().tint(theme.accentGreen) }
                )
            }
        }
        .padding(.top, 10)
    }

    // MARK: - Security

    private var securitySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionCaption(L("settings_security"))
            settingsGroup {
                NavigationLink {
                    SecurityAccessView()
                } label: {
                    settingsRow(
                        icon: { Image(systemName: "lock.fill").font(.system(size: 18)).foregroundColor(theme.textSecondary) },
                        title: L("settings_faceid"),
                        showBottomBorder: true,
                        trailing: { chevronOnly }
                    )
                }
                .buttonStyle(.plain)
                NavigationLink {
                    PrivacyTermsView()
                } label: {
                    settingsRow(
                        icon: { Image(systemName: "shield.fill").font(.system(size: 18)).foregroundColor(theme.textSecondary) },
                        title: L("settings_privacy"),
                        showBottomBorder: false,
                        trailing: { chevronOnly }
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 10)
    }

    // MARK: - Support

    private var supportSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionCaption(L("settings_support"))
            settingsGroup {
                settingsRow(
                    icon: { Image(systemName: "star").font(.system(size: 18)).foregroundColor(theme.textSecondary) },
                    title: L("settings_rate"),
                    showBottomBorder: true,
                    trailing: { chevronOnly }
                )
                Button {
                    let userId = authStore.userId ?? "unknown"
                    let subject = "Feedback".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Feedback"
                    let body = "User ID: \(userId)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    if let url = URL(string: "mailto:support@getairy.app?subject=\(subject)&body=\(body)") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    settingsRow(
                        icon: { Image(systemName: "bubble.left.fill").font(.system(size: 18)).foregroundColor(theme.textSecondary) },
                        title: L("settings_contact"),
                        showBottomBorder: true,
                        trailing: { chevronOnly }
                    )
                }
                .buttonStyle(.plain)
                NavigationLink {
                    ExtractionDebugReportListView(reports: ImportViewModel.shared.lastExtractionReports)
                } label: {
                    settingsRow(
                        icon: { Image(systemName: "doc.text.magnifyingglass").font(.system(size: 18)).foregroundColor(theme.textSecondary) },
                        title: "Extraction Debug",
                        showBottomBorder: false,
                        trailing: { chevronOnly }
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 10)
    }

    // MARK: - Account

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionCaption(L("settings_account"))
            settingsGroup {
                Button {
                    authStore.logout()
                } label: {
                    dangerRow(icon: "rectangle.portrait.and.arrow.right", title: L("settings_signout"), showBottomBorder: true)
                }
                .buttonStyle(.plain)

                Button {
                    showDeleteConfirmation = true
                } label: {
                    dangerRow(icon: "trash", title: L("settings_delete_all"), showBottomBorder: false)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 10)
    }

    // MARK: - Helpers

    private func sectionCaption(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.5)
            .foregroundColor(theme.textTertiary)
            .padding(.bottom, 8)
    }

    private func settingsGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
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

    private func settingsRow<Icon: View, Trailing: View>(
        @ViewBuilder icon: () -> Icon,
        title: String,
        subtitle: String? = nil,
        showBottomBorder: Bool = true,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            icon()
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(theme.isDark ? 0.08 : 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundColor(theme.textPrimary)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing()
        }
        .padding(.horizontal, 16)
        .frame(height: 64)
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

    private func dangerRow(icon: String, title: String, showBottomBorder: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(SettingsDesign.textDanger)
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(theme.isDark ? 0.08 : 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(title)
                .font(.system(size: 15))
                .foregroundColor(SettingsDesign.textDanger)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(SettingsDesign.textDanger)
        }
        .padding(.horizontal, 16)
        .frame(height: 64)
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

    private func rowControl(_ text: String) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(theme.textSecondary)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(theme.textTertiary)
        }
    }

    private var chevronOnly: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(theme.textTertiary)
    }

    // MARK: - iCloud Backup

    private static func setICloudBackupExclusion(_ exclude: Bool) {
        guard var url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        var values = URLResourceValues()
        values.isExcludedFromBackup = exclude
        try? url.setResourceValues(values)
    }

    // MARK: - Monthly Summary Notification

    private static func scheduleMonthlySummaryNotification() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Monthly Summary"
            content.body = "Your spending summary for last month is ready. Open Airy to review."
            content.sound = .default
            var comps = DateComponents()
            comps.day = 1
            comps.hour = 9
            comps.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let request = UNNotificationRequest(identifier: "airy.monthly-summary", content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
        }
    }

    // MARK: - Cancel Subscription Reminders

    private static func cancelAllSubscriptionReminders() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests.filter { $0.identifier.hasPrefix("sub-reminder-") }.map(\.identifier)
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environment(AuthStore())
    }
}
