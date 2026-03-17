//
//  LayoutFamilyStore.swift
//  Airy
//
//  Persists layout families after successful GPT extraction for structure-assist matching.
//

import Foundation
import CryptoKit

/// Coarse alignment / placement hint for structure assist.
enum AmountAlignmentPattern: String, Codable, Equatable {
    case rightAligned
    case leftAligned
    case inline
    case unknown
}

/// One layout family: screen type, row structure signature, and validated keywords from a successful extraction.
struct LayoutFamily: Codable, Equatable {
    let id: String
    var screenType: ScreenType
    var rowStructureSignature: String
    var amountAlignmentPattern: AmountAlignmentPattern
    var merchantPlacementPattern: String?
    var dateTimePlacementPattern: String?
    var ignoreKeywords: [String]
    var failureKeywords: [String]
    /// Coarse fingerprint for matching (line count bucket + structure rhythm hash). Kept for backward compat.
    var coarseFingerprint: String
    /// Structure-only fingerprint (line count bucket + line-length bucket pattern). Used for matching and reuse; no content.
    var structuralFingerprint: String?
    /// Density bucket from avg line length: compact, normal, spacious. Used to avoid merging different app layouts.
    var densityBucket: String?
    /// Amount anchor: right, left, inline, unknown. Used for strong/weak reuse.
    var amountAnchorBucket: String?
    /// Number of times this family was updated or matched (reuse count).
    var useCount: Int
    var lastUsedAt: Date

    // MARK: - Cluster profile (bounded tolerances)
    /// Dominant line-count bucket (e.g. L25). Match when current bucket equals this or lineCountAllowedNeighborBucket.
    var lineCountDominantBucket: String?
    /// At most one allowed neighbor bucket. Only set after same neighbor seen on 2+ reuses.
    var lineCountAllowedNeighborBucket: String?
    /// Reuse count for the neighbor bucket; when >= 2 we keep lineCountAllowedNeighborBucket.
    var lineCountNeighborSeenCount: Int?
    /// Dominant density (compact/normal/spacious). Use densityBucket for backfill.
    var densityDominant: String?
    /// At most one secondary density; set only after same value seen on 2+ reuses.
    var densitySecondary: String?
    var densitySecondaryReuseCount: Int?
    /// Dominant amount anchor (right/left/inline/unknown).
    var amountAnchorDominant: String?
    /// At most one secondary amount anchor; set only after 2+ reuses.
    var amountAnchorSecondary: String?
    var amountAnchorSecondaryReuseCount: Int?
    /// Up to 5 canonical 8-char row-sig prefixes. Cap and canonicalize; no unbounded bag.
    var rowStructureRepresentatives: [String]
    /// Optional: grouped (has date headers) vs flat. Hard identity when set.
    var groupedVsFlat: Bool?
    /// Cached maturity level from LayoutFamilyLearningStore (for fast pipeline lookup without cross-store calls).
    var maturityLevelCached: String?

