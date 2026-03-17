//
//  ParsingRulesStore.swift
//  Airy
//
//  Stores GPT-generated parsing rule sets locally. Each set is separate (no mixing).
//  Parser tries each set in order; first non-empty valid result = 100% match when rule is promoted; else abstain → GPT fallback.
//

import Foundation
import CryptoKit

/// Outcome of local rules match. Only confidentParse blocks GPT; all others trigger fallback.
/// structureAssistOnly = layout family matched, hints only (no full parse).
enum LocalRuleOutcome: String, Codable, Equatable {
    case noMatch
    case structureAssistOnly
    case weakParse
    case confidentParse
    case abstain
    case hardFail
    /// Backward compatibility: same as confidentParse.
    static var confidentSuccess: LocalRuleOutcome { .confidentParse }
}

/// Trust stage for a rule set. Only promoted rules can return confidentSuccess and block GPT.
enum RuleTrustStage: String, Codable, Equatable {
    case candidate
    case observed
    case promoted
}

/// Result of tryMatchWithOutcome / tryStructureAssist: outcome, optional items, structure-assist hints, reason for abstain/hardFail.
struct LocalRuleMatchResult {
    let outcome: LocalRuleOutcome
    let items: [ParsedTransactionItem]?
    let matchedRuleId: String?
    let matchedRuleTrustStage: RuleTrustStage?
    let reasonAbstain: String?
    /// Layout family that matched (when outcome is structureAssistOnly, weakParse, or confidentParse).
    let layoutFamilyId: String?
    /// Local rules suggested this screen type (from matched family).
    let didHelpScreenType: Bool
    /// Local rules helped row grouping (e.g. structure signature matched).
    let didHelpRowGrouping: Bool
    /// Confidence 0...1 that structure assist was useful.
    let localAssistConfidence: Double
    /// When outcome is hardFail or noMatch, short reason (e.g. "no layout family matched").
    let reasonForHardFail: String?
    /// 1.0 = exact structural match, ~0.5 = bucket-only; nil if no family matched.
    let layoutFamilySimilarityScore: Double?
    /// useCount of matched family; nil if no match.
    let familyClusterSize: Int?
    /// True when localAssistConfidence was computed from match type (exact vs bucket).
    let localAssistConfidenceComputed: Bool
    /// Why we reused a family: "strong", "weak", "new", or nil if no match.
    let familyReuseReason: String?
    /// True when match was exact structuralFingerprint.
    let wasStrongReuse: Bool
    /// True when match was fallback (bucket + screenType + densityBucket).
    let wasWeakReuse: Bool
    /// Which structural features matched (e.g. "exact" or "lineBucket,density,screenType").
    let matchedStructuralFeatures: String?
    /// When weak reuse was considered but rejected (e.g. "density mismatch").
    let rejectedStructuralFeatures: String?
    /// Threshold used: "strong", "weak", or "none".
    let familyReuseThresholdUsed: String?
    /// When no family matched: reason (e.g. hard identity or soft tolerance).
    let familyRejectionReason: String?
    /// Which band was exceeded when no match (lineCountVariance, densityVariance, rowSigVariance, etc.).
    let familyToleranceExceeded: String?

