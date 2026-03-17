//
//  OCRBlockClassifier.swift
//  Airy
//
//  Classifies OCR lines into block types for row estimation. Rule-based by default; protocol allows GPT-based impl later.
//

import Foundation

enum BlockLabel: String {
    case transactionCandidate
    case dateHeader
    case cardInfo
    case statusLine
    case sectionDivider
    case noise
    case unknown
}

struct ClassifiedBlock {
    let text: String
    let label: BlockLabel
}

protocol BlockClassifier {
    func classify(lines: [String]) -> [ClassifiedBlock]
}

/// Rule-based classifier: maps lines to labels using regex/patterns. Transaction-like estimate = count of .transactionCandidate.
struct RuleBasedBlockClassifier: BlockClassifier {
    private static let currencySymbols = CharacterSet(charactersIn: "$€£¥₽₴")
    private static let currencyCodes = ["USD", "EUR", "GBP", "JPY", "CAD", "AUD", "CHF", "RUB", "UAH", "USDC", "THB"]

    /// Patterns that identify non-transaction lines (order matters: more specific first).
    private static let dateHeaderPatterns = [
        #"^\d{1,2}\s+(янв|февр|мар|апр|май|июн|июл|авг|сен|окт|нояб|дек)[а-я]*\.?\s*,?\s*\d{4}\s*$"#,
        #"^(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+\d{1,2},?\s*\d{4}\s*$"#,
        #"^\d{1,2}[-./]\d{1,2}[-./]\d{2,4}\s*$"#,
        #"^\d{4}[-./]\d{1,2}[-./]\d{1,2}\s*$"#,
        #"^(January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{4}\s*$"#
    ]
    private static let cardInfoPatterns = [
        #"^\*+\s*\d{4}\s*$"#,
        #"ending in \d{4}"#,
        #"^card\s+.*\d{4}\s*$"#,
        #"^\d{4}\s*$"#,  // last 4 digits only
        #"^account\s+.*\d{4}"#,
        #"card\s+\*"#,
        #"account\s+\*"#
    ]
    private static let statusLinePatterns = [
        #"^total$"#,
        #"^subtotal$"#,
        #"^tax$"#,
        #"^balance$"#,
        #"amount due"#,
        #"ref\s*#?\d+"#,
        #"id\s*#?\d+"#,
        #"order\s*#?\d+"#
    ]
    private static let sectionDividerPatterns = [
        #"^анал[іi]тика$"#,
        #"^історія$"#,
        #"^история$"#,
        #"^history$"#,
        #"^analytics$"#,
        #"^усі$"#,
        #"^всі$"#,
        #"^all$"#,
        #"^vci$"#,
        #"^transaction$"#,
        #"^transactions$"#
    ]
    private static let noisePatterns = [
        #"page \d+"#,
        #"^\d+$"#,           // pure number line
        #"\d{16,}"#,         // long digit string (card number)
        #"^.{0,2}$"#         // very short
    ]

    /// Amount-like: digit sequence with optional decimal and optional currency symbol/code.
    private static let amountPatternStr = #"[-+]?\s*\d{1,3}(?:[\s.,]\d{3})*(?:[.,]\d{2})|\d+[.,]\d{2}|\d+"#

    func classify(lines: [String]) -> [ClassifiedBlock] {
        lines.map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let label = Self.label(for: trimmed)
            return ClassifiedBlock(text: trimmed, label: label)
        }
    }

    private static func label(for line: String) -> BlockLabel {
        let lower = line.lowercased()
        if lower.isEmpty { return .noise }

        if matches(line: lower, patterns: noisePatterns) { return .noise }
        if matches(line: line, patterns: dateHeaderPatterns) { return .dateHeader }
        if matches(line: lower, patterns: cardInfoPatterns) { return .cardInfo }
        if matches(line: lower, patterns: statusLinePatterns) { return .statusLine }
        if matches(line: lower, patterns: sectionDividerPatterns) { return .sectionDivider }

        if hasAmountLikeContent(line) { return .transactionCandidate }
        return .unknown
    }

    private static func matches(line: String, patterns: [String]) -> Bool {
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                return true
            }
        }
        return false
    }

    private static func hasAmountLikeContent(_ line: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: amountPatternStr),
              regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil else { return false }
        return true
    }
}
