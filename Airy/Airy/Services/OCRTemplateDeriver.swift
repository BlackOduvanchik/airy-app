//
//  OCRTemplateDeriver.swift
//  Airy
//
//  Auto-derives an OCR extraction template from GPT output + raw OCR lines.
//  After GPT returns correct transactions we know the ground-truth values,
//  so we search for them in the OCR lines and record relative line offsets
//  (amount-anchor approach). No GPT call needed for template creation.
//

import Foundation

struct OCRTemplateDeriver {

    // MARK: - Public API

    /// Attempt to derive a reusable template from a successful GPT extraction.
    /// Returns nil when the layout is too inconsistent to template.
    static func derive(
        ocrLines: [String],
        transactions: [GPTExtractionTransaction]
    ) -> OCRTemplate? {
        let lines = normalizeLines(ocrLines)
        guard lines.count >= 2 else { return nil }

        // Use at most the first 5 transactions for derivation
        let sample = Array(transactions.prefix(5))
        guard sample.count >= 1 else { return nil }

        var observations: [(amountIdx: Int, merchantOffset: Int, dateOffset: Int, rule: MerchantRule)] = []

        for tx in sample {
            guard let amountIdx = findAmountLine(for: tx.amount, in: lines) else { continue }

            // --- merchant ---
            let merchantOffset: Int
            let rule: MerchantRule
            if let m = tx.merchant, !m.isEmpty {
                if let mIdx = findMerchantLine(m, in: lines, near: amountIdx) {
                    merchantOffset = mIdx - amountIdx
                    rule = merchantRule(for: lines[mIdx], merchant: m, amountLine: lines[amountIdx])
                } else {
                    // Merchant not found in OCR – skip this transaction
                    continue
                }
            } else {
                merchantOffset = 0
                rule = .entireLine
            }

            // --- date ---
            let dateOffset: Int
            if let dIdx = findDateLine(tx.date, in: lines, near: amountIdx) {
                dateOffset = dIdx - amountIdx
            } else {
                dateOffset = 0
            }

            observations.append((amountIdx: amountIdx, merchantOffset: merchantOffset, dateOffset: dateOffset, rule: rule))
        }

        guard observations.count >= 1 else { return nil }

        // Require ≥ 2/3 of observations to agree (or majority if only 1-2)
        let requiredAgreement = max(1, (observations.count * 2 + 2) / 3)

        let merchantOffsets = observations.map(\.merchantOffset)
        let dateOffsets = observations.map(\.dateOffset)
        let rules = observations.map(\.rule)

        guard let consensusMerchantOffset = majority(merchantOffsets, minCount: requiredAgreement),
              let consensusDateOffset = majority(dateOffsets, minCount: requiredAgreement),
              let consensusRule = majority(rules.map(\.rawValue), minCount: requiredAgreement)
        else { return nil }

        // linesPerBlock: average gap between consecutive amount-line indices
        let amountIndices = observations.map(\.amountIdx).sorted()
        let linesPerBlock: Int
        if amountIndices.count >= 2 {
            let gaps = zip(amountIndices, amountIndices.dropFirst()).map { $1 - $0 }
            linesPerBlock = max(1, gaps.reduce(0, +) / gaps.count)
        } else {
            // Single transaction: estimate from offsets
            linesPerBlock = max(2, abs(consensusMerchantOffset) + abs(consensusDateOffset) + 1)
        }

        let rule = MerchantRule(rawValue: consensusRule) ?? .entireLine
        // Reuse existing template with same structure instead of creating a new UUID each time
        if let existing = OCRTemplateStore.shared.findByStructure(
            merchantOffset: consensusMerchantOffset,
            dateOffset: consensusDateOffset,
            rule: rule
        ) {
            return existing
        }
        let template = OCRTemplate(
            id: UUID().uuidString,
            merchantLineOffset: consensusMerchantOffset,
            merchantExtractionRule: rule,
            dateLineOffset: consensusDateOffset,
            linesPerBlock: linesPerBlock,
            knownAmountPatterns: [],
            useCount: 0,
            lastUsed: Date(),
            bankHint: nil
        )
        return template
    }

    // MARK: - Line Search

    private static func findAmountLine(for amount: Double, in lines: [String]) -> Int? {
        // Format variants to search for
        let candidates = amountSearchStrings(amount)
        for (i, line) in lines.enumerated() {
            for candidate in candidates {
                if line.localizedCaseInsensitiveContains(candidate) {
                    return i
                }
            }
        }
        return nil
    }

