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

    // MARK: - Current theme & mode
    private(set) var currentTheme: ColorTheme
    var appearanceMode: AppearanceMode

    /// Mode-aware color scheme for `.preferredColorScheme()`.
    /// Returns `nil` in auto mode so `@Environment(\.colorScheme)` reflects
    /// real system changes (sunrise/sunset). Sheets must apply explicit
    /// `.preferredColorScheme(theme.isDark ? .dark : .light)` themselves.
    var preferredScheme: ColorScheme? {
        switch appearanceMode {
        case .light: return .light
        case .dark: return .dark
        case .auto: return nil
        }
    }

    /// Explicit scheme for sheet/fullScreenCover content — always returns
    /// a concrete value so presentations get the correct dark/light styling.
    var presentationScheme: ColorScheme {
        isDark ? .dark : .light
    }

    // MARK: - Init

    init() {
        let mode = AppearanceStore.appearanceMode
        appearanceMode = mode
        let theme: ColorTheme
        switch mode {
        case .light:
            theme = AppearanceStore.lightTheme
        case .dark:
            theme = AppearanceStore.darkTheme
        case .auto:
            let systemIsDark = UITraitCollection.current.userInterfaceStyle == .dark
            theme = systemIsDark ? AppearanceStore.darkTheme : AppearanceStore.lightTheme
        }
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

    // MARK: - Mode

    func setMode(_ mode: AppearanceMode) {
        appearanceMode = mode
        AppearanceStore.appearanceMode = mode
        switch mode {
        case .light:
            apply(AppearanceStore.lightTheme)
        case .dark:
            apply(AppearanceStore.darkTheme)
        case .auto:
            checkSystemAppearance()
        }
    }

    func setLightTheme(_ theme: ColorTheme) {
        AppearanceStore.lightTheme = theme
        if appearanceMode == .light || (appearanceMode == .auto && !isDark) {
            apply(theme)
        }
    }

    func setDarkTheme(_ theme: ColorTheme) {
        AppearanceStore.darkTheme = theme
        if appearanceMode == .dark || (appearanceMode == .auto && isDark) {
            apply(theme)
        }
    }

    func updateForSystemColorScheme(_ colorScheme: ColorScheme) {
        guard appearanceMode == .auto else { return }
        let theme = colorScheme == .dark ? AppearanceStore.darkTheme : AppearanceStore.lightTheme
        guard theme != currentTheme else { return }
        apply(theme)
    }

    /// Re-read the real system appearance from the window scene (not affected
    /// by our `.preferredColorScheme()` override) and apply if changed.
    func checkSystemAppearance() {
        guard appearanceMode == .auto else { return }
        let style = UITraitCollection.current.userInterfaceStyle
        let systemIsDark = style == .dark
        let theme = systemIsDark ? AppearanceStore.darkTheme : AppearanceStore.lightTheme
        guard theme != currentTheme else { return }
        apply(theme)
    }

    // MARK: - Income / Expense refresh

    func refreshIncomeExpenseColors() {
        incomeColor = Color(hex: AppearanceStore.incomeColorHex) ?? Color(red: 0.404, green: 0.627, blue: 0.510)
        expenseColor = Color(hex: AppearanceStore.expenseColorHex) ?? Color(red: 0.839, green: 0.431, blue: 0.431)
    }
}

// MARK: - Presentation helper

extension View {
    /// Apply theme environment + explicit color scheme + tint to sheet/fullScreenCover content.
    /// Use instead of `.environment(theme)` on presentation content.
    func themed(_ theme: ThemeProvider) -> some View {
        self
            .environment(theme)
            .preferredColorScheme(theme.presentationScheme)
            .tint(theme.textPrimary)
    }
}
