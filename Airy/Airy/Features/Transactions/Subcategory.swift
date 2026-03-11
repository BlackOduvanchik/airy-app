//
//  Subcategory.swift
//  Airy
//
//  Custom subcategory model; stored in UserDefaults.
//

import Foundation

struct Subcategory: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var parentCategoryId: String

    init(id: String = UUID().uuidString, name: String, parentCategoryId: String) {
        self.id = id
        self.name = name
        self.parentCategoryId = parentCategoryId
    }
}

enum SubcategoryStore {
    private static let key = "airy.subcategories"

    static func load() -> [Subcategory] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Subcategory].self, from: data) else {
            return []
        }
        return decoded
    }

    static func save(_ subcategories: [Subcategory]) {
        guard let data = try? JSONEncoder().encode(subcategories) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func add(_ subcategory: Subcategory) {
        var list = load()
        list.append(subcategory)
        save(list)
    }

    static func update(_ subcategory: Subcategory) {
        var list = load()
        if let idx = list.firstIndex(where: { $0.id == subcategory.id }) {
            list[idx] = subcategory
            save(list)
        }
    }

    static func delete(id: String) {
        var list = load()
        list.removeAll { $0.id == id }
        save(list)
    }

    static func forParent(_ parentCategoryId: String) -> [Subcategory] {
        load().filter { $0.parentCategoryId == parentCategoryId }
    }
}
