//
//  SettingsView.swift
//  Airy
//
//  Settings screen: Pro card, Preferences, Data, Notifications, Privacy, Account.
//

import SwiftUI

private enum SettingsDesign {
    static let textDanger = Color(red: 0.84, green: 0.43, blue: 0.43) // #D66E6E
}

struct SettingsView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var showPaywall = false
    @State private var iCloudSyncOn = true
    @State private var monthlySummaryOn = true
    @State private var spendingAlertsOn = false
    @State private var faceIdLockOn = true
    @State private var showDeleteConfirmation = false
    @State private var showAIParsingRules = false

    var body: some View {
        ZStack(alignment: .top) {
            OnboardingGradientBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    proCardSection
                    preferencesSection
                    aiParsingSection
                    dataSection
                    notificationsSection
                    privacySection
                    accountSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .confirmationDialog("Delete All Data", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                authStore.logout()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will sign you out. All data is stored locally on this device.")
        }
        .sheet(isPresented: $showAIParsingRules) {
            AIParsingRulesSheetView()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SETTINGS")
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(OnboardingDesign.textTertiary)
            Text("Your Airy")
                .font(.system(size: 40, weight: .light))
                .tracking(-1)
                .foregroundColor(OnboardingDesign.textPrimary)
        }
        .padding(.top, 20)
        .padding(.bottom, 10)
    }

    // MARK: - Pro card

    private var proCardSection: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white)
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 24))
                        .foregroundColor(OnboardingDesign.accentBlue)
                )
                .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text("Unlock Airy Pro")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(OnboardingDesign.textPrimary)
                Text("Insights, unlimited accounts & more")
                    .font(.system(size: 13))
                    .foregroundColor(OnboardingDesign.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("View Plans") {
                showPaywall = true
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(OnboardingDesign.accentGreen)
            .clipShape(Capsule())
        }
        .padding(24)
        .background(Color.white.opacity(0.45))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(
                    LinearGradient(
                        colors: [OnboardingDesign.accentBlue, OnboardingDesign.accentGreen],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .shadow(color: OnboardingDesign.textPrimary.opacity(0.06), radius: 16, x: 0, y: 8)
    }

    // MARK: - Preferences

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionCaption("Preferences")
            settingsGroup {
                settingsRow(
                    icon: { Text("🇺🇸").font(.system(size: 18)) },
                    title: "Base Currency",
                    showBottomBorder: true,
                    trailing: { rowControl("USD · US Dollar") }
                )
                settingsRow(
                    icon: { themeDotsIcon },
                    title: "Color Theme",
                    showBottomBorder: false,
                    trailing: { rowControl("Sage & Mist") }
                )
            }
        }
        .padding(.top, 10)
    }

    private var themeDotsIcon: some View {
        HStack(spacing: 4) {
            Circle().fill(OnboardingDesign.bgBottomLeft).frame(width: 8, height: 8)
            Circle().fill(OnboardingDesign.bgTop).frame(width: 8, height: 8)
            Circle().fill(OnboardingDesign.accentBlue).frame(width: 8, height: 8)
        }
        .frame(width: 32, height: 32)
        .background(Color.white.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - AI Parsing Rules

    private var aiParsingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionCaption("AI Parsing Rules")
            Button {
                showAIParsingRules = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18))
                        .foregroundColor(OnboardingDesign.accentBlue)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Improve parsing with AI")
                            .font(.system(size: 15))
                            .foregroundColor(OnboardingDesign.textPrimary)
                        Text("Generate rules from sample, use locally")
                            .font(.system(size: 13))
                            .foregroundColor(OnboardingDesign.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(OnboardingDesign.textTertiary)
                }
                .padding(.horizontal, 16)
                .frame(height: 64)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
                .overlay(OnboardingDesign.glassBg.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 28))
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(OnboardingDesign.glassBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 10)
    }

    // MARK: - Data

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionCaption("Data")
            settingsGroup {
                settingsRow(
                    icon: { Image(systemName: "scope").font(.system(size: 18)).foregroundColor(OnboardingDesign.textSecondary) },
                    title: "Merchant Memory Rules",
                    showBottomBorder: true,
                    trailing: { chevronOnly }
                )
                settingsRow(
                    icon: { Image(systemName: "square.and.arrow.down").font(.system(size: 18)).foregroundColor(OnboardingDesign.textSecondary) },
                    title: "Export Data",
                    subtitle: "CSV or JSON",
                    showBottomBorder: true,
                    trailing: { chevronOnly }
                )
                settingsRow(
                    icon: { Image(systemName: "cloud.fill").font(.system(size: 18)).foregroundColor(OnboardingDesign.textSecondary) },
                    title: "iCloud Sync",
                    showBottomBorder: false,
                    trailing: { Toggle("", isOn: $iCloudSyncOn).labelsHidden().tint(OnboardingDesign.accentGreen) }
                )
            }
        }
        .padding(.top, 10)
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionCaption("Notifications")
            settingsGroup {
                settingsRow(
                    icon: { Image(systemName: "bell").font(.system(size: 18)).foregroundColor(OnboardingDesign.textSecondary) },
                    title: "Monthly Summary",
                    subtitle: "Every 1st of month",
                    showBottomBorder: true,
                    trailing: { Toggle("", isOn: $monthlySummaryOn).labelsHidden().tint(OnboardingDesign.accentGreen) }
                )
                settingsRow(
                    icon: { Image(systemName: "bolt").font(.system(size: 18)).foregroundColor(OnboardingDesign.textSecondary) },
                    title: "Spending Alerts",
                    showBottomBorder: false,
                    trailing: { Toggle("", isOn: $spendingAlertsOn).labelsHidden().tint(OnboardingDesign.accentGreen) }
                )
            }
        }
        .padding(.top, 10)
    }

    // MARK: - Privacy

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionCaption("Privacy")
            settingsGroup {
                settingsRow(
                    icon: { Image(systemName: "lock.fill").font(.system(size: 18)).foregroundColor(OnboardingDesign.textSecondary) },
                    title: "Face ID / Passcode Lock",
                    showBottomBorder: true,
                    trailing: { Toggle("", isOn: $faceIdLockOn).labelsHidden().tint(OnboardingDesign.accentGreen) }
                )
                settingsRow(
                    icon: { Image(systemName: "shield.fill").font(.system(size: 18)).foregroundColor(OnboardingDesign.textSecondary) },
                    title: "Data Usage",
                    showBottomBorder: true,
                    trailing: { chevronOnly }
                )
                Button {
                    showDeleteConfirmation = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "trash")
                            .font(.system(size: 18))
                            .foregroundColor(SettingsDesign.textDanger)
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Text("Delete All Data")
                            .font(.system(size: 15))
                            .foregroundColor(SettingsDesign.textDanger)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 10)
    }

    // MARK: - Account (Sign out)

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionCaption("Account")
            settingsGroup {
                if let id = authStore.userId {
                    settingsRow(
                        icon: { Image(systemName: "person.circle").font(.system(size: 18)).foregroundColor(OnboardingDesign.textSecondary) },
                        title: "User ID",
                        subtitle: String(id.prefix(20)) + (id.count > 20 ? "…" : ""),
                        showBottomBorder: true,
                        trailing: { EmptyView() }
                    )
                }
                Button {
                    authStore.logout()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 18))
                            .foregroundColor(OnboardingDesign.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Text("Sign out")
                            .font(.system(size: 15))
                            .foregroundColor(OnboardingDesign.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
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
            .foregroundColor(OnboardingDesign.textTertiary)
            .padding(.bottom, 8)
    }

    private func settingsGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(.ultraThinMaterial)
        .overlay(OnboardingDesign.glassBg.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(OnboardingDesign.glassBorder, lineWidth: 1)
        )
        .shadow(color: OnboardingDesign.textPrimary.opacity(0.06), radius: 16, x: 0, y: 8)
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
                .background(Color.white.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundColor(OnboardingDesign.textPrimary)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(OnboardingDesign.textSecondary)
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
                        .fill(Color.white.opacity(0.3))
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
                .foregroundColor(OnboardingDesign.textSecondary)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(OnboardingDesign.textTertiary)
        }
    }

    private var chevronOnly: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(OnboardingDesign.textTertiary)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environment(AuthStore())
    }
}