    init(outcome: LocalRuleOutcome, items: [ParsedTransactionItem]? = nil, matchedRuleId: String? = nil, matchedRuleTrustStage: RuleTrustStage? = nil, reasonAbstain: String? = nil, layoutFamilyId: String? = nil, didHelpScreenType: Bool = false, didHelpRowGrouping: Bool = false, localAssistConfidence: Double = 0, reasonForHardFail: String? = nil, layoutFamilySimilarityScore: Double? = nil, familyClusterSize: Int? = nil, localAssistConfidenceComputed: Bool = false, familyReuseReason: String? = nil, wasStrongReuse: Bool = false, wasWeakReuse: Bool = false, matchedStructuralFeatures: String? = nil, rejectedStructuralFeatures: String? = nil, familyReuseThresholdUsed: String? = nil, familyRejectionReason: String? = nil, familyToleranceExceeded: String? = nil) {
        self.outcome = outcome
        self.items = items
        self.matchedRuleId = matchedRuleId
        self.matchedRuleTrustStage = matchedRuleTrustStage
        self.reasonAbstain = reasonAbstain
        self.layoutFamilyId = layoutFamilyId
        self.didHelpScreenType = didHelpScreenType
        self.didHelpRowGrouping = didHelpRowGrouping
        self.localAssistConfidence = localAssistConfidence
        self.reasonForHardFail = reasonForHardFail
        self.layoutFamilySimilarityScore = layoutFamilySimilarityScore
        self.familyClusterSize = familyClusterSize
        self.localAssistConfidenceComputed = localAssistConfidenceComputed
        self.familyReuseReason = familyReuseReason
        self.wasStrongReuse = wasStrongReuse
        self.wasWeakReuse = wasWeakReuse
        self.matchedStructuralFeatures = matchedStructuralFeatures
        self.rejectedStructuralFeatures = rejectedStructuralFeatures
        self.familyReuseThresholdUsed = familyReuseThresholdUsed
        self.familyRejectionReason = familyRejectionReason
        self.familyToleranceExceeded = familyToleranceExceeded
    }
}

/// Rules generated by GPT for a specific OCR format. Applied locally.
struct ParsingRules: Codable, Equatable {
    /// Extra regex patterns for junk lines (e.g. "page 2", "order #12345")
    var extraJunkPatterns: [String]?
    /// Additional date regex patterns (Swift regex compatible)
    var datePatterns: [String]?
    /// Currency symbol → code mapping (e.g. "₽" → "RUB")
    var currencySymbols: [String: String]?
    /// Default currency when not detected (e.g. "USD", "RUB")
    var defaultCurrency: String?
    /// Optional custom amount regex
    var amountPattern: String?
}

/// One rule set from one GPT response. Stored in order; tried in order.
struct RuleSetEntry: Codable, Equatable {
    let id: String
    let signature: String
    let rules: ParsingRules
    /// Trust stage: candidate → observed → promoted. Only promoted can block GPT. Default .candidate for legacy entries.
    var trustStage: RuleTrustStage
    /// Number of successful uses (different screenshots). Used to promote candidate→observed→promoted.
    var successUseCount: Int
    /// Optional layout/screen fingerprint for tighter applicability. Nil = match any (legacy).
    var layoutSignature: String?
    /// Image hashes where this rule was used successfully (for promotion: different screenshots).
    var lastUsedImageHashes: [String]

    enum CodingKeys: String, CodingKey {
        case id, signature, rules, trustStage, successUseCount, layoutSignature, lastUsedImageHashes
    }

    init(id: String, signature: String, rules: ParsingRules, trustStage: RuleTrustStage = .candidate, successUseCount: Int = 0, layoutSignature: String? = nil, lastUsedImageHashes: [String] = []) {
        self.id = id
        self.signature = signature
        self.rules = rules
        self.trustStage = trustStage
        self.successUseCount = successUseCount
        self.layoutSignature = layoutSignature
        self.lastUsedImageHashes = lastUsedImageHashes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        signature = try c.decode(String.self, forKey: .signature)
        rules = try c.decode(ParsingRules.self, forKey: .rules)
        trustStage = (try c.decodeIfPresent(RuleTrustStage.self, forKey: .trustStage)) ?? .candidate
        successUseCount = (try c.decodeIfPresent(Int.self, forKey: .successUseCount)) ?? 0
        layoutSignature = try c.decodeIfPresent(String.self, forKey: .layoutSignature)
        lastUsedImageHashes = (try c.decodeIfPresent([String].self, forKey: .lastUsedImageHashes)) ?? []
    }
}

final class ParsingRulesStore {
    static let shared = ParsingRulesStore()
    private let key = "parsingRuleSets"
    private let lastOcrKey = "parsingRules_lastOcr"
    private let imageCacheKey = "parsingRules_imageHashCache"
    private let maxRuleSets = 50
    private let maxImageCacheEntries = 100
    private var ruleSets: [RuleSetEntry] = []
    private var imageHashToItems: [String: [ParsedTransactionItem]] = [:]
    private let queue = DispatchQueue(label: "parsingRulesStore")

