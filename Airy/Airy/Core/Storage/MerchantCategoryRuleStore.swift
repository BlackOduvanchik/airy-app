//
//  MerchantCategoryRuleStore.swift
//  Airy
//
//  When user changes category for a merchant in Review and turns "Remember rule" on,
//  we save it so the same merchant gets that category on future imports.
//

import Foundation

private struct MerchantCategoryRule: Codable {
    let categoryId: String
    let subcategoryId: String?
}

final class MerchantCategoryRuleStore {
    static let shared = MerchantCategoryRuleStore()
    private let key = "merchantCategoryRules"
    private let maxRules = 200

    private init() {}

    /// Save category (and optional subcategory) for this merchant. Use when user confirms with "Remember rule" and changed category.
    func save(merchant: String, categoryId: String, subcategoryId: String?) {
        let normalized = merchant.trimmingCharacters(in: .whitespaces).lowercased()
        guard !normalized.isEmpty, !categoryId.isEmpty else { return }
        var all = loadAll()
        all[normalized] = MerchantCategoryRule(categoryId: categoryId, subcategoryId: subcategoryId)
        if all.count > maxRules {
            let keysToRemove = Array(all.keys.prefix(all.count - maxRules))
            keysToRemove.forEach { all.removeValue(forKey: $0) }
        }
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Category id for this merchant if we have a saved rule; nil otherwise.
    func categoryId(for merchant: String?) -> String? {
        guard let m = merchant else { return nil }
        let normalized = m.trimmingCharacters(in: .whitespaces).lowercased()
        return loadAll()[normalized]?.categoryId
    }

    /// Subcategory id for this merchant if we have a saved rule; nil otherwise.
    func subcategoryId(for merchant: String?) -> String? {
        guard let m = merchant else { return nil }
        let normalized = m.trimmingCharacters(in: .whitespaces).lowercased()
        return loadAll()[normalized]?.subcategoryId
    }

    func clearAll() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private func loadAll() -> [String: MerchantCategoryRule] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [:] }
        let decoded = try? JSONDecoder().decode([String: MerchantCategoryRule].self, from: data)
        return decoded ?? [:]
    }
}
