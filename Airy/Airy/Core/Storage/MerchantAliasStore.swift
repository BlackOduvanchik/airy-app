//
//  MerchantAliasStore.swift
//  Airy
//
//  Observed vs confirmed aliases. Only confirmed used for normalization and duplicate logic.
//

import Foundation

enum MerchantAliasKind {
    case observed   // from GPT or extraction; not trusted for normalization
    case confirmed  // user corrected or explicitly confirmed
}

struct MerchantAliasEntry: Codable, Equatable {
    let rawOrDisplay: String
    let normalizedMerchant: String
    let kind: String // "observed" | "confirmed"
}

final class MerchantAliasStore {
    static let shared = MerchantAliasStore()
    private let key = "merchantAliasStore"
    private let maxEntries = 500
    private var entries: [MerchantAliasEntry] = []
    private let queue = DispatchQueue(label: "merchantAliasStore")

    private init() {
        loadFromUserDefaults()
        migrateFromMerchantCorrectionStore()
    }

    /// Resolve to normalized merchant using **confirmed** aliases only. Returns nil if no confirmed alias.
    func resolveToNormalizedMerchant(raw: String?) -> String? {
        guard let r = raw?.trimmingCharacters(in: .whitespaces), !r.isEmpty else { return nil }
        let key = r.lowercased()
        return queue.sync {
            entries.first { $0.kind == "confirmed" && $0.rawOrDisplay.lowercased() == key }?.normalizedMerchant
        }
    }

    /// Normalize for display/storage: use confirmed alias if present, else trim and return as-is (no observed).
    func normalizeForPipeline(raw: String?) -> String {
        guard let r = raw?.trimmingCharacters(in: .whitespaces), !r.isEmpty else { return "Other" }
        if let canonical = resolveToNormalizedMerchant(raw: r) { return canonical }
        return r
    }

    /// Add or update a **confirmed** alias (user correction or explicit confirm).
    func addConfirmed(rawOrDisplay: String, normalizedMerchant: String) {
        guard !normalizedMerchant.isEmpty, rawOrDisplay.trimmingCharacters(in: .whitespaces).lowercased() != normalizedMerchant.trimmingCharacters(in: .whitespaces).lowercased() else { return }
        queue.sync {
            entries.removeAll { $0.rawOrDisplay.lowercased() == rawOrDisplay.lowercased() }
            entries.insert(MerchantAliasEntry(rawOrDisplay: rawOrDisplay.trimmingCharacters(in: .whitespaces), normalizedMerchant: normalizedMerchant.trimmingCharacters(in: .whitespaces), kind: "confirmed"), at: 0)
            if entries.count > maxEntries { entries = Array(entries.prefix(maxEntries)) }
            persist()
        }
    }

    /// Record an **observed** alias (e.g. from GPT). Not used for normalization until confirmed.
    func addObserved(rawOrDisplay: String, normalizedMerchant: String) {
        guard !normalizedMerchant.isEmpty else { return }
        queue.sync {
            if entries.contains(where: { $0.rawOrDisplay.lowercased() == rawOrDisplay.lowercased() && $0.kind == "confirmed" }) { return }
            entries.removeAll { $0.rawOrDisplay.lowercased() == rawOrDisplay.lowercased() && $0.kind == "observed" }
            entries.append(MerchantAliasEntry(rawOrDisplay: rawOrDisplay.trimmingCharacters(in: .whitespaces), normalizedMerchant: normalizedMerchant.trimmingCharacters(in: .whitespaces), kind: "observed"))
            if entries.count > maxEntries { entries = Array(entries.suffix(maxEntries)) }
            persist()
        }
    }

    /// Promote observed alias to confirmed (after user confirmation).
    func confirmAlias(rawOrDisplay: String) {
        queue.sync {
            guard let idx = entries.firstIndex(where: { $0.rawOrDisplay.lowercased() == rawOrDisplay.lowercased() && $0.kind == "observed" }) else { return }
            let e = entries[idx]
            entries.remove(at: idx)
            entries.insert(MerchantAliasEntry(rawOrDisplay: e.rawOrDisplay, normalizedMerchant: e.normalizedMerchant, kind: "confirmed"), at: 0)
            persist()
        }
    }

    func clearAll() {
        queue.sync(flags: .barrier) {
            entries.removeAll()
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func loadFromUserDefaults() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([MerchantAliasEntry].self, from: data) else { return }
        entries = decoded
    }

    /// One-time: copy legacy merchant corrections into confirmed aliases.
    private func migrateFromMerchantCorrectionStore() {
        struct LegacyCorrection: Codable {
            let originalMerchant: String
            let correctedMerchant: String
        }
        guard let data = UserDefaults.standard.data(forKey: "merchantCorrections"),
              let corrections = try? JSONDecoder().decode([LegacyCorrection].self, from: data) else { return }
        queue.sync {
            var seen = Set<String>()
            for c in corrections {
                let key = c.originalMerchant.lowercased()
                if seen.contains(key) { continue }
                seen.insert(key)
                if !entries.contains(where: { $0.rawOrDisplay.lowercased() == key && $0.kind == "confirmed" }) {
                    entries.insert(MerchantAliasEntry(rawOrDisplay: c.originalMerchant, normalizedMerchant: c.correctedMerchant, kind: "confirmed"), at: 0)
                }
            }
            if entries.count > maxEntries { entries = Array(entries.prefix(maxEntries)) }
            persist()
        }
    }
}