    init(id: String = UUID().uuidString, screenType: ScreenType, rowStructureSignature: String, amountAlignmentPattern: AmountAlignmentPattern = .unknown, merchantPlacementPattern: String? = nil, dateTimePlacementPattern: String? = nil, ignoreKeywords: [String] = [], failureKeywords: [String] = [], coarseFingerprint: String, structuralFingerprint: String? = nil, densityBucket: String? = nil, amountAnchorBucket: String? = nil, useCount: Int = 0, lastUsedAt: Date = Date(), lineCountDominantBucket: String? = nil, lineCountAllowedNeighborBucket: String? = nil, lineCountNeighborSeenCount: Int? = nil, densityDominant: String? = nil, densitySecondary: String? = nil, densitySecondaryReuseCount: Int? = nil, amountAnchorDominant: String? = nil, amountAnchorSecondary: String? = nil, amountAnchorSecondaryReuseCount: Int? = nil, rowStructureRepresentatives: [String] = [], groupedVsFlat: Bool? = nil, maturityLevelCached: String? = nil) {
        self.id = id
        self.screenType = screenType
        self.rowStructureSignature = rowStructureSignature
        self.amountAlignmentPattern = amountAlignmentPattern
        self.merchantPlacementPattern = merchantPlacementPattern
        self.dateTimePlacementPattern = dateTimePlacementPattern
        self.ignoreKeywords = ignoreKeywords
        self.failureKeywords = failureKeywords
        self.coarseFingerprint = coarseFingerprint
        self.structuralFingerprint = structuralFingerprint
        self.densityBucket = densityBucket
        self.amountAnchorBucket = amountAnchorBucket
        self.useCount = useCount
        self.lastUsedAt = lastUsedAt
        self.lineCountDominantBucket = lineCountDominantBucket
        self.lineCountAllowedNeighborBucket = lineCountAllowedNeighborBucket
        self.lineCountNeighborSeenCount = lineCountNeighborSeenCount
        self.densityDominant = densityDominant
        self.densitySecondary = densitySecondary
        self.densitySecondaryReuseCount = densitySecondaryReuseCount
        self.amountAnchorDominant = amountAnchorDominant
        self.amountAnchorSecondary = amountAnchorSecondary
        self.amountAnchorSecondaryReuseCount = amountAnchorSecondaryReuseCount
        self.rowStructureRepresentatives = rowStructureRepresentatives
        self.groupedVsFlat = groupedVsFlat
        self.maturityLevelCached = maturityLevelCached
    }

