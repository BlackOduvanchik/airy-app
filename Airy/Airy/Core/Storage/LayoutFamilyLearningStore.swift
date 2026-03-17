//
//  LayoutFamilyLearningStore.swift
//  Airy
//
//  Self-learning store: accumulates structural row examples per layout family,
//  builds row archetypes, tracks maturity levels, and drives the decision of
//  when local extraction is good enough to skip GPT.
//

import Foundation

// MARK: - Amount position

enum LearnedAmountPosition: String, Codable {
    case suffix     // amount at end of line (right-aligned)
    case prefix     // amount at start
    case inline     // somewhere in the middle
    case unknown
}

// MARK: - Maturity levels

/// Maturity level of a layout family. Drives routing: GPT-first → local-first.
enum FamilyMaturityLevel: String, Codable {
    /// 0–4 confirmed screenshots. Always use GPT.
    case apprentice
    /// 5–9 confirmed screenshots. Try local; GPT validates.
    case learning
    /// 10–14 confirmed screenshots + archetype confidence ≥ 0.75. Local primary; GPT on gate failure.
    case proficient
    /// 15+ confirmed screenshots + archetype confidence ≥ 0.88. Local with relaxed gates; GPT only on mismatch.
    case expert
}

// MARK: - Confirmed row example

enum ConfirmedExampleSource: String, Codable {
    case gptTeacher     // matched from GPT result
    case userConfirmed  // user approved without changes
    case userCorrected  // user made changes (weaker signal)
}

/// Structural fingerprint of one confirmed transaction row group.
/// Stores only structure — no merchant names, amounts, or dates.
struct ConfirmedRowExample: Codable {
    var familyId: String
    var imageHash: String
    /// Number of OCR lines in this row group.
    var rowLineCount: Int
    /// Per-line length bucket for first 3 lines: "S" (<16 chars), "M" (<36), "L" (≥36).
    var lineLengthSignature: [String]
    /// Where the amount token sits within the joined row text.
    var amountPosition: LearnedAmountPosition
    /// Does this row contain an inline date (on the same line as amount/merchant)?
    var hasDateInline: Bool
    /// Line index (0-based) within the group where a date was found, if any.
    var dateLineIndex: Int?
    var confirmedAt: Date
    var source: ConfirmedExampleSource
}

// MARK: - Row archetype

/// Learned structural template for a transaction row within a family.
/// Built from majority-vote over ConfirmedRowExamples.
struct RowArchetype: Codable {
    /// Most common row line count.
    var dominantLineCount: Int
    /// Range covering all observed line counts (clamped to reasonable bounds).
    var minLineCount: Int
    var maxLineCount: Int
    /// Most common amount position.
    var amountPosition: LearnedAmountPosition
    /// Element-wise dominant length signature (positions 0, 1, 2).
    var lineLengthSignature: [String]
    /// Whether most confirmed rows have date headers separating groups.
    var hasDateHeaders: Bool
    /// Whether the date is typically inline within the row.
    var dateInline: Bool
    /// Confidence: fraction of examples agreeing with dominant values (0...1).
    var confidence: Double
    /// How many confirmed examples built this archetype.
    var confirmedExampleCount: Int
    /// Consecutive successful local extractions since last failure.
    var consecutiveSuccessCount: Int
    /// Consecutive failed local extractions (gate rejected or user corrected).
    var consecutiveFailCount: Int
}

// MARK: - Extraction outcome

struct ExtractionOutcome: Codable {
    var imageHash: String
    /// true = local extraction passed gates and was used.
    var wasAccepted: Bool
    /// true = user made corrections on this image's pending transactions.
    var wasUserCorrected: Bool
    var timestamp: Date
}

// MARK: - Family learning record

struct FamilyLearningRecord: Codable {
    var familyId: String
    var maturityLevel: FamilyMaturityLevel
    /// Number of distinct image hashes that contributed confirmed examples.
    var confirmedScreenshotCount: Int
    /// Total number of confirmed row examples accumulated.
    var totalExamplesCount: Int
    /// Learned archetype; nil until enough examples (≥ 5).
    var archetype: RowArchetype?
    /// Up to 30 confirmed image hashes for deduplication.
    var confirmedImageHashes: [String]
    /// Rolling window of last 20 extraction outcomes for degradation tracking.
    var recentOutcomes: [ExtractionOutcome]
    /// Recent user corrections count (rolling 5 screenshots).
    var consecutiveUserCorrectionCount: Int
    var lastUpdatedAt: Date
}

