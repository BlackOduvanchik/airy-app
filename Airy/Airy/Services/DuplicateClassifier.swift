//
//  DuplicateClassifier.swift
//  Airy
//
//  Exact / Probable / Not duplicate using normalized merchant, date, amount.
//  No "contains" merchant logic; only confirmed alias resolution.
//

import Foundation

final class DuplicateClassifier {
    static let shared = DuplicateClassifier()
    private let aliasStore: MerchantAliasStore
    private let amountTolerance = 0.01
    private let merchantSimilarityThreshold = 0.85

    init(aliasStore: MerchantAliasStore = .shared) {
        self.aliasStore = aliasStore
    }

    /// Classify candidate against saved transactions only (not pending). Use normalized merchant from confirmed aliases.
    func classify(
        normalizedMerchant: String,
        isoDate: String,
        amount: Double,
        saved: [SavedTransactionRecord],
        includePending: Bool = false,
        pending: [SavedTransactionRecord] = []
    ) -> DuplicateClassification {
        let dateStr = String(isoDate.prefix(10))
        let normCandidate = aliasStore.normalizeForPipeline(raw: normalizedMerchant)

        for r in saved {
            guard abs(r.amount - amount) < amountTolerance else { continue }
            guard String(r.date.prefix(10)) == dateStr else { continue }
            let normSaved = aliasStore.normalizeForPipeline(raw: r.merchant)
            if normCandidate.lowercased() == normSaved.lowercased() {
                return .exactDuplicate
            }
            if merchantSimilarity(normCandidate, normSaved) >= merchantSimilarityThreshold {
                return .probableDuplicate(ofSavedId: r.id)
            }
        }

        if includePending {
            for r in pending {
                guard abs(r.amount - amount) < amountTolerance else { continue }
                guard String(r.date.prefix(10)) == dateStr else { continue }
                let normSaved = aliasStore.normalizeForPipeline(raw: r.merchant)
                if normCandidate.lowercased() == normSaved.lowercased() {
                    return .exactDuplicate
                }
                if merchantSimilarity(normCandidate, normSaved) >= merchantSimilarityThreshold {
                    return .probableDuplicate(ofSavedId: r.id)
                }
            }
        }

        return .notDuplicate
    }

    /// Levenshtein-based similarity in 0...1.
    private func merchantSimilarity(_ a: String, _ b: String) -> Double {
        let aLower = a.lowercased()
        let bLower = b.lowercased()
        if aLower == bLower { return 1.0 }
        if aLower.isEmpty || bLower.isEmpty { return 0 }
        let distance = levenshtein(aLower, bLower)
        let maxLen = max(aLower.count, bLower.count)
        return 1.0 - (Double(distance) / Double(maxLen))
    }

    private func levenshtein(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        var row = (0...b.count).map { $0 }
        for (i, c1) in a.enumerated() {
            var next = [i + 1]
            for (j, c2) in b.enumerated() {
                let cost = c1 == c2 ? 0 : 1
                next.append(min(next[j] + 1, row[j + 1] + 1, row[j] + cost))
            }
            row = next
        }
        return row.last ?? 0
    }
}
