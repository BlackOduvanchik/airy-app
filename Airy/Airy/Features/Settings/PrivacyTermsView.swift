//
//  PrivacyTermsView.swift
//  Airy
//
//  Privacy & Terms: two cards linking to Privacy Policy and Terms of Use.
//

import SwiftUI

struct PrivacyTermsView: View {
    @Environment(ThemeProvider.self) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            OnboardingGradientBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection

                    NavigationLink {
                        LegalTextView(title: L("privacy_policy_title"), text: LegalTexts.privacyPolicy)
                    } label: {
                        legalCard(
                            icon: "shield",
                            title: L("privacy_policy_title"),
                            subtitle: L("privacy_policy_desc")
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        LegalTextView(title: L("privacy_terms_title"), text: LegalTexts.termsOfUse)
                    } label: {
                        legalCard(
                            icon: "doc.text",
                            title: L("privacy_terms_title"),
                            subtitle: L("privacy_terms_desc")
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
            ToolbarItem(placement: .principal) {
                Text(L("privacy_title"))
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(theme.textTertiary)
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("privacy_caption").uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(theme.textTertiary)
            Text(L("privacy_title"))
                .font(.system(size: 34, weight: .light))
                .tracking(-1)
                .foregroundColor(theme.textPrimary)
        }
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    // MARK: - Card

    private func legalCard(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(theme.accentGreen)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(theme.isDark ? 0.08 : 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(theme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(theme.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(theme.textTertiary)
        }
        .padding(24)
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
}