// MARK: - Store

final class LayoutFamilyLearningStore {
    static let shared = LayoutFamilyLearningStore()

    private let key = "layoutFamilyLearning_v1"
    private let maxHashesPerRecord = 30
    private let maxOutcomesPerRecord = 20
    private var records: [String: FamilyLearningRecord] = [:]
    private let queue = DispatchQueue(label: "layoutFamilyLearningStore")

    private init() {
        loadFromUserDefaults()
    }

    // MARK: - Public API

    /// Record structural examples from a GPT teacher mapping or user confirmation.
    /// Call after GPTTeacherMapper successfully maps GPT transactions to OCR rows.
    func recordConfirmedExamples(_ examples: [ConfirmedRowExample], familyId: String, imageHash: String) {
        guard !examples.isEmpty else { return }
        queue.sync {
            var record = records[familyId] ?? makeEmptyRecord(familyId: familyId)
            // Deduplicate by image hash — only learn from each screenshot once
            guard !record.confirmedImageHashes.contains(imageHash) else { return }
            record.confirmedImageHashes.append(imageHash)
            if record.confirmedImageHashes.count > maxHashesPerRecord {
                record.confirmedImageHashes.removeFirst(record.confirmedImageHashes.count - maxHashesPerRecord)
            }
            record.confirmedScreenshotCount += 1
            record.totalExamplesCount += examples.count
            record.lastUpdatedAt = Date()
            records[familyId] = record
            rebuildArchetypeIfReadyOnQueue(familyId: familyId, newExamples: examples)
            persist()
        }
    }

    /// Record the outcome of a local extraction attempt for this family.
    func recordExtractionOutcome(familyId: String, imageHash: String, wasAccepted: Bool, wasUserCorrected: Bool) {
        queue.sync {
            var record = records[familyId] ?? makeEmptyRecord(familyId: familyId)
            let outcome = ExtractionOutcome(
                imageHash: imageHash,
                wasAccepted: wasAccepted,
                wasUserCorrected: wasUserCorrected,
                timestamp: Date()
            )
            record.recentOutcomes.append(outcome)
            if record.recentOutcomes.count > maxOutcomesPerRecord {
                record.recentOutcomes.removeFirst(record.recentOutcomes.count - maxOutcomesPerRecord)
            }
            if wasAccepted && !wasUserCorrected {
                record.archetype?.consecutiveSuccessCount += 1
                record.archetype?.consecutiveFailCount = 0
                record.consecutiveUserCorrectionCount = 0
            } else {
                record.archetype?.consecutiveFailCount += 1
                record.archetype?.consecutiveSuccessCount = 0
            }
            record.lastUpdatedAt = Date()
            records[familyId] = record
            persist()
        }
    }

    /// Record user feedback when pending transactions are confirmed or rejected.
    /// - Parameter correctionMade: true if user edited any field (merchant, category, date, amount).
    func recordUserFeedback(familyId: String, imageHash: String, correctionMade: Bool) {
        queue.sync {
            var record = records[familyId] ?? makeEmptyRecord(familyId: familyId)
            if correctionMade {
                record.consecutiveUserCorrectionCount += 1
                record.archetype?.consecutiveFailCount += 1
                record.archetype?.consecutiveSuccessCount = 0
            } else {
                record.consecutiveUserCorrectionCount = 0
                record.archetype?.consecutiveSuccessCount += 1
                record.archetype?.consecutiveFailCount = 0
            }
            record.lastUpdatedAt = Date()
            records[familyId] = record
            persist()
        }
    }

    /// Current maturity level for a family.
    func maturityLevel(forFamilyId id: String) -> FamilyMaturityLevel {
        queue.sync {
            records[id]?.maturityLevel ?? .apprentice
        }
    }

