//
//  AppLanguage.swift
//  Airy
//
//  Supported in-app languages.
//

import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case en
    case ru
    case uk
    case be
    case zhHans = "zh-Hans"
    case es
    case fr
    case de
    case ja
    case pt

    var id: String { rawValue }

    var flag: String {
        switch self {
        case .en: return "🇺🇸"
        case .ru: return "🇷🇺"
        case .uk: return "🇺🇦"
        case .be: return "🇧🇾"
        case .zhHans: return "🇨🇳"
        case .es: return "🇪🇸"
        case .fr: return "🇫🇷"
        case .de: return "🇩🇪"
        case .ja: return "🇯🇵"
        case .pt: return "🇧🇷"
        }
    }

    var nativeName: String {
        switch self {
        case .en: return "English"
        case .ru: return "Русский"
        case .uk: return "Українська"
        case .be: return "Беларуская"
        case .zhHans: return "简体中文"
        case .es: return "Español"
        case .fr: return "Français"
        case .de: return "Deutsch"
        case .ja: return "日本語"
        case .pt: return "Português"
        }
    }

    var englishName: String {
        switch self {
        case .en: return "English"
        case .ru: return "Russian"
        case .uk: return "Ukrainian"
        case .be: return "Belarusian"
        case .zhHans: return "Chinese"
        case .es: return "Spanish"
        case .fr: return "French"
        case .de: return "German"
        case .ja: return "Japanese"
        case .pt: return "Portuguese"
        }
    }
}
