//
//  AppearanceStore.swift
//  Airy
//
//  Persists appearance preferences: color theme, navigation type, income/expense colors.
//

import SwiftUI

// MARK: - Appearance Mode

enum AppearanceMode: String, CaseIterable {
    case light, dark, auto

    @MainActor var displayName: String {
        switch self {
        case .light: L("appearance_mode_light")
        case .dark: L("appearance_mode_dark")
        case .auto: L("appearance_mode_auto")
        }
    }
}

// MARK: - Color Theme

enum ColorTheme: String, CaseIterable {
    case sageMist, oceanBlue, sunsetGlow, midnightDark
    case roseQuartz, lavenderHaze, mintFresh, peachCream
    case electricViolet, berryBlast, coralReef, tropicalTeal
    case snowWhite, warmSand, charcoal, forestNight

    var isDark: Bool {
        switch self {
        case .midnightDark, .electricViolet, .berryBlast, .charcoal, .forestNight: true
        default: false
        }
    }

    static var lightThemes: [ColorTheme] { allCases.filter { !$0.isDark } }
    static var darkThemes: [ColorTheme] { allCases.filter { $0.isDark } }
    static var featuredLight: [ColorTheme] { [.sageMist, .oceanBlue, .sunsetGlow] }
    static var featuredDark: [ColorTheme] { [.midnightDark, .electricViolet, .charcoal] }

    static var featured: [ColorTheme] { [.sageMist, .oceanBlue, .sunsetGlow] }

    var displayName: String {
        switch self {
        case .sageMist: "Sage & Mist"
        case .oceanBlue: "Ocean Blue"
        case .sunsetGlow: "Sunset Glow"
        case .midnightDark: "Midnight Dark"
        case .roseQuartz: "Rose Quartz"
        case .lavenderHaze: "Lavender Haze"
        case .mintFresh: "Mint Fresh"
        case .peachCream: "Peach Cream"
        case .electricViolet: "Electric Violet"
        case .berryBlast: "Berry Blast"
        case .coralReef: "Coral Reef"
        case .tropicalTeal: "Tropical Teal"
        case .snowWhite: "Snow White"
        case .warmSand: "Warm Sand"
        case .charcoal: "Charcoal"
        case .forestNight: "Forest Night"
        }
    }

    var leftHex: String {
        switch self {
        case .sageMist: "#D8E1E6"
        case .oceanBlue: "#C4D7E0"
        case .sunsetGlow: "#F2E3D5"
        case .midnightDark: "#2C3E50"
        case .roseQuartz: "#F0D8DE"
        case .lavenderHaze: "#E0D5ED"
        case .mintFresh: "#D5F0E8"
        case .peachCream: "#F5E6DA"
        case .electricViolet: "#4A1B6E"
        case .berryBlast: "#6B1555"
        case .coralReef: "#F5D5C8"
        case .tropicalTeal: "#D0EEF0"
        case .snowWhite: "#F2F3F5"
        case .warmSand: "#F0EAE0"
        case .charcoal: "#2A2D32"
        case .forestNight: "#1A2E22"
        }
    }

    var rightHex: String {
        switch self {
        case .sageMist: "#8EBAA5"
        case .oceanBlue: "#7B9DAB"
        case .sunsetGlow: "#E5A186"
        case .midnightDark: "#1A252F"
        case .roseQuartz: "#C48B9F"
        case .lavenderHaze: "#9B82B5"
        case .mintFresh: "#6BC4A6"
        case .peachCream: "#E0A882"
        case .electricViolet: "#2A1B4E"
        case .berryBlast: "#3A1535"
        case .coralReef: "#E07B6B"
        case .tropicalTeal: "#40B5B5"
        case .snowWhite: "#D0D5DA"
        case .warmSand: "#C0A880"
        case .charcoal: "#1A1D22"
        case .forestNight: "#0F2018"
        }
    }

    var leftColor: Color { Color(hex: leftHex) ?? .gray }
    var rightColor: Color { Color(hex: rightHex) ?? .gray }