    private init() {
        loadFromUserDefaults()
        loadImageCache()
    }

    /// Return cached extraction for this image hash (same image → no GPT call).
    func cachedResult(forImageHash hash: String) -> [ParsedTransactionItem]? {
        queue.sync { imageHashToItems[hash] }
    }

    /// Store GPT extraction by image hash so the same image is not sent to GPT again.
    func cacheResult(_ items: [ParsedTransactionItem], forImageHash hash: String) {
        queue.sync {
            imageHashToItems[hash] = items
            if imageHashToItems.count > maxImageCacheEntries {
                let keysToRemove = Array(imageHashToItems.keys.prefix(imageHashToItems.count - maxImageCacheEntries))
                keysToRemove.forEach { imageHashToItems.removeValue(forKey: $0) }
            }
            persistImageCache()
        }
    }

    /// Append a new rule set (from a new GPT response or manual "Generate rules"). Does not merge with existing.
    func appendRuleSet(rules: ParsingRules, forOcrText ocrText: String) {
        saveForOcr(rules: rules, ocrText: ocrText)
    }

    /// Save rules for this OCR (appends a new rule set). Used by Settings "Generate rules" and by import GPT flow.
    func saveForOcr(rules: ParsingRules, ocrText: String) {
        queue.sync {
            let sig = fingerprint(ocrText)
            let normalized = Self.normalizedOCRText(ocrText)
            let layoutSig = Self.screenFingerprint(normalizedText: normalized)
            let entry = RuleSetEntry(id: UUID().uuidString, signature: sig, rules: rules, layoutSignature: layoutSig)
            ruleSets.append(entry)
            if ruleSets.count > maxRuleSets {
                ruleSets.removeFirst(ruleSets.count - maxRuleSets)
            }
            persist()
        }
    }

    /// Returns true if items are valid and their amounts/dates appear in ocrText. Used by ExtractionRulesMatcher.
    func isValidResultMatchingOcr(_ items: [ParsedTransactionItem], ocrText: String) -> Bool {
        isValidParseResult(items) && parsedResultMatchesOcrText(items, ocrText: ocrText)
    }

    /// Try each rule set in order. Returns first non-empty valid parse result that also matches OCR content, or nil if none match.
    /// Rejects local results when amounts/dates don't appear in the text (e.g. same app, different page → wrong extraction).
    /// For outcome-based flow use tryMatchWithOutcome; this returns non-nil only for confidentSuccess (promoted + not obviously incomplete).
    func tryMatch(ocrText: String, parser: LocalOCRParser, baseCurrency: String) -> [ParsedTransactionItem]? {
        let result = tryMatchWithOutcome(
            ocrText: ocrText,
            parser: parser,
            baseCurrency: baseCurrency,
            transactionLikeRowEstimate: nil,
            strongAmountRowCount: nil,
            repeatedRowClusterCount: nil
        )
        if case .confidentParse = result.outcome, let items = result.items, !items.isEmpty {
            return items
        }
        return nil
    }

