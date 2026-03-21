//
//  ImageHashCacheStore.swift
//  Airy
//
//  Simple image hash → extracted transactions cache. Same image is never sent to GPT twice.
//

import Foundation

final class ImageHashCacheStore {
    static let shared = ImageHashCacheStore()
    private let cacheKey = "parsingRules_imageHashCache"
    private let maxEntries = 100
    private var cache: [String: [ParsedTransactionItem]] = [:]
    private let queue = DispatchQueue(label: "imageHashCacheStore")

    private init() { load() }

    func cachedResult(forImageHash hash: String) -> [ParsedTransactionItem]? {
        queue.sync { cache[hash] }
    }

    func cacheResult(_ items: [ParsedTransactionItem], forImageHash hash: String) {
        queue.sync {
            cache[hash] = items
            if cache.count > maxEntries {
                let keysToRemove = Array(cache.keys.prefix(cache.count - maxEntries))
                keysToRemove.forEach { cache.removeValue(forKey: $0) }
            }
            persist()
        }
    }

    func clearAll() {
        queue.sync {
            cache.removeAll()
            UserDefaults.standard.removeObject(forKey: cacheKey)
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let decoded = try? JSONDecoder().decode([String: [ParsedTransactionItem]].self, from: data) else { return }
        cache = decoded
    }
}