    var themeColors: ThemeColors {
        switch self {
        case .sageMist:
            ThemeColors(
                bgTop: Color(red: 0.847, green: 0.882, blue: 0.902),
                bgBottomLeft: Color(red: 0.557, green: 0.729, blue: 0.647),
                bgBottomRight: Color(red: 0.886, green: 0.871, blue: 0.808),
                textPrimary: Color(red: 0.118, green: 0.176, blue: 0.141),
                textSecondary: Color(red: 0.369, green: 0.478, blue: 0.420),
                textTertiary: Color(red: 0.541, green: 0.639, blue: 0.588),
                accentGreen: Color(red: 0.404, green: 0.627, blue: 0.510),
                accentBlue: Color(red: 0.482, green: 0.616, blue: 0.671),
                glassBg: Color.white.opacity(0.45),
                glassBorder: Color.white.opacity(0.6),
                isDark: false,
                glowCenter: Color.white.opacity(0.8)
            )
        case .oceanBlue:
            ThemeColors(
                bgTop: Color(red: 0.769, green: 0.843, blue: 0.878),
                bgBottomLeft: Color(red: 0.420, green: 0.616, blue: 0.686),
                bgBottomRight: Color(red: 0.816, green: 0.867, blue: 0.894),
                textPrimary: Color(red: 0.102, green: 0.176, blue: 0.227),
                textSecondary: Color(red: 0.290, green: 0.420, blue: 0.478),
                textTertiary: Color(red: 0.478, green: 0.604, blue: 0.671),
                accentGreen: Color(red: 0.353, green: 0.604, blue: 0.710),
                accentBlue: Color(red: 0.357, green: 0.557, blue: 0.659),
                glassBg: Color.white.opacity(0.45),
                glassBorder: Color.white.opacity(0.6),
                isDark: false,
                glowCenter: Color.white.opacity(0.8)
            )
        case .sunsetGlow:
            ThemeColors(
                bgTop: Color(red: 0.949, green: 0.890, blue: 0.835),
                bgBottomLeft: Color(red: 0.831, green: 0.584, blue: 0.431),
                bgBottomRight: Color(red: 0.922, green: 0.831, blue: 0.753),
                textPrimary: Color(red: 0.239, green: 0.157, blue: 0.125),
                textSecondary: Color(red: 0.478, green: 0.353, blue: 0.290),
                textTertiary: Color(red: 0.663, green: 0.537, blue: 0.478),
                accentGreen: Color(red: 0.831, green: 0.522, blue: 0.420),
                accentBlue: Color(red: 0.769, green: 0.604, blue: 0.522),
                glassBg: Color.white.opacity(0.40),
                glassBorder: Color.white.opacity(0.5),
                isDark: false,
                glowCenter: Color.white.opacity(0.8)
            )
        case .midnightDark:
            ThemeColors(
                bgTop: Color(red: 0.102, green: 0.145, blue: 0.184),
                bgBottomLeft: Color(red: 0.086, green: 0.129, blue: 0.169),
                bgBottomRight: Color(red: 0.173, green: 0.243, blue: 0.314),
                textPrimary: Color.white,
                textSecondary: Color(red: 0.741, green: 0.765, blue: 0.780),
                textTertiary: Color(red: 0.498, green: 0.549, blue: 0.553),
                accentGreen: Color(red: 0.180, green: 0.800, blue: 0.443),
                accentBlue: Color(red: 0.204, green: 0.596, blue: 0.859),
                glassBg: Color(red: 0.102, green: 0.145, blue: 0.184).opacity(0.65),
                glassBorder: Color.white.opacity(0.08),
                isDark: true,
                glowCenter: Color(red: 0.173, green: 0.243, blue: 0.314).opacity(0.3)
            )
        case .roseQuartz:
            ThemeColors(
                bgTop: Color(red: 0.941, green: 0.847, blue: 0.871),
                bgBottomLeft: Color(red: 0.769, green: 0.545, blue: 0.624),
                bgBottomRight: Color(red: 0.929, green: 0.835, blue: 0.835),
                textPrimary: Color(red: 0.239, green: 0.122, blue: 0.165),
                textSecondary: Color(red: 0.478, green: 0.290, blue: 0.361),
                textTertiary: Color(red: 0.651, green: 0.478, blue: 0.545),
                accentGreen: Color(red: 0.769, green: 0.478, blue: 0.545),
                accentBlue: Color(red: 0.671, green: 0.478, blue: 0.616),
                glassBg: Color.white.opacity(0.45),
                glassBorder: Color.white.opacity(0.6),
                isDark: false,
                glowCenter: Color.white.opacity(0.8)
            )
        case .lavenderHaze:
            ThemeColors(
                bgTop: Color(red: 0.878, green: 0.835, blue: 0.929),
                bgBottomLeft: Color(red: 0.608, green: 0.510, blue: 0.710),
                bgBottomRight: Color(red: 0.863, green: 0.816, blue: 0.890),
                textPrimary: Color(red: 0.165, green: 0.122, blue: 0.239),
                textSecondary: Color(red: 0.369, green: 0.290, blue: 0.478),
                textTertiary: Color(red: 0.541, green: 0.463, blue: 0.627),
                accentGreen: Color(red: 0.608, green: 0.478, blue: 0.710),
                accentBlue: Color(red: 0.510, green: 0.439, blue: 0.659),
                glassBg: Color.white.opacity(0.45),
                glassBorder: Color.white.opacity(0.6),
                isDark: false,
                glowCenter: Color.white.opacity(0.8)
            )
        case .mintFresh:
            ThemeColors(
                bgTop: Color(red: 0.835, green: 0.941, blue: 0.910),
                bgBottomLeft: Color(red: 0.420, green: 0.769, blue: 0.651),
                bgBottomRight: Color(red: 0.816, green: 0.910, blue: 0.867),
                textPrimary: Color(red: 0.102, green: 0.239, blue: 0.180),
                textSecondary: Color(red: 0.239, green: 0.478, blue: 0.369),
                textTertiary: Color(red: 0.420, green: 0.627, blue: 0.533),
                accentGreen: Color(red: 0.290, green: 0.686, blue: 0.545),
                accentBlue: Color(red: 0.353, green: 0.616, blue: 0.671),
                glassBg: Color.white.opacity(0.45),
                glassBorder: Color.white.opacity(0.6),
                isDark: false,
                glowCenter: Color.white.opacity(0.8)
            )
        case .peachCream:
            ThemeColors(
                bgTop: Color(red: 0.961, green: 0.902, blue: 0.855),
                bgBottomLeft: Color(red: 0.878, green: 0.659, blue: 0.510),
                bgBottomRight: Color(red: 0.941, green: 0.867, blue: 0.816),
                textPrimary: Color(red: 0.239, green: 0.141, blue: 0.094),
                textSecondary: Color(red: 0.478, green: 0.337, blue: 0.251),
                textTertiary: Color(red: 0.659, green: 0.518, blue: 0.416),
                accentGreen: Color(red: 0.816, green: 0.565, blue: 0.439),
                accentBlue: Color(red: 0.753, green: 0.604, blue: 0.502),
                glassBg: Color.white.opacity(0.42),
                glassBorder: Color.white.opacity(0.55),
                isDark: false,
                glowCenter: Color.white.opacity(0.8)
            )
        case .electricViolet:
            ThemeColors(
                bgTop: Color(red: 0.165, green: 0.106, blue: 0.306),
                bgBottomLeft: Color(red: 0.290, green: 0.106, blue: 0.431),
                bgBottomRight: Color(red: 0.227, green: 0.169, blue: 0.369),
                textPrimary: Color.white,
                textSecondary: Color(red: 0.780, green: 0.741, blue: 0.850),
                textTertiary: Color(red: 0.553, green: 0.498, blue: 0.670),
                accentGreen: Color(red: 0.659, green: 0.333, blue: 0.969),
                accentBlue: Color(red: 0.545, green: 0.361, blue: 0.965),
                glassBg: Color(red: 0.165, green: 0.106, blue: 0.306).opacity(0.65),
                glassBorder: Color.white.opacity(0.08),
                isDark: true,
                glowCenter: Color(red: 0.290, green: 0.106, blue: 0.431).opacity(0.3)
            )
        case .berryBlast:
            ThemeColors(
                bgTop: Color(red: 0.227, green: 0.082, blue: 0.208),
                bgBottomLeft: Color(red: 0.420, green: 0.082, blue: 0.333),
                bgBottomRight: Color(red: 0.290, green: 0.145, blue: 0.243),
                textPrimary: Color.white,
                textSecondary: Color(red: 0.850, green: 0.741, blue: 0.820),
                textTertiary: Color(red: 0.620, green: 0.498, blue: 0.580),
                accentGreen: Color(red: 0.918, green: 0.314, blue: 0.580),
                accentBlue: Color(red: 0.780, green: 0.251, blue: 0.560),
                glassBg: Color(red: 0.227, green: 0.082, blue: 0.208).opacity(0.65),
                glassBorder: Color.white.opacity(0.08),
                isDark: true,
                glowCenter: Color(red: 0.420, green: 0.082, blue: 0.333).opacity(0.3)
            )
        case .coralReef:
            ThemeColors(
                bgTop: Color(red: 0.961, green: 0.835, blue: 0.784),
                bgBottomLeft: Color(red: 0.878, green: 0.482, blue: 0.420),
                bgBottomRight: Color(red: 0.937, green: 0.808, blue: 0.753),
                textPrimary: Color(red: 0.239, green: 0.102, blue: 0.078),
                textSecondary: Color(red: 0.541, green: 0.290, blue: 0.243),
                textTertiary: Color(red: 0.690, green: 0.478, blue: 0.431),
                accentGreen: Color(red: 0.878, green: 0.408, blue: 0.314),
                accentBlue: Color(red: 0.816, green: 0.541, blue: 0.478),
                glassBg: Color.white.opacity(0.42),
                glassBorder: Color.white.opacity(0.55),
                isDark: false,
                glowCenter: Color.white.opacity(0.8)
            )
        case .tropicalTeal:
            ThemeColors(
                bgTop: Color(red: 0.816, green: 0.933, blue: 0.941),
                bgBottomLeft: Color(red: 0.251, green: 0.710, blue: 0.710),
                bgBottomRight: Color(red: 0.773, green: 0.898, blue: 0.910),
                textPrimary: Color(red: 0.059, green: 0.239, blue: 0.239),
                textSecondary: Color(red: 0.165, green: 0.439, blue: 0.439),
                textTertiary: Color(red: 0.353, green: 0.604, blue: 0.604),
                accentGreen: Color(red: 0.165, green: 0.659, blue: 0.627),
                accentBlue: Color(red: 0.290, green: 0.671, blue: 0.710),
                glassBg: Color.white.opacity(0.45),
                glassBorder: Color.white.opacity(0.6),
                isDark: false,
                glowCenter: Color.white.opacity(0.8)
            )
        case .snowWhite:
            ThemeColors(
                bgTop: Color(red: 0.949, green: 0.953, blue: 0.961),
                bgBottomLeft: Color(red: 0.816, green: 0.835, blue: 0.855),
                bgBottomRight: Color(red: 0.910, green: 0.918, blue: 0.929),
                textPrimary: Color(red: 0.102, green: 0.114, blue: 0.133),
                textSecondary: Color(red: 0.353, green: 0.376, blue: 0.439),
                textTertiary: Color(red: 0.541, green: 0.565, blue: 0.627),
                accentGreen: Color(red: 0.290, green: 0.565, blue: 0.878),
                accentBlue: Color(red: 0.416, green: 0.541, blue: 0.753),
                glassBg: Color.white.opacity(0.55),
                glassBorder: Color.white.opacity(0.7),
                isDark: false,
                glowCenter: Color.white.opacity(0.8)
            )
        case .warmSand:
            ThemeColors(
                bgTop: Color(red: 0.941, green: 0.918, blue: 0.878),
                bgBottomLeft: Color(red: 0.753, green: 0.659, blue: 0.502),
                bgBottomRight: Color(red: 0.910, green: 0.867, blue: 0.816),
                textPrimary: Color(red: 0.180, green: 0.145, blue: 0.094),
                textSecondary: Color(red: 0.439, green: 0.376, blue: 0.290),
                textTertiary: Color(red: 0.627, green: 0.565, blue: 0.502),
                accentGreen: Color(red: 0.690, green: 0.565, blue: 0.376),
                accentBlue: Color(red: 0.627, green: 0.565, blue: 0.416),
                glassBg: Color.white.opacity(0.48),
                glassBorder: Color.white.opacity(0.6),
                isDark: false,
                glowCenter: Color.white.opacity(0.8)
            )
        case .charcoal:
            ThemeColors(
                bgTop: Color(red: 0.165, green: 0.176, blue: 0.196),
                bgBottomLeft: Color(red: 0.102, green: 0.114, blue: 0.133),
                bgBottomRight: Color(red: 0.208, green: 0.220, blue: 0.243),
                textPrimary: Color.white,
                textSecondary: Color(red: 0.741, green: 0.753, blue: 0.765),
                textTertiary: Color(red: 0.498, green: 0.510, blue: 0.530),
                accentGreen: Color(red: 0.180, green: 0.800, blue: 0.443),
                accentBlue: Color(red: 0.204, green: 0.596, blue: 0.859),
                glassBg: Color(red: 0.165, green: 0.176, blue: 0.196).opacity(0.65),
                glassBorder: Color.white.opacity(0.08),
                isDark: true,
                glowCenter: Color(red: 0.208, green: 0.220, blue: 0.243).opacity(0.3)
            )
        case .forestNight:
            ThemeColors(
                bgTop: Color(red: 0.102, green: 0.180, blue: 0.133),
                bgBottomLeft: Color(red: 0.059, green: 0.125, blue: 0.094),
                bgBottomRight: Color(red: 0.145, green: 0.220, blue: 0.157),
                textPrimary: Color.white,
                textSecondary: Color(red: 0.680, green: 0.800, blue: 0.720),
                textTertiary: Color(red: 0.450, green: 0.580, blue: 0.500),
                accentGreen: Color(red: 0.180, green: 0.820, blue: 0.420),
                accentBlue: Color(red: 0.200, green: 0.700, blue: 0.560),
                glassBg: Color(red: 0.102, green: 0.180, blue: 0.133).opacity(0.65),
                glassBorder: Color.white.opacity(0.08),
                isDark: true,
                glowCenter: Color(red: 0.145, green: 0.220, blue: 0.157).opacity(0.3)
            )
        }
    }
}

