//
//  ThemeProvider.swift
//  Airy
//
//  Observable theme provider: holds current color tokens, injected via .environment().
//  Call apply(_:) with animation to smoothly switch themes.
//

import SwiftUI

@Observable @MainActor
final class ThemeProvider {
    // MARK: - Background
    var bgTop: Color
    var bgBottomLeft: Color
    var bgBottomRight: Color
    var glowCenter: Color

    // MARK: - Text
    var textPrimary: Color
    var textSecondary: Color
    var textTertiary: Color

    // MARK: - Accent (dynamic)
    var accentGreen: Color
    var accentBlue: Color

    // MARK: - Accent (static — same in every theme)
    let accentAmber = Color(red: 0.851, green: 0.627, blue: 0.357)
    let accentWarning = Color(red: 0.831, green: 0.639, blue: 0.451)
    let textDanger = Color(red: 0.839, green: 0.478, blue: 0.478)

    // MARK: - Glass
    var glassBg: Color
    var glassBorder: Color
    var glassHighlight: Color
    let aiGlow = Color(red: 0.655, green: 0.545, blue: 0.980)

    // MARK: - Income / Expense (user-customizable)
    var incomeColor: Color
    var expenseColor: Color

    // MARK: - Dark mode flag
    var isDark: Bool

    // MARK: - Current theme
    private(set) var currentTheme: ColorTheme

    // MARK: - Init

    init() {
        let theme = AppearanceStore.colorTheme
        let c = theme.themeColors
        currentTheme = theme
        bgTop = c.bgTop
        bgBottomLeft = c.bgBottomLeft
        bgBottomRight = c.bgBottomRight
        glowCenter = c.glowCenter
        textPrimary = c.textPrimary
        textSecondary = c.textSecondary
        textTertiary = c.textTertiary
        accentGreen = c.accentGreen
        accentBlue = c.accentBlue
        glassBg = c.glassBg
        glassBorder = c.glassBorder
        glassHighlight = c.isDark ? Color.white.opacity(0.1) : Color.white.opacity(0.9)
        isDark = c.isDark
        incomeColor = Color(hex: AppearanceStore.incomeColorHex) ?? Color(red: 0.404, green: 0.627, blue: 0.510)
        expenseColor = Color(hex: AppearanceStore.expenseColorHex) ?? Color(red: 0.839, green: 0.431, blue: 0.431)
    }

    // MARK: - Apply

    func apply(_ theme: ColorTheme) {
        AppearanceStore.colorTheme = theme
        currentTheme = theme
        let c = theme.themeColors
        bgTop = c.bgTop
        bgBottomLeft = c.bgBottomLeft
        bgBottomRight = c.bgBottomRight
        glowCenter = c.glowCenter
        textPrimary = c.textPrimary
        textSecondary = c.textSecondary
        textTertiary = c.textTertiary
        accentGreen = c.accentGreen
        accentBlue = c.accentBlue
        glassBg = c.glassBg
        glassBorder = c.glassBorder
        glassHighlight = c.isDark ? Color.white.opacity(0.1) : Color.white.opacity(0.9)
        isDark = c.isDark
    }

    // MARK: - Income / Expense refresh

    func refreshIncomeExpenseColors() {
        incomeColor = Color(hex: AppearanceStore.incomeColorHex) ?? Color(red: 0.404, green: 0.627, blue: 0.510)
        expenseColor = Color(hex: AppearanceStore.expenseColorHex) ?? Color(red: 0.839, green: 0.431, blue: 0.431)
    }
}