    /// Outcome-based match: confidentSuccess (only if promoted and not obviously incomplete), abstain, or hardFail.
    /// When abstain/hardFail the pipeline should fall back to GPT. Pass row estimates for "obviously incomplete" detection.
    func tryMatchWithOutcome(
        ocrText: String,
        parser: LocalOCRParser,
        baseCurrency: String,
        transactionLikeRowEstimate: Int?,
        strongAmountRowCount: Int?,
        repeatedRowClusterCount: Int?
    ) -> LocalRuleMatchResult {
        queue.sync {
            let normalizedOcr = Self.normalizedOCRText(ocrText)
            let currentFp = Self.screenFingerprint(normalizedText: normalizedOcr)
            for index in ruleSets.indices {
                let entry = ruleSets[index]
                if let layoutSig = entry.layoutSignature, layoutSig != currentFp {
                    continue
                }
                let items = parser.parse(ocrText: ocrText, baseCurrency: baseCurrency, customRules: entry.rules)
                guard isValidParseResult(items), parsedResultMatchesOcrText(items, ocrText: ocrText) else { continue }

                let txEst = transactionLikeRowEstimate ?? 0
                let strongRows = strongAmountRowCount ?? 0
                let clusterCount = repeatedRowClusterCount ?? 0
                let obviouslyIncomplete = items.count == 1 && (txEst >= 2 || strongRows >= 2 || clusterCount >= 2)

                if entry.trustStage != .promoted {
                    return LocalRuleMatchResult(outcome: .abstain, items: items, matchedRuleId: entry.id, matchedRuleTrustStage: entry.trustStage, reasonAbstain: "rule not promoted (\(entry.trustStage.rawValue))")
                }
                if obviouslyIncomplete {
                    return LocalRuleMatchResult(outcome: .abstain, items: items, matchedRuleId: entry.id, matchedRuleTrustStage: entry.trustStage, reasonAbstain: "single item but repeated row structure (txEst=\(txEst), strong=\(strongRows), clusters=\(clusterCount))")
                }
                return LocalRuleMatchResult(outcome: .confidentParse, items: items, matchedRuleId: entry.id, matchedRuleTrustStage: entry.trustStage, reasonAbstain: nil)
            }
            return LocalRuleMatchResult(outcome: .hardFail, items: nil, matchedRuleId: nil, matchedRuleTrustStage: nil, reasonAbstain: nil, reasonForHardFail: "no rule set matched layout or valid parse")
        }
    }