// MARK: - Theme Colors

struct ThemeColors {
    let bgTop: Color
    let bgBottomLeft: Color
    let bgBottomRight: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let accentGreen: Color
    let accentBlue: Color
    let glassBg: Color
    let glassBorder: Color
    let isDark: Bool
    let glowCenter: Color
}

// MARK: - Navigation Type

enum NavigationType: String, CaseIterable {
    case airyBar, standardTab

    var displayName: String {
        switch self {
        case .airyBar: "Custom Airy Bar"
        case .standardTab: "Standard Tab Bar"
        }
    }

    @MainActor var subtitle: String {
        switch self {
        case .airyBar: L("nav_type_airy_desc")
        case .standardTab: L("nav_type_standard_desc")
        }
    }
}

// MARK: - Amount Display Format

enum AmountDisplayFormat: String, CaseIterable {
    case symbolGrouped      // $1,234.56
    case symbolPlain        // $1234.56
    case plain              // 1234.56
    case signSymbolPlain    // + $1234.56 / - $1234.56
    case signSymbolGrouped  // + $1,234.56 / - $1,234.56
    case signPlain          // + 1234.56 / - 1234.56

    var showSign: Bool {
        switch self {
        case .symbolGrouped, .symbolPlain, .plain: false
        case .signSymbolPlain, .signSymbolGrouped, .signPlain: true
        }
    }

