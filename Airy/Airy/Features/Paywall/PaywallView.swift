//
//  PaywallView.swift
//  Airy
//
//  Pro subscription paywall. Matches onboarding page 5 design.
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(ThemeProvider.self) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = PaywallViewModel()
    @State private var selectedPlan: Plan = .yearly

    enum Plan { case monthly, yearly }

    var body: some View {
        NavigationStack {
            ZStack {
                OnboardingGradientBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        headerSection
                            .padding(.bottom, 16)

                        featuresCard
                            .padding(.bottom, 16)

                        pricingToggle
                            .padding(.bottom, 12)

                        Text(viewModel.isTrialEligible ? "No charge today · Cancel anytime" : "Cancel anytime")
                            .font(.system(size: 13))
                            .foregroundColor(theme.textTertiary)
                            .padding(.bottom, 4)

                        if let err = viewModel.errorMessage {
                            Text(err)
                                .font(.system(size: 13))
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.bottom, 4)
                        }

                        HStack(spacing: 40) {
                            Button("Restore Purchase") {
                                Task { await viewModel.restore() }
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(theme.textTertiary)
                            .disabled(viewModel.isRestoring)
                        }
                        .padding(.bottom, 16)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .frame(maxWidth: 400)
                }
                .scrollIndicators(.hidden)

                // Subscribe button pinned to bottom
                VStack {
                    Spacer()
                    VStack(spacing: 12) {
                        Button {
                            let productId = selectedPlan == .yearly
                                ? StoreKitService.productIdYearly
                                : StoreKitService.productId
                            Task { await viewModel.purchaseById(productId) }
                        } label: {
                            Text(viewModel.isTrialEligible ? "Start Free 7-Day Trial" : "Subscribe Now")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                        }
                        .background(theme.accentGreen)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1))
                        .shadow(color: theme.accentGreen.opacity(0.2), radius: 12, x: 0, y: 8)
                        .disabled(viewModel.isPurchasing)
                        .overlay {
                            if viewModel.isPurchasing {
                                ProgressView()
                                    .tint(.white)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common_close")) { dismiss() }
                        .foregroundColor(theme.textSecondary)
                }
            }
            .task { await viewModel.loadProducts() }
            .onChange(of: viewModel.didSucceed) { _, ok in
                if ok { dismiss() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .airyEntitlementsDidChange)) { _ in
                viewModel.didSucceed = true
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 0) {
            Text("Think clearly\nabout money.")
                .font(.system(size: 40, weight: .light))
                .tracking(-1)
                .lineSpacing(2)
                .multilineTextAlignment(.center)
                .foregroundColor(theme.textPrimary)
                .padding(.bottom, 8)

            Text("Unlock everything Airy has to offer.")
                .font(.system(size: 15))
                .foregroundColor(theme.textSecondary)
        }
    }

    // MARK: - Features

    private var featuresCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            proFeatureRow(
                iconBg: theme.accentGreen.opacity(0.15),
                iconName: "camera.viewfinder",
                name: "30 Screenshots per Month",
                benefit: "Snap and import your transactions"
            )
            proFeatureRow(
                iconBg: theme.accentBlue.opacity(0.15),
                iconName: "sparkles",
                name: "AI Money Mirror",
                benefit: "Daily reflections on your spending"
            )
            proFeatureRow(
                iconBg: Color.teal.opacity(0.15),
                iconName: "chart.bar",
                name: "Advanced Analytics",
                benefit: "Deep trends and forecasting"
            )
            proFeatureRow(
                iconBg: Color.purple.opacity(0.15),
                iconName: "paintpalette",
                name: "Custom Themes & Colors",
                benefit: "Personalize with premium themes"
            )
            proFeatureRow(
                iconBg: theme.textTertiary.opacity(0.15),
                iconName: "clock",
                name: "Yearly Review",
                benefit: "Comprehensive annual net worth recap"
            )
            proFeatureRow(
                iconBg: Color.indigo.opacity(0.15),
                iconName: "cloud",
                name: "Cloud Sync",
                benefit: "Secure backup across all devices"
            )
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .overlay(theme.glassBg.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(theme.glassBorder, lineWidth: 1)
        )
        .shadow(color: theme.textPrimary.opacity(0.06), radius: 16, x: 0, y: 8)
    }

    private func proFeatureRow(iconBg: Color, iconName: String, name: String, benefit: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(iconBg)
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: iconName)
                        .font(.system(size: 14))
                        .foregroundColor(theme.textPrimary)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(theme.textPrimary)
                Text(benefit)
                    .font(.system(size: 11))
                    .foregroundColor(theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(theme.accentGreen)
        }
    }

    // MARK: - Pricing

    private var pricingToggle: some View {
        VStack(spacing: 10) {
            planOption(plan: .monthly, label: "Monthly", price: monthlyPrice)
            planOption(plan: .yearly, label: "Yearly", price: yearlyPrice, badge: "SAVE 40%")
        }
    }

    private func planOption(plan: Plan, label: String, price: String, badge: String? = nil) -> some View {
        let isSelected = selectedPlan == plan
        return Button {
            withAnimation(.easeOut(duration: 0.2)) { selectedPlan = plan }
        } label: {
            HStack {
                HStack(spacing: 8) {
                    Text(label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color(red: 0.851, green: 0.627, blue: 0.357))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                Spacer()
                Text(price)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(theme.textPrimary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.white.opacity(0.6) : Color.white.opacity(0.3))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(isSelected ? theme.accentGreen : Color.white.opacity(0.5), lineWidth: isSelected ? 1.5 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: isSelected ? theme.accentGreen.opacity(0.2) : .clear, radius: 15, x: 0, y: 0)
        .disabled(viewModel.isPurchasing)
    }

    private var monthlyPrice: String {
        viewModel.products.first(where: { $0.id == StoreKitService.productId })?.displayPrice ?? "$6.99"
    }

    private var yearlyPrice: String {
        viewModel.products.first(where: { $0.id == StoreKitService.productIdYearly })?.displayPrice ?? "$49.99"
    }
}

#Preview {
    PaywallView()
        .environment(ThemeProvider())
}