    /// Structure-assist first: match by layout family (structural fingerprint). If a family matches, return structureAssistOnly with computed confidence; else try rule sets and convert hardFail to noMatch.
    func tryStructureAssist(
        ocrText: String,
        parser: LocalOCRParser,
        baseCurrency: String,
        transactionLikeRowEstimate: Int?,
        strongAmountRowCount: Int?,
        repeatedRowClusterCount: Int?,
        rowStructureSignature: String? = nil,
        amountAnchorBucket: String? = nil
    ) -> LocalRuleMatchResult {
        let normalizedOcr = Self.normalizedOCRText(ocrText)
        let structuralFp = LayoutFamilyStore.structuralFingerprint(normalizedText: normalizedOcr)
        let densityBucket = LayoutFamilyStore.densityBucket(normalizedText: normalizedOcr)
        let lineCount = normalizedOcr.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.count
        let inferredScreenType: ScreenType = lineCount >= 11 ? .transactionList : .unknown
        // Exact structural match first
        var families = LayoutFamilyStore.shared.familiesMatching(structuralFingerprint: structuralFp, screenType: nil, densityBucket: nil, rowStructureSignature: nil, amountAnchorBucket: nil, fallbackToBucket: false)
        var profileRejectionReason: String?
        if families.isEmpty {
            let lineBucket = LayoutFamilyStore.lineCountBucket(fromStructuralFingerprint: structuralFp)
            let profileResult = LayoutFamilyStore.shared.familiesMatchingProfile(lineCountBucket: lineBucket, screenType: inferredScreenType, densityBucket: densityBucket, amountAnchorBucket: amountAnchorBucket, rowStructureSignature: rowStructureSignature)
            families = profileResult.families
            profileRejectionReason = profileResult.rejectionReason
        }
        if let first = families.first {
            let exactMatch = first.structuralFingerprint == structuralFp
            // Strong reuse: evaluate against family profile (representatives + dominant/secondary), not legacy single fields.
            let sigPrefix = (rowStructureSignature ?? "").isEmpty ? "" : String((rowStructureSignature ?? "").prefix(8))
            let rowReps = first.rowStructureRepresentatives.isEmpty
                ? (first.rowStructureSignature.isEmpty ? [] : [String(first.rowStructureSignature.prefix(8))])
                : first.rowStructureRepresentatives
            let rowSigMatch = !sigPrefix.isEmpty && !rowReps.isEmpty && rowReps.contains { rep in rep.hasPrefix(sigPrefix) || sigPrefix.hasPrefix(rep) }
            let currentAnchor = amountAnchorBucket ?? "unknown"
            let anchorDom = first.amountAnchorDominant ?? first.amountAnchorBucket ?? "unknown"
            let anchorSec = first.amountAnchorSecondary
            let amountAnchorMatch = !currentAnchor.isEmpty && currentAnchor != "unknown" && (currentAnchor == anchorDom || (anchorSec != nil && currentAnchor == anchorSec))
            let fullProfileMatch = rowSigMatch && amountAnchorMatch
            let strongReuse = exactMatch || fullProfileMatch
            let reuseReason = strongReuse ? "strong" : "weak"
            let thresholdUsed = strongReuse ? "strong" : "weak"
            let localAssistConfidence = strongReuse ? 0.88 : 0.58
            let similarityScore = strongReuse ? 1.0 : 0.6
            let matchedFeatures: String
            if exactMatch { matchedFeatures = "exact" }
            else if fullProfileMatch { matchedFeatures = "lineBucket,density,screenType,rowSig,amountAnchor" }
            else { matchedFeatures = "lineBucket,density,screenType" }
            return LocalRuleMatchResult(
                outcome: .structureAssistOnly,
                items: nil,
                matchedRuleId: nil,
                matchedRuleTrustStage: nil,
                reasonAbstain: nil,
                layoutFamilyId: first.id,
                didHelpScreenType: true,
                didHelpRowGrouping: true,
                localAssistConfidence: localAssistConfidence,
                reasonForHardFail: nil,
                layoutFamilySimilarityScore: similarityScore,
                familyClusterSize: first.useCount,
                localAssistConfidenceComputed: true,
                familyReuseReason: reuseReason,
                wasStrongReuse: strongReuse,
                wasWeakReuse: !strongReuse,
                matchedStructuralFeatures: matchedFeatures,
                rejectedStructuralFeatures: nil,
                familyReuseThresholdUsed: thresholdUsed,
                familyRejectionReason: nil,
                familyToleranceExceeded: nil
            )
        }
        let result = tryMatchWithOutcome(
            ocrText: ocrText,
            parser: parser,
            baseCurrency: baseCurrency,
            transactionLikeRowEstimate: transactionLikeRowEstimate,
            strongAmountRowCount: strongAmountRowCount,
            repeatedRowClusterCount: repeatedRowClusterCount
        )
        if result.outcome == .hardFail {
            return LocalRuleMatchResult(
                outcome: .noMatch,
                items: nil,
                matchedRuleId: nil,
                matchedRuleTrustStage: nil,
                reasonAbstain: nil,
                layoutFamilyId: nil,
                didHelpScreenType: false,
                didHelpRowGrouping: false,
                localAssistConfidence: 0,
                reasonForHardFail: result.reasonForHardFail ?? profileRejectionReason ?? "no layout family or rule set matched",
                familyRejectionReason: profileRejectionReason,
                familyToleranceExceeded: profileRejectionReason
            )
        }
        return result
    }

    /// Call when a rule produced confidentParse and we returned its items (no GPT). Updates successUseCount and promotes candidate→observed→promoted.
    func recordSuccessfulLocalUse(ruleId: String?, imageHash: String) {
        guard let ruleId = ruleId else { return }
        queue.sync {
            guard let index = ruleSets.firstIndex(where: { $0.id == ruleId }) else { return }
            var entry = ruleSets[index]
            if !entry.lastUsedImageHashes.contains(imageHash) {
                entry.lastUsedImageHashes.append(imageHash)
                if entry.lastUsedImageHashes.count > 20 {
                    entry.lastUsedImageHashes.removeFirst(entry.lastUsedImageHashes.count - 20)
                }
            }
            entry.successUseCount = entry.lastUsedImageHashes.count
            if entry.successUseCount >= 1 && entry.trustStage == .candidate {
                entry.trustStage = .observed
            }
            if entry.successUseCount >= 3 && entry.trustStage == .observed {
                entry.trustStage = .promoted
            }
            ruleSets[index] = entry
            persist()
        }
    }