    enum CodingKeys: String, CodingKey {
        case id, screenType, rowStructureSignature, amountAlignmentPattern, merchantPlacementPattern, dateTimePlacementPattern, ignoreKeywords, failureKeywords, coarseFingerprint, structuralFingerprint, densityBucket, amountAnchorBucket, useCount, lastUsedAt
        case lineCountDominantBucket, lineCountAllowedNeighborBucket, lineCountNeighborSeenCount
        case densityDominant, densitySecondary, densitySecondaryReuseCount
        case amountAnchorDominant, amountAnchorSecondary, amountAnchorSecondaryReuseCount
        case rowStructureRepresentatives, groupedVsFlat, maturityLevelCached
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        screenType = try c.decode(ScreenType.self, forKey: .screenType)
        rowStructureSignature = try c.decode(String.self, forKey: .rowStructureSignature)
        amountAlignmentPattern = try c.decode(AmountAlignmentPattern.self, forKey: .amountAlignmentPattern)
        merchantPlacementPattern = try c.decodeIfPresent(String.self, forKey: .merchantPlacementPattern)
        dateTimePlacementPattern = try c.decodeIfPresent(String.self, forKey: .dateTimePlacementPattern)
        ignoreKeywords = try c.decodeIfPresent([String].self, forKey: .ignoreKeywords) ?? []
        failureKeywords = try c.decodeIfPresent([String].self, forKey: .failureKeywords) ?? []
        coarseFingerprint = try c.decode(String.self, forKey: .coarseFingerprint)
        structuralFingerprint = try c.decodeIfPresent(String.self, forKey: .structuralFingerprint)
        densityBucket = try c.decodeIfPresent(String.self, forKey: .densityBucket)
        amountAnchorBucket = try c.decodeIfPresent(String.self, forKey: .amountAnchorBucket)
        useCount = try c.decodeIfPresent(Int.self, forKey: .useCount) ?? 0
        lastUsedAt = try c.decode(Date.self, forKey: .lastUsedAt)
        lineCountDominantBucket = try c.decodeIfPresent(String.self, forKey: .lineCountDominantBucket) ?? structuralFingerprint.flatMap { LayoutFamilyStore.lineCountBucket(fromStructuralFingerprint: $0) }
        lineCountAllowedNeighborBucket = try c.decodeIfPresent(String.self, forKey: .lineCountAllowedNeighborBucket)
        lineCountNeighborSeenCount = try c.decodeIfPresent(Int.self, forKey: .lineCountNeighborSeenCount)
        densityDominant = try c.decodeIfPresent(String.self, forKey: .densityDominant) ?? densityBucket ?? "normal"
        densitySecondary = try c.decodeIfPresent(String.self, forKey: .densitySecondary)
        densitySecondaryReuseCount = try c.decodeIfPresent(Int.self, forKey: .densitySecondaryReuseCount)
        amountAnchorDominant = try c.decodeIfPresent(String.self, forKey: .amountAnchorDominant) ?? amountAnchorBucket ?? "unknown"
        amountAnchorSecondary = try c.decodeIfPresent(String.self, forKey: .amountAnchorSecondary)
        amountAnchorSecondaryReuseCount = try c.decodeIfPresent(Int.self, forKey: .amountAnchorSecondaryReuseCount)
        rowStructureRepresentatives = try c.decodeIfPresent([String].self, forKey: .rowStructureRepresentatives) ?? (rowStructureSignature.isEmpty ? [] : [String(rowStructureSignature.prefix(8))])
        groupedVsFlat = try c.decodeIfPresent(Bool.self, forKey: .groupedVsFlat)
        maturityLevelCached = try c.decodeIfPresent(String.self, forKey: .maturityLevelCached)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(screenType, forKey: .screenType)
        try c.encode(rowStructureSignature, forKey: .rowStructureSignature)
        try c.encode(amountAlignmentPattern, forKey: .amountAlignmentPattern)
        try c.encodeIfPresent(merchantPlacementPattern, forKey: .merchantPlacementPattern)
        try c.encodeIfPresent(dateTimePlacementPattern, forKey: .dateTimePlacementPattern)
        try c.encode(ignoreKeywords, forKey: .ignoreKeywords)
        try c.encode(failureKeywords, forKey: .failureKeywords)
        try c.encode(coarseFingerprint, forKey: .coarseFingerprint)
        try c.encode(structuralFingerprint, forKey: .structuralFingerprint)
        try c.encode(densityBucket, forKey: .densityBucket)
        try c.encode(amountAnchorBucket, forKey: .amountAnchorBucket)
        try c.encode(useCount, forKey: .useCount)
        try c.encode(lastUsedAt, forKey: .lastUsedAt)
        try c.encodeIfPresent(lineCountDominantBucket, forKey: .lineCountDominantBucket)
        try c.encodeIfPresent(lineCountAllowedNeighborBucket, forKey: .lineCountAllowedNeighborBucket)
        try c.encodeIfPresent(lineCountNeighborSeenCount, forKey: .lineCountNeighborSeenCount)
        try c.encodeIfPresent(densityDominant, forKey: .densityDominant)
        try c.encodeIfPresent(densitySecondary, forKey: .densitySecondary)
        try c.encodeIfPresent(densitySecondaryReuseCount, forKey: .densitySecondaryReuseCount)
        try c.encodeIfPresent(amountAnchorDominant, forKey: .amountAnchorDominant)
        try c.encodeIfPresent(amountAnchorSecondary, forKey: .amountAnchorSecondary)
        try c.encodeIfPresent(amountAnchorSecondaryReuseCount, forKey: .amountAnchorSecondaryReuseCount)
        if !rowStructureRepresentatives.isEmpty { try c.encode(rowStructureRepresentatives, forKey: .rowStructureRepresentatives) }
        try c.encodeIfPresent(groupedVsFlat, forKey: .groupedVsFlat)
        try c.encodeIfPresent(maturityLevelCached, forKey: .maturityLevelCached)
    }
}

final class LayoutFamilyStore {
    static let shared = LayoutFamilyStore()
    private let key = "layoutFamilies"
    private let maxFamilies = 30
    private var families: [LayoutFamily] = []
    private let queue = DispatchQueue(label: "layoutFamilyStore")

    private init() {
        loadFromUserDefaults()
    }

