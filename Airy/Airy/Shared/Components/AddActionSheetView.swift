//
//  AddActionSheetView.swift
//  Airy
//
//  Bottom sheet for Add Transaction: Add Expense, Add Income, Add Screenshot.
//  Add Screenshot opens second page: explanation, Paste from Clipboard, Open Gallery.
//

import SwiftUI

struct AddActionSheetView: View {
    @Environment(ThemeProvider.self) private var theme
    var onExpense: () -> Void
    var onIncome: () -> Void
    var onPasteFromClipboard: () -> Void
    var onOpenGallery: () -> Void
    var onCancel: () -> Void

    @State private var showScreenshotPage = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(theme.isDark ? 0.15 : 0.5))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 12)

            Text(showScreenshotPage ? L("add_screenshot") : L("add_transaction_title"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(theme.isDark ? theme.textTertiary : Color.white.opacity(0.55))
                .tracking(0.8)
                .padding(.bottom, 2)

            if showScreenshotPage {
                screenshotPageContent
            } else {
                mainPageContent
            }

            Button {
                if showScreenshotPage {
                    showScreenshotPage = false
                } else {
                    onCancel()
                }
            } label: {
                Text(showScreenshotPage ? L("common_back") : L("common_cancel"))
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
            }
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(theme.isDark ? theme.bgTop.opacity(0.65) : Color.white.opacity(0.72))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(theme.isDark ? Color.white.opacity(0.08) : Color.white.opacity(0.85), lineWidth: 1)
                    )
                    .shadow(color: theme.isDark ? Color.black.opacity(0.3) : Color(red: 0.08, green: 0.16, blue: 0.12).opacity(0.07), radius: 8, x: 0, y: 24)
            )
            .buttonStyle(.plain)
            .padding(.top, 6)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private var mainPageContent: some View {
        VStack(spacing: 0) {
            actionRow(
                icon: "plus",
                title: L("add_expense"),
                subtitle: L("add_expense_sub"),
                iconColor: theme.expenseColor,
                iconBg: theme.expenseColor.opacity(theme.isDark ? 0.2 : 0.1)
            ) {
                onExpense()
            }

            divider

            actionRow(
                icon: "arrow.up",
                title: L("add_income"),
                subtitle: L("add_income_sub"),
                iconColor: theme.incomeColor,
                iconBg: theme.incomeColor.opacity(theme.isDark ? 0.2 : 0.12)
            ) {
                onIncome()
            }

            divider

            actionRow(
                icon: "camera.fill",
                title: L("add_screenshot_action"),
                subtitle: L("add_screenshot_sub"),
                iconColor: Color(red: 0.35, green: 0.53, blue: 0.72),
                iconBg: Color(red: 0.36, green: 0.62, blue: 0.76).opacity(theme.isDark ? 0.2 : 0.12)
            ) {
                withAnimation(.easeInOut(duration: 0.25)) { showScreenshotPage = true }
            }
        }
        .background(actionsPanelBackground)
    }

    private var screenshotPageContent: some View {
        VStack(spacing: 0) {
            explanationBlock

            VStack(spacing: 0) {
                actionRow(
                    icon: "doc.on.clipboard",
                    title: L("add_paste"),
                    subtitle: L("add_paste_sub"),
                    iconColor: Color(red: 0.31, green: 0.60, blue: 0.45),
                    iconBg: Color(red: 0.31, green: 0.60, blue: 0.45).opacity(theme.isDark ? 0.2 : 0.12)
                ) {
                    onPasteFromClipboard()
                }

                divider

                actionRow(
                    icon: "photo.on.rectangle.angled",
                    title: L("add_gallery"),
                    subtitle: L("add_gallery_sub"),
                    iconColor: Color(red: 0.35, green: 0.53, blue: 0.72),
                    iconBg: Color(red: 0.36, green: 0.62, blue: 0.76).opacity(theme.isDark ? 0.2 : 0.12)
                ) {
                    onOpenGallery()
                }
            }
            .background(actionsPanelBackground)
        }
    }

    private var explanationBlock: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.35, green: 0.53, blue: 0.72).opacity(theme.isDark ? 0.2 : 0.12))
                    .frame(width: 52, height: 52)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color(red: 0.35, green: 0.53, blue: 0.72).opacity(theme.isDark ? 0.3 : 0.2), lineWidth: 1)
                    )
                Image(systemName: "camera.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(theme.isDark ? theme.accentBlue : Color(red: 0.35, green: 0.53, blue: 0.72))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(L("add_scan_title"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(theme.textPrimary)
                Text(L("add_scan_sub"))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(theme.isDark ? theme.textSecondary : Color(red: 0.48, green: 0.60, blue: 0.54))
                .lineSpacing(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .padding(.horizontal, 2)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(theme.isDark ? theme.bgTop.opacity(0.5) : Color.white.opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(theme.isDark ? Color.white.opacity(0.08) : Color.white.opacity(0.7), lineWidth: 1)
                )
                .shadow(color: theme.isDark ? Color.black.opacity(0.3) : Color(red: 0.08, green: 0.16, blue: 0.12).opacity(0.06), radius: 16, x: 0, y: 4)
        )
        .padding(.bottom, 6)
    }

    private var actionsPanelBackground: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(theme.isDark ? theme.bgTop.opacity(0.65) : Color.white.opacity(0.72))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(theme.isDark ? Color.white.opacity(0.08) : Color.white.opacity(0.85), lineWidth: 1)
            )
            .shadow(color: theme.isDark ? Color.black.opacity(0.4) : Color(red: 0.08, green: 0.16, blue: 0.12).opacity(0.14), radius: 32, x: 0, y: 16)
            .shadow(color: theme.isDark ? Color.black.opacity(0.2) : Color(red: 0.08, green: 0.16, blue: 0.12).opacity(0.06), radius: 8, x: 0, y: 24)
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.isDark ? Color.white.opacity(0.08) : Color(red: 0.78, green: 0.86, blue: 0.82).opacity(0.35))
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
                        .foregroundColor(theme.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(theme.isDark ? theme.textSecondary : Color(red: 0.48, green: 0.60, blue: 0.54))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(theme.isDark ? theme.textTertiary : Color(red: 0.75, green: 0.81, blue: 0.78))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
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
                onPasteFromClipboard: {},
                onOpenGallery: {},
                onCancel: {}
            )
        }
    }
}