    /// Last OCR from import. Used for "Generate rules from last import" in Settings.
    var lastOcrSample: String? {
        get { UserDefaults.standard.string(forKey: lastOcrKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastOcrKey) }
    }

    func clearAll() {
        queue.sync {
            ruleSets.removeAll()
            imageHashToItems.removeAll()
            UserDefaults.standard.removeObject(forKey: key)
            UserDefaults.standard.removeObject(forKey: lastOcrKey)
            UserDefaults.standard.removeObject(forKey: imageCacheKey)
        }
    }

    private func isValidParseResult(_ items: [ParsedTransactionItem]) -> Bool {
        guard !items.isEmpty else { return false }
        for item in items {
            if item.amount < 0.01 || item.amount > 50_000 { return false }
            guard let y = Int(String(item.date.prefix(4))), (2020...2030).contains(y) else { return false }
            if (item.merchant?.count ?? 0) < 2 { return false }
        }
        return true
    }

    /// Only accept local parse if extracted amounts and dates appear in the OCR text (avoids wrong data when same layout, different content).
    private func parsedResultMatchesOcrText(_ items: [ParsedTransactionItem], ocrText: String) -> Bool {
        let normalized = ocrText.replacingOccurrences(of: ",", with: ".")
        for item in items {
            let amountStr = formatAmountForMatch(item.amount)
            if !amountAppearsInText(amountStr, ocrText: normalized) { return false }
            let year = String(item.date.prefix(4))
            if !normalized.contains(year) { return false }
            if item.date.count >= 10 {
                let day = String(item.date.suffix(2))
                if !normalized.contains(day) { return false }
            }
        }
        return true
    }

    private func formatAmountForMatch(_ amount: Double) -> (intPart: String, fracPart: String) {
        let intPart = Int(amount)
        let frac = Int(round((amount - Double(intPart)) * 100))
        return (String(intPart), frac > 0 ? String(frac) : "")
    }

    private func amountAppearsInText(_ amount: (intPart: String, fracPart: String), ocrText: String) -> Bool {
        guard ocrText.contains(amount.intPart) else { return false }
        if !amount.fracPart.isEmpty {
            if amount.fracPart.count == 1, !ocrText.contains(amount.fracPart) { return false }
            if amount.fracPart.count == 2, !ocrText.contains(amount.fracPart) { return false }
        }
        return true
    }

    private func fingerprint(_ ocrText: String) -> String {
        let s = String(ocrText.prefix(300))
        var hash: UInt64 = 5381
        for c in s.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(c)
        }
        return String(hash)
    }

    /// Same semantics as OCRNormalizer.normalizedOCRText (duplicated here to avoid cross-target dependency).
    private static func normalizedOCRText(_ raw: String) -> String {
        raw
            .precomposedStringWithCompatibilityMapping
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: "\n")
            .map { line in
                line.trimmingCharacters(in: .whitespaces)
                    .split(separator: " ")
                    .joined(separator: " ")
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// Same semantics as OCRNormalizer.screenFingerprint (structural fingerprint for rule applicability).
    private static func screenFingerprint(normalizedText: String) -> String {
        let lines = normalizedText.split(separator: "\n")
        let lineCount = lines.count
        let totalLen = normalizedText.count
        let firstChars = lines.prefix(20).map { $0.prefix(1).description }.joined()
        let data = Data("\(lineCount)|\(totalLen)|\(firstChars)".utf8)
        let hash = SHA256.hash(data: data)
        return hash.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(ruleSets) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func persistImageCache() {
        if let data = try? JSONEncoder().encode(imageHashToItems) {
            UserDefaults.standard.set(data, forKey: imageCacheKey)
        }
    }

    private func loadImageCache() {
        guard let data = UserDefaults.standard.data(forKey: imageCacheKey),
              let decoded = try? JSONDecoder().decode([String: [ParsedTransactionItem]].self, from: data) else { return }
        imageHashToItems = decoded
    }

    private func loadFromUserDefaults() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([RuleSetEntry].self, from: data) else { return }
        ruleSets = decoded
    }
}