    /// Coarse fingerprint for family matching: line count bucket + structure rhythm (first-char pattern of first 15 lines). Same app/screen type often shares this. Kept for backward compat.
    static func coarseFingerprint(normalizedText: String) -> String {
        let lines = normalizedText.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let count = lines.count
        let bucket: String
        switch count {
        case 0..<11: bucket = "L10"
        case 11..<26: bucket = "L25"
        case 26..<51: bucket = "L50"
        default: bucket = "L99"
        }
        let rhythm = lines.prefix(15).map { line in
            line.first.map { String($0) } ?? ""
        }.joined()
        let data = Data("\(bucket)|\(rhythm)".utf8)
        let hash = SHA256.hash(data: data)
        return bucket + hash.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Structure-only fingerprint: line count bucket + line-length bucket pattern (S/M/L per line, first 15). No content; stable across screenshots of same layout.
    static func structuralFingerprint(normalizedText: String) -> String {
        let lines = normalizedText.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let count = lines.count
        let bucket: String
        switch count {
        case 0..<11: bucket = "L10"
        case 11..<26: bucket = "L25"
        case 26..<51: bucket = "L50"
        default: bucket = "L99"
        }
        let lengthPattern = lines.prefix(15).map { line -> String in
            let len = line.count
            switch len {
            case 0..<16: return "S"
            case 16..<36: return "M"
            default: return "L"
            }
        }.joined()
        let data = Data("\(bucket)|\(lengthPattern)".utf8)
        let hash = SHA256.hash(data: data)
        return bucket + hash.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Line-count bucket from a structural (or coarse) fingerprint string (e.g. "L25").
    static func lineCountBucket(fromStructuralFingerprint structuralFingerprint: String) -> String? {
        let b = String(structuralFingerprint.prefix(3))
        return (b == "L10" || b == "L25" || b == "L50" || b == "L99") ? b : nil
    }

    /// Density bucket from average line length of first 15 normalized lines: compact (<18), normal (18–32), spacious (32+).
    static func densityBucket(normalizedText: String) -> String {
        let lines = normalizedText.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let count = min(15, lines.count)
        guard count > 0 else { return "normal" }
        let total = lines.prefix(count).reduce(0) { $0 + $1.count }
        let avg = Double(total) / Double(count)
        if avg < 18 { return "compact" }
        if avg <= 32 { return "normal" }
        return "spacious"
    }

    private static let amountAnchorPatternStr = #"[-+]?\s*\d{1,3}(?:[\s.,]\d{3})*(?:[.,]\d{2})|\d+[.,]\d{2}|\d+"#

    /// Amount anchor bucket from line positions: right (amount in last ~25%), left (first ~25%), inline, or unknown. Majority vote across lines with amount-like content.
    static func amountAnchorBucket(lines: [String]) -> String {
        guard let regex = try? NSRegularExpression(pattern: amountAnchorPatternStr) else { return "unknown" }
        var right = 0, left = 0, inline = 0
        for line in lines.prefix(30) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let range = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed))?.range else { continue }
            let len = trimmed.utf16.count
            guard len > 0 else { continue }
            let ratio = Double(range.location) / Double(len)
            if ratio >= 0.75 { right += 1 }
            else if ratio <= 0.25 { left += 1 }
            else { inline += 1 }
        }
        let total = right + left + inline
        guard total > 0 else { return "unknown" }
        if right >= left && right >= inline { return "right" }
        if left >= right && left >= inline { return "left" }
        return "inline"
    }

    /// Row structure signature: hash of run-lengths of transactionCandidate blocks (e.g. "2,3,2" for runs of 2, 3, 2). Pass run-lengths from classifier.
    static func rowStructureSignature(transactionCandidateRunLengths: [Int]) -> String {
        let s = transactionCandidateRunLengths.map { String($0) }.joined(separator: ",")
        let data = Data(s.utf8)
        let hash = SHA256.hash(data: data)
        return hash.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    /// Result of addOrUpdate for debug: whether we reused an existing family, final id, cluster size (useCount), and reason.
    struct AddOrUpdateResult {
        let reused: Bool
        let familyId: String
        let clusterSize: Int
        let reason: String
    }

    /// Result of profile-based family matching: families sorted by similarity (best first), and rejection reason when none matched.
    struct ProfileMatchResult {
        let families: [LayoutFamily]
        let rejectionReason: String?
    }

    private static let maxRowRepresentatives = 5
    private static let rowSigPrefixLength = 8

    /// Persist or update a layout family. Prefers matching by structuralFingerprint; reuses existing family id and increments useCount. Returns reuse info for debug.
    func addOrUpdate(family: LayoutFamily) -> AddOrUpdateResult {
        queue.sync {
            let now = Date()
            if let sf = family.structuralFingerprint, let index = families.firstIndex(where: { $0.structuralFingerprint == sf }) {
                var updated = families[index]
                updated.lastUsedAt = now
                updated.useCount += 1
                updated.screenType = family.screenType
                updated.rowStructureSignature = family.rowStructureSignature
                updated.amountAlignmentPattern = family.amountAlignmentPattern
                updated.amountAnchorBucket = family.amountAnchorBucket
                updated.merchantPlacementPattern = family.merchantPlacementPattern ?? updated.merchantPlacementPattern
                updated.dateTimePlacementPattern = family.dateTimePlacementPattern ?? updated.dateTimePlacementPattern
                if !family.ignoreKeywords.isEmpty { updated.ignoreKeywords = family.ignoreKeywords }
                if !family.failureKeywords.isEmpty { updated.failureKeywords = family.failureKeywords }
                updated.coarseFingerprint = family.coarseFingerprint
                updated.maturityLevelCached = LayoutFamilyLearningStore.shared.maturityLevel(forFamilyId: updated.id).rawValue
                families[index] = updated
                persist()
                return AddOrUpdateResult(reused: true, familyId: updated.id, clusterSize: updated.useCount, reason: "exact structural match")
            }
            // Cluster match: profile (hard identity + soft tolerance), pick best similarity, then conservatively widen (call OnCurrentQueue to avoid re-entrant queue.sync deadlock)
            let lineBucket = family.structuralFingerprint.flatMap { Self.lineCountBucket(fromStructuralFingerprint: $0) }
            let profileResult = familiesMatchingProfileOnCurrentQueue(lineCountBucket: lineBucket, screenType: family.screenType, densityBucket: family.densityBucket, amountAnchorBucket: family.amountAnchorBucket, rowStructureSignature: family.rowStructureSignature)
            if let first = profileResult.families.first, let index = families.firstIndex(where: { $0.id == first.id }) {
                var updated = families[index]
                updated.lastUsedAt = now
                updated.useCount += 1
                updated.screenType = family.screenType
                updated.rowStructureSignature = family.rowStructureSignature
                updated.amountAlignmentPattern = family.amountAlignmentPattern
                updated.amountAnchorBucket = family.amountAnchorBucket
                updated.densityBucket = family.densityBucket
                updated.coarseFingerprint = family.coarseFingerprint
                // Conservative widen: line count neighbor
                if let curLine = lineBucket, curLine != (updated.lineCountDominantBucket ?? "") {
                    if updated.lineCountAllowedNeighborBucket == curLine {
                        updated.lineCountNeighborSeenCount = (updated.lineCountNeighborSeenCount ?? 0) + 1
                    } else if updated.lineCountAllowedNeighborBucket == nil {
                        updated.lineCountAllowedNeighborBucket = curLine
                        updated.lineCountNeighborSeenCount = 1
                    }
                }
                // Conservative widen: density secondary (only after 2+ reuses)
                if let curDensity = family.densityBucket, !curDensity.isEmpty, curDensity != (updated.densityDominant ?? updated.densityBucket ?? "normal") {
                    if updated.densitySecondary == curDensity {
                        updated.densitySecondaryReuseCount = (updated.densitySecondaryReuseCount ?? 0) + 1
                    } else if updated.densitySecondary == nil {
                        updated.densitySecondary = curDensity
                        updated.densitySecondaryReuseCount = 1
                    }
                }
                // Conservative widen: amount anchor secondary (keep candidate; only use in match when count >= 2 if we want – currently we allow set secondary as soon as set)
                if let curAnchor = family.amountAnchorBucket, !curAnchor.isEmpty, curAnchor != (updated.amountAnchorDominant ?? updated.amountAnchorBucket ?? "unknown") {
                    if updated.amountAnchorSecondary == curAnchor {
                        updated.amountAnchorSecondaryReuseCount = (updated.amountAnchorSecondaryReuseCount ?? 0) + 1
                    } else if updated.amountAnchorSecondary == nil {
                        updated.amountAnchorSecondary = curAnchor
                        updated.amountAnchorSecondaryReuseCount = 1
                    }
                }
                // Conservative widen: row representatives (cap 5, at most one new per update)
                let prefix = String(family.rowStructureSignature.prefix(Self.rowSigPrefixLength))
                if !prefix.isEmpty {
                    var reps = updated.rowStructureRepresentatives
                    if reps.isEmpty { reps = [String(updated.rowStructureSignature.prefix(Self.rowSigPrefixLength))].filter { !$0.isEmpty } }
                    let matches = reps.contains { $0.hasPrefix(prefix) || prefix.hasPrefix($0) }
                    if !matches {
                        if reps.count < Self.maxRowRepresentatives {
                            reps.append(prefix)
                        } else {
                            if let idx = reps.firstIndex(where: { $0 != prefix }) {
                                reps[idx] = prefix
                            }
                        }
                        updated.rowStructureRepresentatives = reps
                    }
                }
                updated.maturityLevelCached = LayoutFamilyLearningStore.shared.maturityLevel(forFamilyId: updated.id).rawValue
                families[index] = updated
                persist()
                return AddOrUpdateResult(reused: true, familyId: updated.id, clusterSize: updated.useCount, reason: "profile match")
            }
            // New family: point profile
            var toAppend = family
            toAppend.lastUsedAt = now
            toAppend.useCount = 1
            toAppend.maturityLevelCached = FamilyMaturityLevel.apprentice.rawValue
            toAppend.lineCountDominantBucket = lineBucket
            toAppend.lineCountAllowedNeighborBucket = nil
            toAppend.lineCountNeighborSeenCount = nil
            toAppend.densityDominant = family.densityBucket ?? "normal"
            toAppend.densitySecondary = nil
            toAppend.densitySecondaryReuseCount = nil
            toAppend.amountAnchorDominant = family.amountAnchorBucket ?? "unknown"
            toAppend.amountAnchorSecondary = nil
            toAppend.amountAnchorSecondaryReuseCount = nil
            let sigPrefix = String(family.rowStructureSignature.prefix(Self.rowSigPrefixLength))
            toAppend.rowStructureRepresentatives = sigPrefix.isEmpty ? [] : [sigPrefix]
            families.append(toAppend)
            if families.count > maxFamilies {
                families.sort { $0.lastUsedAt < $1.lastUsedAt }
                families.removeFirst(families.count - maxFamilies)
            }
            persist()
            return AddOrUpdateResult(reused: false, familyId: toAppend.id, clusterSize: 1, reason: profileResult.rejectionReason ?? "new family")
        }
    }

    /// Return the layout family with the given id, if present. Used for local extraction hints (e.g. amount anchor).
    func family(withId id: String) -> LayoutFamily? {
        queue.sync {
            families.first { $0.id == id }
        }
    }

    /// Line-count bucket prefix of a coarse fingerprint (e.g. "L10", "L25", "L50", "L99").
    static func lineCountBucket(fromCoarseFingerprint coarseFingerprint: String) -> String? {
        let b = String(coarseFingerprint.prefix(3))
        return (b == "L10" || b == "L25" || b == "L50" || b == "L99") ? b : nil
    }

    /// Return families whose coarse fingerprint matches. If exact match is empty and fallbackToBucket is true, returns families in the same line-count bucket (similar screens).
    func familiesMatching(coarseFingerprint: String, fallbackToBucket: Bool = false) -> [LayoutFamily] {
        queue.sync {
            var result = families.filter { $0.coarseFingerprint == coarseFingerprint }
            if result.isEmpty, fallbackToBucket, let bucket = Self.lineCountBucket(fromCoarseFingerprint: coarseFingerprint) {
                result = families.filter { $0.coarseFingerprint.hasPrefix(bucket) }
                    .sorted { $0.lastUsedAt > $1.lastUsedAt }
            }
            return result
        }
    }

    /// Profile-based match: hard identity (screenType, amountAnchor family) then soft tolerance (line bucket, density, row sig). Returns families sorted by similarity score (best first), then lastUsedAt. Rejection reason when none match.
    /// Call only from outside the store's queue. For callers already inside queue.sync (e.g. addOrUpdate), use familiesMatchingProfileOnCurrentQueue to avoid deadlock.
    func familiesMatchingProfile(lineCountBucket: String?, screenType: ScreenType?, densityBucket: String?, amountAnchorBucket: String?, rowStructureSignature: String?) -> ProfileMatchResult {
        queue.sync {
            familiesMatchingProfileOnCurrentQueue(lineCountBucket: lineCountBucket, screenType: screenType, densityBucket: densityBucket, amountAnchorBucket: amountAnchorBucket, rowStructureSignature: rowStructureSignature)
        }
    }

    /// Same as familiesMatchingProfile but must be called only while already executing on the store's queue (e.g. from inside addOrUpdate's queue.sync block). Avoids re-entrant sync deadlock.
    private func familiesMatchingProfileOnCurrentQueue(lineCountBucket: String?, screenType: ScreenType?, densityBucket: String?, amountAnchorBucket: String?, rowStructureSignature: String?) -> ProfileMatchResult {
            // Hard identity: screenType must match; amountAnchor must be in {dominant, secondary} when both sides have a value
            func hardIdentityMatch(_ candidate: LayoutFamily) -> Bool {
                guard candidate.screenType == (screenType ?? candidate.screenType) else { return false }
                if let gvf = candidate.groupedVsFlat { _ = gvf; /* could check current groupedVsFlat when we have it */ }
                let dom = candidate.amountAnchorDominant ?? candidate.amountAnchorBucket ?? "unknown"
                let sec = candidate.amountAnchorSecondary
                let current = amountAnchorBucket ?? "unknown"
                if current == "unknown" { return true }
                if current == dom { return true }
                if let s = sec, current == s { return true }
                return false
            }
            // Soft tolerance + similarity score (higher = better). Returns nil if soft check fails.
            func softScore(_ candidate: LayoutFamily) -> Double? {
                let lineDom = candidate.lineCountDominantBucket ?? Self.lineCountBucket(fromStructuralFingerprint: candidate.structuralFingerprint ?? "")
                let lineNeighbor = candidate.lineCountAllowedNeighborBucket
                let currentLine = lineCountBucket ?? ""
                guard !currentLine.isEmpty, let dom = lineDom else { return nil }
                let lineMatch: Bool
                var lineScore: Double = 0
                if dom == currentLine {
                    lineMatch = true
                    lineScore = 1.0
                } else if lineNeighbor == currentLine {
                    lineMatch = true
                    lineScore = 0.8
                } else {
                    lineMatch = false
                }
                guard lineMatch else { return nil }

                let densityDom = candidate.densityDominant ?? candidate.densityBucket ?? "normal"
                let densitySec = candidate.densitySecondary
                let currentDensity = densityBucket ?? "normal"
                let densityMatch = (currentDensity == densityDom || (densitySec != nil && currentDensity == densitySec))
                guard densityMatch else { return nil }
                let densityScore: Double = currentDensity == densityDom ? 0.2 : 0.1

                let reps = candidate.rowStructureRepresentatives.isEmpty ? (candidate.rowStructureSignature.isEmpty ? [] : [String(candidate.rowStructureSignature.prefix(Self.rowSigPrefixLength))]) : candidate.rowStructureRepresentatives
                let sigPrefix = (rowStructureSignature ?? "").isEmpty ? "" : String((rowStructureSignature ?? "").prefix(Self.rowSigPrefixLength))
                var rowScore: Double = 0
                if !sigPrefix.isEmpty && !reps.isEmpty {
                    let match = reps.contains { rep in rep.hasPrefix(sigPrefix) || sigPrefix.hasPrefix(rep) }
                    if match { rowScore = 0.2 } else {
                        // "Close" = same length as any rep (e.g. same run-length count) – use prefix length as proxy
                        let close = reps.contains { $0.count == sigPrefix.count }
                        if close { rowScore = 0.1 } else { return nil }
                    }
                } else if sigPrefix.isEmpty { rowScore = 0.1 }

                return lineScore + densityScore + rowScore
            }

            var scored: [(LayoutFamily, Double)] = []
            for f in families {
                guard hardIdentityMatch(f) else { continue }
                guard let score = softScore(f) else { continue }
                scored.append((f, score))
            }
            scored.sort { a, b in
                if a.1 != b.1 { return a.1 > b.1 }
                if a.0.useCount != b.0.useCount { return a.0.useCount > b.0.useCount }
                return a.0.lastUsedAt > b.0.lastUsedAt
            }
            let list = scored.map { $0.0 }
            let reason: String? = list.isEmpty ? (lineCountBucket == nil ? "no line bucket" : "no family matched profile (hard identity or soft tolerance)") : nil
            return ProfileMatchResult(families: list, rejectionReason: reason)
    }

    /// Return families whose structural fingerprint matches. Prefers families with structuralFingerprint set. If empty and fallbackToBucket, match by line-count bucket only.
    func familiesMatching(structuralFingerprint structuralFp: String, fallbackToBucket: Bool = false) -> [LayoutFamily] {
        queue.sync {
            var result = families.filter { $0.structuralFingerprint == structuralFp }
            if result.isEmpty, fallbackToBucket, let bucket = Self.lineCountBucket(fromStructuralFingerprint: structuralFp) {
                result = families.filter { $0.structuralFingerprint?.hasPrefix(bucket) == true }
                    .sorted { $0.lastUsedAt > $1.lastUsedAt }
            }
            return result
        }
    }

    /// Return families matching structure; strong reuse = exact structuralFingerprint or full profile; weak = same bucket + screenType + densityBucket (+ optional rowSig and amountAnchor).
    func familiesMatching(structuralFingerprint structuralFp: String, screenType: ScreenType?, densityBucket: String?, rowStructureSignature: String? = nil, amountAnchorBucket: String? = nil, fallbackToBucket: Bool) -> [LayoutFamily] {
        queue.sync {
            var result = families.filter { $0.structuralFingerprint == structuralFp }
            if result.isEmpty, fallbackToBucket, let bucket = Self.lineCountBucket(fromStructuralFingerprint: structuralFp),
               let st = screenType, let db = densityBucket, !db.isEmpty {
                result = families.filter { candidate in
                    guard candidate.structuralFingerprint?.hasPrefix(bucket) == true,
                          candidate.screenType == st,
                          let cdb = candidate.densityBucket, cdb == db else { return false }
                    if let sig = rowStructureSignature, !sig.isEmpty {
                        let csig = candidate.rowStructureSignature
                        guard csig.hasPrefix(String(sig.prefix(8))) || (!csig.isEmpty && sig.hasPrefix(String(csig.prefix(8)))) else { return false }
                    }
                    if let ab = amountAnchorBucket, !ab.isEmpty, let cab = candidate.amountAnchorBucket, !cab.isEmpty, ab != cab { return false }
                    return true
                }.sorted { $0.lastUsedAt > $1.lastUsedAt }
            }
            return result
        }
    }

    /// Return families with same screen type and similar structure (e.g. same row structure signature prefix).
    func familiesMatching(screenType: ScreenType?, coarseFingerprint: String, rowStructureSignature: String?) -> [LayoutFamily] {
        queue.sync {
            var result = families.filter { $0.coarseFingerprint == coarseFingerprint }
            if let st = screenType, !result.isEmpty {
                result = result.filter { $0.screenType == st }
            }
            if let sig = rowStructureSignature, !sig.isEmpty, !result.isEmpty {
                result = result.filter { $0.rowStructureSignature == sig || $0.rowStructureSignature.hasPrefix(sig.prefix(8)) }
            }
            return result
        }
    }

    func clearAll() {
        queue.sync {
            families.removeAll()
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(families) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func loadFromUserDefaults() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([LayoutFamily].self, from: data) else { return }
        families = decoded
    }
}
