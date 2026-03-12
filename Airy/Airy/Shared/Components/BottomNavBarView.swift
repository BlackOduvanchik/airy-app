//
//  BottomNavBarView.swift
//  Airy
//
//  Shared bottom nav bar: Insights, FAB, Settings. Same layout on Dashboard and Transactions.
//

import SwiftUI

struct BottomNavBarView: View {
    var onInsights: () -> Void
    var onFab: () -> Void
    var onSettings: () -> Void
    var insightsActive: Bool = false
    var settingsActive: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            navButton(icon: "chart.xyaxis.line", isActive: insightsActive, action: onInsights)
            Spacer()
            fabButton(action: onFab)
            Spacer()
            navButton(icon: "gearshape.fill", isActive: settingsActive, action: onSettings)
        }
        .padding(.horizontal, 32)
        .frame(height: 72)
        .background(
            RoundedRectangle(cornerRadius: 36)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 36)
                        .fill(Color.white.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 36)
                        .stroke(Color.white.opacity(0.8), lineWidth: 1)
                )
                .shadow(color: Color(red: 0.118, green: 0.176, blue: 0.141).opacity(0.08), radius: 24, x: 0, y: 8)
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 30)
    }

    private func navButton(icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(isActive ? OnboardingDesign.textPrimary : OnboardingDesign.textTertiary)
            }
            .frame(width: 48, height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func fabButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Color.clear
                    .frame(width: 88, height: 88)
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white, Color.white.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(Circle().stroke(Color.white, lineWidth: 1))
                        .shadow(color: OnboardingDesign.accentGreen.opacity(0.25), radius: 12, x: 0, y: 6)
                        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 3)
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(OnboardingDesign.textPrimary)
                }
                .frame(width: 68, height: 68)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(y: -24)
    }
}