    private static func findMerchantLine(_ merchant: String, in lines: [String], near anchor: Int) -> Int? {
        var m = merchant.trimmingCharacters(in: .whitespaces)
        // GPT often truncates long names: "MJT-EMQUART..." → strip marker before searching
        if m.hasSuffix("...") { m = String(m.dropLast(3)).trimmingCharacters(in: .whitespaces) }
        m = m.lowercased()
        guard !m.isEmpty else { return nil }
        // Search within ±5 lines of the anchor
        let lo = max(0, anchor - 5)
        let hi = min(lines.count - 1, anchor + 5)
        // Score 3: full substring match; Score 2: prefix match (≥5 chars); Score 1: first-word match
        let firstWord = m.split(separator: " ").first.map(String.init) ?? m
        let prefix5 = m.count >= 5 ? String(m.prefix(5)) : ""
        var bestIdx: Int? = nil
        var bestScore = 0
        for i in lo...hi {
            let line = lines[i].lowercased()
            if m.count >= 3 && line.contains(m) {
                let score = 3
                if score > bestScore { bestScore = score; bestIdx = i }
            } else if !prefix5.isEmpty && line.contains(prefix5) {
                let score = 2
                if score > bestScore { bestScore = score; bestIdx = i }
            } else if firstWord.count >= 3 && line.contains(firstWord) {
                let score = 1
                if score > bestScore { bestScore = score; bestIdx = i }
            }
        }
        return bestIdx
    }

    private static func findDateLine(_ date: String, in lines: [String], near anchor: Int) -> Int? {
        guard date.count >= 8 else { return nil }
        let datePrefix = String(date.prefix(10)) // "yyyy-MM-dd"
        let lo = max(0, anchor - 5)
        let hi = min(lines.count - 1, anchor + 5)
        for i in lo...hi {
            let line = lines[i]
            // Try the ISO date directly
            if line.contains(datePrefix) { return i }
            // Try without dashes (for formats like "08/02/2026")
            let parts = datePrefix.split(separator: "-")
            if parts.count == 3 {
                let d = parts[2], m = parts[1], y = parts[0]
                let variants = ["\(d)/\(m)/\(y)", "\(m)/\(d)/\(y)", "\(d).\(m).\(y)", "\(d)-\(m)-\(y)"]
                for v in variants {
                    if line.contains(v) { return i }
                }
            }
        }
        return nil
    }

    // MARK: - Merchant Rule Detection

    private static func merchantRule(for line: String, merchant: String, amountLine: String) -> MerchantRule {
        // Same line as amount and contains '|' → beforePipe
        if line == amountLine || line.lowercased().contains(merchant.lowercased()) {
            if line.contains("|") { return .beforePipe }
            if line.contains(":") {
                // Check if merchant appears after a colon
                if let colonRange = line.range(of: ":") {
                    let afterColon = line[colonRange.upperBound...].trimmingCharacters(in: .whitespaces)
                    if afterColon.lowercased().contains(merchant.lowercased()) { return .colonRight }
                }
            }
        }
        return .entireLine
    }

    // MARK: - Helpers

    private static func normalizeLines(_ lines: [String]) -> [String] {
        lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func amountSearchStrings(_ amount: Double) -> [String] {
        // OCR always shows positive numbers; expenses arrive as negative from GPT → search both signs
        let values: [Double] = amount < 0 ? [amount, -amount] : [amount]
        var variants: [String] = []
        for v in values {
            // "39.99", "39,99"
            let dot = String(format: "%.2f", v)
            let comma = dot.replacingOccurrences(of: ".", with: ",")
            if !variants.contains(dot) { variants.append(dot) }
            if !variants.contains(comma) { variants.append(comma) }
            // integer part only if no decimals
            if v == v.rounded(.towardZero) {
                let intStr = String(Int(v))
                if !variants.contains(intStr) { variants.append(intStr) }
            }
            // Strip trailing zeros: "39.90" → "39.9"
            let stripped = String(format: "%g", v)
            if !variants.contains(stripped) { variants.append(stripped) }
        }
        return variants
    }

    /// Returns the most common element if it appears at least `minCount` times.
    private static func majority<T: Hashable>(_ items: [T], minCount: Int) -> T? {
        var counts: [T: Int] = [:]
        for item in items { counts[item, default: 0] += 1 }
        guard let (value, count) = counts.max(by: { $0.value < $1.value }),
              count >= minCount else { return nil }
        return value
    }
}
