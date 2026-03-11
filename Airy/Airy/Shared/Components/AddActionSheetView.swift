//
//  AddActionSheetView.swift
//  Airy
//
//  Bottom sheet for Add Transaction: Add Expense, Add Income, Add Screenshot.
//

import SwiftUI

struct AddActionSheetView: View {
    var onExpense: () -> Void
    var onIncome: () -> Void
    var onScreenshot: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.5))
                .frame(width: 36, height: 4)
                .padding(.top, 6)
                .padding(.bottom, 6)

            Text("ADD TRANSACTION")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.55))
                .tracking(0.8)
                .padding(.bottom, 4)

            VStack(spacing: 0) {
                actionRow(
                    icon: "plus",
                    title: "Add Expense",
                    subtitle: "Log a purchase manually",
                    iconColor: Color(red: 0.85, green: 0.36, blue: 0.32),
                    iconBg: Color(red: 0.94, green: 0.39, blue: 0.35).opacity(0.1)
                ) {
                    onExpense()
                }

                divider

                actionRow(
                    icon: "arrow.up",
                    title: "Add Income",
                    subtitle: "Record a payment received",
                    iconColor: Color(red: 0.31, green: 0.60, blue: 0.45),
                    iconBg: Color(red: 0.31, green: 0.60, blue: 0.45).opacity(0.12)
                ) {
                    onIncome()
                }

                divider

                actionRow(
                    icon: "camera.fill",
                    title: "Add Screenshot",
                    subtitle: "Let Airy read your transactions",
                    iconColor: Color(red: 0.35, green: 0.53, blue: 0.72),
                    iconBg: Color(red: 0.36, green: 0.62, blue: 0.76).opacity(0.12)
                ) {
                    onScreenshot()
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.white.opacity(0.72))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.white.opacity(0.85), lineWidth: 1)
                    )
                    .shadow(color: Color(red: 0.08, green: 0.16, blue: 0.12).opacity(0.14), radius: 32, x: 0, y: 16)
                    .shadow(color: Color(red: 0.08, green: 0.16, blue: 0.12).opacity(0.06), radius: 8, x: 0, y: 24)
            )

            Button {
                onCancel()
            } label: {
                Text("Cancel")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(OnboardingDesign.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
            }
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(0.72))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.white.opacity(0.85), lineWidth: 1)
                    )
                    .shadow(color: Color(red: 0.08, green: 0.16, blue: 0.12).opacity(0.07), radius: 8, x: 0, y: 24)
            )
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 28)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(red: 0.78, green: 0.86, blue: 0.82).opacity(0.35))
            .frame(height: 1)
            .padding(.horizontal, 20)
    }

    private func actionRow(
        icon: String,
        title: String,
        subtitle: String,
        iconColor: Color,
        iconBg: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(iconColor)
                    .frame(width: 48, height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(iconBg)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(OnboardingDesign.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(Color(red: 0.48, green: 0.60, blue: 0.54))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(red: 0.75, green: 0.81, blue: 0.78))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.3).ignoresSafeArea()
        VStack {
            Spacer()
            AddActionSheetView(
                onExpense: {},
                onIncome: {},
                onScreenshot: {},
                onCancel: {}
            )
        }
    }
}
