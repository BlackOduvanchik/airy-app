//
//  LanguageManager.swift
//  Airy
//
//  Observable singleton for in-app language switching.
//  Views call L("key") which reads `current` — SwiftUI tracks and re-renders on change.
//

import SwiftUI

@Observable @MainActor
final class LanguageManager {
    static let shared = LanguageManager()

    var current: AppLanguage {
        didSet { UserDefaults.standard.set(current.rawValue, forKey: "airy_appLanguage") }
    }

    private let store: [AppLanguage: [String: String]]

    private init() {
        let code = UserDefaults.standard.string(forKey: "airy_appLanguage") ?? "en"
        current = AppLanguage(rawValue: code) ?? .en
        store = [
            .en: translationsEN,
            .ru: translationsRU,
            .uk: translationsUK,
            .be: translationsBE,
            .zhHans: translationsZH,
            .es: translationsES,
            .fr: translationsFR,
            .de: translationsDE,
            .ja: translationsJA,
            .pt: translationsPT,
        ]
    }

    func set(_ language: AppLanguage) {
        current = language
    }

    /// Simple lookup — falls back to English, then to key itself.
    func t(_ key: String) -> String {
        store[current]?[key] ?? store[.en]?[key] ?? key
    }

    /// Parametric lookup — replaces {0}, {1}, … with args.
    func t(_ key: String, _ args: [String]) -> String {
        var result = t(key)
        for (i, arg) in args.enumerated() {
            result = result.replacingOccurrences(of: "{\(i)}", with: arg)
        }
        return result
    }
}

// MARK: - Global helpers

/// Simple translation lookup.
@MainActor func L(_ key: String) -> String {
    LanguageManager.shared.t(key)
}

/// Parametric translation lookup — replaces {0}, {1}, … with args.
@MainActor func L(_ key: String, _ args: String...) -> String {
    LanguageManager.shared.t(key, args)
}
