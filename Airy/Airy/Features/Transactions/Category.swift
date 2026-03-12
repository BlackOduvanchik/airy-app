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

// MARK: - Shared category icon & color (Dashboard, Transaction list, New Entry, etc.)

enum CategoryIconHelper {
    /// Resolves effective category ID for icon/color. If categoryId is a subcategory id, returns parent.
    static func effectiveCategoryId(categoryId: String, subcategoryId: String? = nil) -> String {
        if let cat = CategoryStore.byId(categoryId) { return cat.id }
        let sub = SubcategoryStore.load().first { $0.id == categoryId }
        return sub?.parentCategoryId ?? categoryId
    }

    /// Icon name for category. For subcategory, uses parent category's icon.
    static func iconName(categoryId: String, subcategoryId: String? = nil) -> String {
        let effectiveId = effectiveCategoryId(categoryId: categoryId, subcategoryId: subcategoryId)
        if let cat = CategoryStore.byId(effectiveId), let icon = cat.iconName { return icon }
        let c = effectiveId.lowercased()
        if c.contains("food") || c.contains("dining") || c.contains("grocer") { return "cup.and.saucer.fill" }
        if c.contains("transport") || c.contains("transit") { return "car.fill" }
        if c.contains("housing") || c.contains("rent") { return "house.fill" }
        if c.contains("shopping") { return "bag.fill" }
        if c.contains("health") { return "heart.fill" }
        if c.contains("bills") { return "doc.text.fill" }
        return "dollarsign"
    }

    /// Icon for subscription transactions.
    static func subscriptionIconName() -> String { "creditcard.fill" }

    /// Color for category. For subcategory, uses parent category's color.
    static func color(categoryId: String, subcategoryId: String? = nil) -> Color {
        let effectiveId = effectiveCategoryId(categoryId: categoryId, subcategoryId: subcategoryId)
        return CategoryStore.byId(effectiveId)?.color ?? fallbackColor(effectiveId)
    }

    private static func fallbackColor(_ categoryId: String) -> Color {
        let c = categoryId.lowercased()
        if c.contains("food") || c.contains("dining") || c.contains("grocer") { return Color(hex: CategoryStore.defaultColorGreen) ?? OnboardingDesign.accentGreen }
        if c.contains("transport") || c.contains("transit") { return Color(hex: CategoryStore.defaultColorBlue) ?? OnboardingDesign.accentBlue }
        if c.contains("housing") || c.contains("rent") { return Color(hex: CategoryStore.defaultColorAmber) ?? OnboardingDesign.accentWarning }
        if c.contains("shopping") { return Color(hex: CategoryStore.defaultColorPurple) ?? OnboardingDesign.accentBlue }
        if c.contains("health") { return Color(hex: CategoryStore.defaultColorRed) ?? OnboardingDesign.textDanger }
        if c.contains("bills") { return Color(hex: CategoryStore.defaultColorAmber) ?? OnboardingDesign.accentWarning }
        return Color(hex: CategoryStore.defaultColorGray) ?? OnboardingDesign.textSecondary
    }

    /// Display name for transaction (merchant, subcategory, or category). Never returns empty.
    static func transactionDisplayName(merchant: String?, subcategory: String?, categoryId: String) -> String {
        let m = merchant?.trimmingCharacters(in: .whitespaces)
        if let x = m, !x.isEmpty, x.lowercased() != "unknown" { return x }
        let s = subcategory?.trimmingCharacters(in: .whitespaces)
        if let x = s, !x.isEmpty { return x }
        let cat = displayName(categoryId: categoryId)
        if !cat.isEmpty { return cat }
        return "Unknown"
    }

    /// Display name for category badge/list. Uses CategoryStore name for custom categories (e.g. Russian names), fallback for legacy ids.
    static func displayName(categoryId: String) -> String {
        if categoryId.isEmpty { return "Unknown" }
        if let cat = CategoryStore.byId(categoryId) { return cat.name }
        let c = categoryId.lowercased()
        if c.contains("food") || c.contains("dining") { return "Dining" }
        if c.contains("transport") || c.contains("transit") { return "Transit" }
        if c.contains("shopping") { return "Shopping" }
        if c.contains("health") { return "Health" }
        if c.contains("housing") { return "Housing" }
        if c.contains("bills") { return "Bills" }
        return categoryId.prefix(1).uppercased() + categoryId.dropFirst().lowercased()
    }

    /// Background and foreground colors for icon circle. Use for subscription = true for subscription styling.
    static func iconColors(categoryId: String, subcategoryId: String? = nil, isSubscription: Bool = false) -> (Color, Color) {
        if isSubscription {
            return (OnboardingDesign.accentWarning.opacity(0.2), OnboardingDesign.accentWarning)
        }
        let color = self.color(categoryId: categoryId, subcategoryId: subcategoryId)
        return (color.opacity(0.2), color)
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

    /// Returns up to 3 category IDs for quick pick (excluding "other"). Fills with CategoryStore categories if needed.
    static func forQuickPick() -> [String] {
        let used = load().filter { $0 != "other" }
        let availableFromStore = CategoryStore.load().map(\.id).filter { $0 != "other" }
        let defaults = availableFromStore.isEmpty ? ["food", "transport", "housing"] : availableFromStore
        var result = used
        for d in defaults where result.count < maxCount && !result.contains(d) {
            result.append(d)
        }
        return Array(result.prefix(maxCount))
    }
}