    var showSymbol: Bool {
        switch self {
        case .symbolGrouped, .symbolPlain, .signSymbolPlain, .signSymbolGrouped: true
        case .plain, .signPlain: false
        }
    }

    var useGrouping: Bool {
        switch self {
        case .symbolGrouped, .signSymbolGrouped: true
        case .symbolPlain, .plain, .signSymbolPlain, .signPlain: false
        }
    }

    func example(sign: String) -> String {
        switch self {
        case .symbolGrouped:     "$1,234.56"
        case .symbolPlain:       "$1234.56"
        case .plain:             "1234.56"
        case .signSymbolPlain:   "\(sign) $1234.56"
        case .signSymbolGrouped: "\(sign) $1,234.56"
        case .signPlain:         "\(sign) 1234.56"
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let navigationTypeChanged = Notification.Name("airy_navigationTypeChanged")
}

// MARK: - Store

enum AppearanceStore {
    private static let themeKey = "airy_colorTheme"
    private static let navKey = "airy_navType"
    private static let incomeKey = "airy_incomeColorHex"
    private static let expenseKey = "airy_expenseColorHex"
    private static let incomeFormatKey = "airy_incomeFormat"
    private static let expenseFormatKey = "airy_expenseFormat"
    private static let modeKey = "airy_appearanceMode"
    private static let lightThemeKey = "airy_lightTheme"
    private static let darkThemeKey = "airy_darkTheme"

    static var colorTheme: ColorTheme {
        get { ColorTheme(rawValue: UserDefaults.standard.string(forKey: themeKey) ?? "") ?? .sageMist }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: themeKey) }
    }