    /// Learned row archetype for a family, if built.
    func archetype(forFamilyId id: String) -> RowArchetype? {
        queue.sync {
            records[id]?.archetype
        }
    }

    /// Confirmed screenshot count for a family.
    func confirmedScreenshotCount(forFamilyId id: String) -> Int {
        queue.sync {
            records[id]?.confirmedScreenshotCount ?? 0
        }
    }

    /// Check and apply degradation based on recent failure rate.
    /// Call after a failed extraction or after user corrections.
    func checkAndApplyDegradation(familyId: String) {
        queue.sync {
            guard var record = records[familyId] else { return }
            let changed = applyDegradationIfNeeded(&record)
            if changed {
                records[familyId] = record
                persist()
            }
        }
    }

    func clearAll() {
        queue.sync {
            records.removeAll()
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - Private: archetype building

    private func rebuildArchetypeIfReadyOnQueue(familyId: String, newExamples: [ConfirmedRowExample]) {
        guard var record = records[familyId] else { return }
        let count = record.totalExamplesCount
        // Rebuild at milestones: 5, 10, 15, 20, and every 10 thereafter
        let shouldRebuild = count == 5 || count == 10 || count == 15 || count == 20 || (count > 20 && count % 10 == 0)
        guard shouldRebuild else {
            // Still update the record (maturity might advance from screenshot count alone)
            record.maturityLevel = computeMaturityLevel(record: record)
            records[familyId] = record
            return
        }

        // Load all accumulated examples from UserDefaults (stored separately keyed by familyId)
        let allExamples = loadExamples(forFamilyId: familyId) + newExamples
        guard allExamples.count >= 5 else {
            record.maturityLevel = computeMaturityLevel(record: record)
            records[familyId] = record
            return
        }

        let archetype = buildArchetype(from: allExamples)
        record.archetype = archetype
        record.maturityLevel = computeMaturityLevel(record: record)
        records[familyId] = record

        // Persist examples separately so they survive but don't bloat the main record
        saveExamples(allExamples.suffix(50).map { $0 }, forFamilyId: familyId)
    }

    private func buildArchetype(from examples: [ConfirmedRowExample]) -> RowArchetype {
        let count = examples.count

        // Dominant line count (mode)
        let lineCountMode = mode(values: examples.map { $0.rowLineCount }) ?? 1
        let minLine = examples.map { $0.rowLineCount }.min() ?? lineCountMode
        let maxLine = examples.map { $0.rowLineCount }.max() ?? lineCountMode

        // Amount position (mode)
        let amountPositions = examples.map { $0.amountPosition.rawValue }
        let amountPositionMode = mode(values: amountPositions) ?? LearnedAmountPosition.unknown.rawValue
        let amountPosition = LearnedAmountPosition(rawValue: amountPositionMode) ?? .unknown

        // Line length signature: element-wise mode for positions 0, 1, 2
        var sigResult: [String] = []
        for pos in 0..<3 {
            let values = examples.compactMap { ex -> String? in
                pos < ex.lineLengthSignature.count ? ex.lineLengthSignature[pos] : nil
            }
            sigResult.append(mode(values: values) ?? "M")
        }

        // Date inline vote
        let dateInlineVotes = examples.filter { $0.hasDateInline }.count
        let dateInline = dateInlineVotes > count / 2

        // Date header detection: rows that have NO inline date are likely part of a dated-header layout
        let hasDateHeaders = !dateInline && examples.filter { $0.dateLineIndex != nil }.count > count / 3

        // Confidence: fraction of examples agreeing with dominant line count and amount position
        let lineCountAgreement = Double(examples.filter { $0.rowLineCount == lineCountMode }.count) / Double(count)
        let amountAgreement = Double(examples.filter { $0.amountPosition.rawValue == amountPositionMode }.count) / Double(count)
        let confidence = (lineCountAgreement * 0.6 + amountAgreement * 0.4)

        return RowArchetype(
            dominantLineCount: lineCountMode,
            minLineCount: minLine,
            maxLineCount: maxLine,
            amountPosition: amountPosition,
            lineLengthSignature: sigResult,
            hasDateHeaders: hasDateHeaders,
            dateInline: dateInline,
            confidence: confidence,
            confirmedExampleCount: count,
            consecutiveSuccessCount: 0,
            consecutiveFailCount: 0
        )
    }

    // MARK: - Private: maturity

    private func computeMaturityLevel(record: FamilyLearningRecord) -> FamilyMaturityLevel {
        let screenshots = record.confirmedScreenshotCount
        let confidence = record.archetype?.confidence ?? 0.0

        // Check degradation first
        let failRate = recentFailRate(record: record)
        switch record.maturityLevel {
        case .expert:
            if failRate >= 0.30 { return .proficient }
        case .proficient:
            if failRate >= 0.40 { return .learning }
        case .learning:
            if failRate >= 0.60 { return .apprentice }
        case .apprentice:
            break
        }

        // 3 consecutive user corrections → immediate downgrade
        if record.consecutiveUserCorrectionCount >= 3 {
            switch record.maturityLevel {
            case .expert: return .proficient
            case .proficient: return .learning
            case .learning: return .apprentice
            case .apprentice: return .apprentice
            }
        }

        // Upgrade path
        if screenshots >= 15 && confidence >= 0.88 { return .expert }
        if screenshots >= 10 && confidence >= 0.75 { return .proficient }
        if screenshots >= 5 { return .learning }
        return .apprentice
    }

    private func recentFailRate(record: FamilyLearningRecord) -> Double {
        let outcomes = record.recentOutcomes
        guard outcomes.count >= 5 else { return 0 }
        let failures = outcomes.filter { !$0.wasAccepted || $0.wasUserCorrected }.count
        return Double(failures) / Double(outcomes.count)
    }

    @discardableResult
    private func applyDegradationIfNeeded(_ record: inout FamilyLearningRecord) -> Bool {
        let newLevel = computeMaturityLevel(record: record)
        if newLevel.degradationRank < record.maturityLevel.degradationRank {
            record.maturityLevel = newLevel
            // Reduce archetype confidence to force eventual rebuild
            record.archetype?.confidence *= 0.7
            record.archetype?.consecutiveFailCount = 0
            record.archetype?.consecutiveSuccessCount = 0
            return true
        }
        return false
    }

    // MARK: - Private: helpers

    private func makeEmptyRecord(familyId: String) -> FamilyLearningRecord {
        FamilyLearningRecord(
            familyId: familyId,
            maturityLevel: .apprentice,
            confirmedScreenshotCount: 0,
            totalExamplesCount: 0,
            archetype: nil,
            confirmedImageHashes: [],
            recentOutcomes: [],
            consecutiveUserCorrectionCount: 0,
            lastUpdatedAt: Date()
        )
    }

    private func mode<T: Hashable>(values: [T]) -> T? {
        guard !values.isEmpty else { return nil }
        var freq: [T: Int] = [:]
        for v in values { freq[v, default: 0] += 1 }
        return freq.max(by: { $0.value < $1.value })?.key
    }

    // MARK: - Persistence (records)

    private func persist() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func loadFromUserDefaults() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: FamilyLearningRecord].self, from: data) else { return }
        records = decoded
    }

    // MARK: - Persistence (examples, stored separately to avoid bloating main record)

    private func examplesKey(forFamilyId id: String) -> String { "layoutFamilyExamples_\(id)" }

    private func loadExamples(forFamilyId id: String) -> [ConfirmedRowExample] {
        guard let data = UserDefaults.standard.data(forKey: examplesKey(forFamilyId: id)),
              let decoded = try? JSONDecoder().decode([ConfirmedRowExample].self, from: data) else { return [] }
        return decoded
    }

    private func saveExamples(_ examples: [ConfirmedRowExample], forFamilyId id: String) {
        if let data = try? JSONEncoder().encode(examples) {
            UserDefaults.standard.set(data, forKey: examplesKey(forFamilyId: id))
        }
    }
}

// MARK: - MaturityLevel helpers

private extension FamilyMaturityLevel {
    /// Numeric rank for degradation comparison (lower = worse).
    var degradationRank: Int {
        switch self {
        case .apprentice: return 0
        case .learning: return 1
        case .proficient: return 2
        case .expert: return 3
        }
    }
}
