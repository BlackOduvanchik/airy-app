//
//  Category.swift
//  Airy
//
//  Category model with color support. Top-level categories; subcategories use Subcategory model.
//

import SwiftUI
import UIKit

struct Category: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var colorHex: String
    var iconName: String?

    init(id: String = UUID().uuidString, name: String, colorHex: String, iconName: String? = nil) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.iconName = iconName
    }

    var color: Color {
        Color(hex: colorHex) ?? OnboardingDesign.accentGreen
    }
}

// MARK: - Color hex extension

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        let r = Double((rgb & 0xFF0000) >> 16) / 255
        let g = Double((rgb & 0x00FF00) >> 8) / 255
        let b = Double(rgb & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b)
    }

    func toHex() -> String {
        let uic = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uic.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

// MARK: - CategoryStore

enum CategoryStore {
    private static let key = "airy.categories"

    static let defaultColorGreen = "#67A082"
    static let defaultColorBlue = "#7B9DAB"
    static let defaultColorAmber = "#C4956A"
    static let defaultColorRed = "#E07A7A"
    static let defaultColorPurple = "#9B7EC8"
    static let defaultColorGray = "#8AA396"

    static let presetColors: [String] = [
        defaultColorGreen,
        defaultColorBlue,
        defaultColorAmber,
        defaultColorRed,
        defaultColorPurple,
        "#5B8A9E",
        "#6B9B7A",
        "#B87D5B",
    ]

    static func load() -> [Category] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Category].self, from: data),
              !decoded.isEmpty else {
            return defaultCategories()
        }
        return decoded
    }

    static func save(_ categories: [Category]) {
        guard let data = try? JSONEncoder().encode(categories) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func defaultCategories() -> [Category] {
        [
            Category(id: "food", name: "Food & Dining", colorHex: defaultColorGreen),
            Category(id: "transport", name: "Transport", colorHex: defaultColorBlue),
            Category(id: "housing", name: "Housing", colorHex: defaultColorAmber),
            Category(id: "health", name: "Health", colorHex: defaultColorRed),
            Category(id: "shopping", name: "Shopping", colorHex: defaultColorPurple),
            Category(id: "bills", name: "Bills", colorHex: defaultColorAmber),
            Category(id: "other", name: "Other", colorHex: defaultColorGray),
        ]
    }

    static func ensureDefaults() {
        var current = load()
        if current.isEmpty {
            current = defaultCategories()
            save(current)
        }
        seedDefaultSubcategoriesIfNeeded()
    }

    private static let seededKey = "airy.subcategories_seeded"
    private static func seedDefaultSubcategoriesIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }
        let defaults: [(String, String)] = [
            ("food", "Restaurants"),
            ("food", "Groceries"),
            ("food", "Bars"),
            ("transport", "Taxi & Rideshare"),
            ("transport", "Fuel"),
            ("transport", "Public Transit"),
            ("transport", "Parking"),
            ("housing", "Rent"),
            ("housing", "Utilities"),
            ("housing", "Insurance"),
        ]
        for (parentId, name) in defaults {
            SubcategoryStore.add(Subcategory(name: name, parentCategoryId: parentId))
        }
        UserDefaults.standard.set(true, forKey: seededKey)
    }

    static func add(_ category: Category) {
        var list = load()
        if list.isEmpty { list = defaultCategories() }
        list.append(category)
        save(list)
    }

    static func update(_ category: Category) {
        var list = load()
        if let idx = list.firstIndex(where: { $0.id == category.id }) {
            list[idx] = category
            save(list)
        }
    }

    static func delete(id: String) {
        var list = load()
        list.removeAll { $0.id == id }
        save(list)
        SubcategoryStore.deleteByParent(parentCategoryId: id)
    }

    static func reorder(_ categories: [Category]) {
        save(categories)
    }

    static func byId(_ id: String) -> Category? {
        load().first { $0.id == id }
    }
}

// MARK: - Last used categories (for Add Transaction quick pick)

enum LastUsedCategoriesStore {
    private static let key = "airy.lastUsedCategoryIds"
    private static let maxCount = 3

    static func recordUsed(categoryId: String) {
        var list = load()
        list.removeAll { $0 == categoryId }
        list.insert(categoryId, at: 0)
        list = Array(list.prefix(maxCount))
        UserDefaults.standard.set(list, forKey: key)
    }

    static func load() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    /// Returns up to 3 category IDs for quick pick (excluding "other"). Fills with defaults if needed.
    static func forQuickPick() -> [String] {
        let used = load().filter { $0 != "other" }
        let defaults = ["food", "transport", "housing"]
        var result = used
        for d in defaults where result.count < maxCount && !result.contains(d) {
            result.append(d)
        }
        return Array(result.prefix(maxCount))
    }
}