    static var appearanceMode: AppearanceMode {
        get {
            if let raw = UserDefaults.standard.string(forKey: modeKey),
               let mode = AppearanceMode(rawValue: raw) {
                return mode
            }
            // Migration: derive from current theme
            return colorTheme.isDark ? .dark : .light
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: modeKey) }
    }

    static var lightTheme: ColorTheme {
        get {
            if let raw = UserDefaults.standard.string(forKey: lightThemeKey),
               let theme = ColorTheme(rawValue: raw) {
                return theme
            }
            let current = colorTheme
            return current.isDark ? .sageMist : current
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: lightThemeKey) }
    }

    static var darkTheme: ColorTheme {
        get {
            if let raw = UserDefaults.standard.string(forKey: darkThemeKey),
               let theme = ColorTheme(rawValue: raw) {
                return theme
            }
            let current = colorTheme
            return current.isDark ? current : .midnightDark
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: darkThemeKey) }
    }

    static var navigationType: NavigationType {
        get { NavigationType(rawValue: UserDefaults.standard.string(forKey: navKey) ?? "") ?? .airyBar }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: navKey)
            NotificationCenter.default.post(name: .navigationTypeChanged, object: nil)
        }
    }

    static var incomeColorHex: String {
        get { UserDefaults.standard.string(forKey: incomeKey) ?? "#34C27A" }
        set { UserDefaults.standard.set(newValue, forKey: incomeKey) }
    }

    static var expenseColorHex: String {
        get { UserDefaults.standard.string(forKey: expenseKey) ?? "#D97C8E" }
        set { UserDefaults.standard.set(newValue, forKey: expenseKey) }
    }

    static var incomeFormat: AmountDisplayFormat {
        get { AmountDisplayFormat(rawValue: UserDefaults.standard.string(forKey: incomeFormatKey) ?? "") ?? .symbolGrouped }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: incomeFormatKey) }
    }

    static var expenseFormat: AmountDisplayFormat {
        get { AmountDisplayFormat(rawValue: UserDefaults.standard.string(forKey: expenseFormatKey) ?? "") ?? .symbolGrouped }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: expenseFormatKey) }
    }
}
