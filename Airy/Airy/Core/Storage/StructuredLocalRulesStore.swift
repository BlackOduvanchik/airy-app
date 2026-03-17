//
//  StructuredLocalRulesStore.swift
//  Airy
//
//  Versioned structured rules only. No raw GPT regex; hints (keywords, date formats) only.
//

import Foundation

/// Structured rule: keywords, date hints, single optional amount pattern. No freeform regex arrays.
struct StructuredLocalRule: Codable, Equatable {
    let id: String
    var version: Int
    var screenTypeHint: String?
    var dateFormatHints: [String]
    var currencyHints: [String]
    var ignoreKeywords: [String]
    var failureKeywords: [String]
    var amountPattern: String?
}

final class StructuredLocalRulesStore {
    static let shared = StructuredLocalRulesStore()
    private let key = "structuredLocalRules"
    private let maxRules = 50
    private var rules: [StructuredLocalRule] = []
    private let queue = DispatchQueue(label: "structuredLocalRulesStore")

    private init() {
        loadFromUserDefaults()
    }

    func allRules() -> [StructuredLocalRule] {
        queue.sync { rules }
    }

    func append(_ rule: StructuredLocalRule) {
        queue.sync {
            var r = rule
            if rules.contains(where: { $0.id == r.id }) {
                r.version = (rules.first { $0.id == r.id }?.version ?? 0) + 1
            }
            rules.removeAll { $0.id == r.id }
            rules.append(r)
            if rules.count > maxRules {
                rules.removeFirst(rules.count - maxRules)
            }
            persist()
        }
    }

    func clearAll() {
        queue.sync {
            rules.removeAll()
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func loadFromUserDefaults() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([StructuredLocalRule].self, from: data) else { return }
        rules = decoded
    }
}

// MARK: - Convert to ParsingRules for LocalOCRParser

extension StructuredLocalRule {
    /// Converts structured rule to ParsingRules so LocalOCRParser can use it (keywords → junk patterns, date hints → regex).
    func toParsingRules(baseCurrency: String) -> ParsingRules {
        let junkFromIgnore = ignoreKeywords.map { kw in
            let escaped = NSRegularExpression.escapedPattern(for: kw)
            return "(?i).*\(escaped).*"
        }
        let junkFromFailure = failureKeywords.map { kw in
            let escaped = NSRegularExpression.escapedPattern(for: kw)
            return "(?i).*\(escaped).*"
        }
        let extraJunk = junkFromIgnore + junkFromFailure
        let datePatterns = dateFormatHints.flatMap { hint -> [String] in
            switch hint.lowercased().replacingOccurrences(of: " ", with: "") {
            case "yyyy-mm-dd", "yyyy-m-d":
                return [#"(\d{4})[-./](\d{1,2})[-./](\d{1,2})"#]
            case "dd.mm.yy", "dd.mm.yyyy":
                return [#"(\d{1,2})[-./](\d{1,2})[-./](\d{1,4})"#]
            case "mm/dd/yyyy", "m/d/yyyy":
                return [#"(\d{1,2})[-/](\d{1,2})[-/](\d{4})"#]
            default:
                return []
            }
        }
        let defaultCur = currencyHints.first.flatMap { $0.isEmpty ? nil : $0 } ?? baseCurrency
        return ParsingRules(
            extraJunkPatterns: extraJunk.isEmpty ? nil : extraJunk,
            datePatterns: datePatterns.isEmpty ? nil : datePatterns,
            currencySymbols: nil,
            defaultCurrency: defaultCur,
            amountPattern: amountPattern
        )
    }
}
