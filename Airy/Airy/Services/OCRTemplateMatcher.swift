//
//  OCRTemplateMatcher.swift
//  Airy
//
//  Matches incoming OCR lines against stored templates and extracts transactions locally.
//  Returns a result only when confidence ≥ 0.95.
//

import Foundation

struct TemplateMatchResult {
    let templateId: String
    let confidence: Double
    let items: [ParsedTransactionItem]
}

struct OCRTemplateMatcher {

    // MARK: - Public

    /// Try every stored template and return the best match if confidence ≥ 0.95, else nil.
    static func bestMatch(
        ocrLines: [String],
        store: OCRTemplateStore,
        baseCurrency: String
    ) -> TemplateMatchResult? {
        bestMatchWithDiagnostics(ocrLines: ocrLines, store: store, baseCurrency: baseCurrency).result
    }

    /// Same as bestMatch but also returns the best-attempted confidence even when < 0.95 (for diagnostics).
    static func bestMatchWithDiagnostics(
        ocrLines: [String],
        store: OCRTemplateStore,
        baseCurrency: String
    ) -> (result: TemplateMatchResult?, bestConfidence: Double, storeCount: Int) {
        let lines = normalizeLines(ocrLines)
        let templates = store.all()
        guard lines.count >= 2, !templates.isEmpty else {
            return (nil, 0.0, templates.count)
        }

        var bestResult: TemplateMatchResult? = nil
        var bestConfidence: Double = 0.0

        for template in templates {
            guard let candidate = tryTemplate(template, lines: lines, baseCurrency: baseCurrency) else { continue }
            if candidate.confidence > bestConfidence {
                bestConfidence = candidate.confidence
            }
            if candidate.confidence >= 0.95, candidate.items.count >= 3,
               (bestResult?.confidence ?? 0) < candidate.confidence {
                bestResult = candidate
            }
        }
        return (bestResult, bestConfidence, templates.count)
    }

    // MARK: - Verification

    /// Returns true if the template correctly extracts ≥40% of expectedMerchants from the given normalized OCR text.
    /// Used to validate a GPT-derived template before saving it to the store.
    static func verify(
        template: OCRTemplate,
        normalizedOcrText: String,
        baseCurrency: String,
        expectedMerchants: Set<String>
    ) -> Bool {
        guard !expectedMerchants.isEmpty else { return false }
        let lines = normalizeLines(normalizedOcrText.components(separatedBy: .newlines))
        guard let result = tryTemplate(template, lines: lines, baseCurrency: baseCurrency) else { return false }
        let extracted = Set(result.items.compactMap { $0.merchant?.lowercased() })
        let overlap = expectedMerchants.intersection(extracted)
        return Double(overlap.count) / Double(expectedMerchants.count) >= 0.4
    }

    // MARK: - Template Attempt

    static func tryTemplate(
        _ template: OCRTemplate,
        lines: [String],
        baseCurrency: String
    ) -> TemplateMatchResult? {
        // Find all lines that look like an amount anchor
        let anchorIndices = findAmountAnchorLines(in: lines)
        guard !anchorIndices.isEmpty else { return nil }

        var items: [ParsedTransactionItem] = []
        var attempted = 0

        for anchorIdx in anchorIndices {
            attempted += 1
            guard let item = extractItem(
                template: template,
                lines: lines,
                anchorIdx: anchorIdx,
                baseCurrency: baseCurrency
            ) else { continue }
            items.append(item)
        }

        guard attempted > 0 else { return nil }

        // Reject results with low-quality merchants (account numbers, generic labels)
        let qualityItems = items.filter { isMerchantQuality($0.merchant) }
        guard qualityItems.count >= 3 else { return nil }
        // Confidence based on quality items only — prevents partial matches from looking confident.
        let confidence = Double(qualityItems.count) / Double(attempted)

        return TemplateMatchResult(
            templateId: template.id,
            confidence: confidence,
            items: deduplicateItems(qualityItems)
        )
    }

    /// Returns false for masked account numbers ("****1085"), pure-digit strings ("44"),
    /// generic labels ("Other", "покупка", etc.), or names shorter than 3 chars.
    private static let genericMerchantLabels: Set<String> = [
        "other", "transaction", "покупка", "purchase", "payment", "оплата",
        "withdrawal", "payout", "transfer", "sale", "expense",
        // Context words that appear in OCR descriptions but are not merchants
        "with", "from", "to", "by", "via", "at", "card", "debit", "credit",
        "ref", "note", "memo", "desc", "description"
    ]

    private static func isMerchantQuality(_ merchant: String?) -> Bool {
        guard let m = merchant, m.count >= 3 else { return false }
        if m.contains("*") { return false }
        let lower = m.lowercased()
        if genericMerchantLabels.contains(lower) { return false }
        if m.allSatisfy({ $0.isNumber || $0 == " " }) { return false }
        return true
    }

    // MARK: - Item Extraction

    private static func extractItem(
        template: OCRTemplate,
        lines: [String],
        anchorIdx: Int,
        baseCurrency: String
    ) -> ParsedTransactionItem? {
        let anchorLine = lines[anchorIdx]

        // --- Amount ---
        guard let (amount, isCredit, currency) = parseAmount(from: anchorLine, baseCurrency: baseCurrency) else {
            return nil
        }

        // --- Merchant ---
        let merchantLineIdx = anchorIdx + template.merchantLineOffset
        let merchantLine: String
        if merchantLineIdx >= 0 && merchantLineIdx < lines.count {
            merchantLine = lines[merchantLineIdx]
        } else {
            merchantLine = anchorLine
        }
        let merchant = extractMerchant(from: merchantLine, rule: template.merchantExtractionRule, anchorLine: anchorLine) ?? "Transaction"
        guard merchant.count >= 2, merchant.lowercased() != "transaction" else { return nil }

        // --- Date ---
        let dateLine: String
        let dateLineIdx = anchorIdx + template.dateLineOffset
        if dateLineIdx >= 0 && dateLineIdx < lines.count {
            dateLine = lines[dateLineIdx]
        } else {
            dateLine = anchorLine
        }
        let date = parseDate(from: dateLine) ?? parseDate(from: anchorLine) ?? todayISO()

        // --- Time (optional) ---
        let time = parseTime(from: anchorLine) ?? parseTime(from: dateLine)

        return ParsedTransactionItem(
            amount: amount,
            isCredit: isCredit,
            currency: currency,
            date: date,
            time: time,
            merchant: capitalized(merchant),
            categoryId: nil,
            subcategoryId: nil,
            isSubscription: nil,
            extractedByTemplateId: nil  // caller sets this
        )
    }

    // MARK: - Amount Anchor Detection

    private static let amountRegex: NSRegularExpression? = {
        let pattern = #"[-+]?\s*\d{1,3}(?:[\s,]\d{3})*[.,]\d{2}\s*(?:[A-Z]{2,4}|[$€£¥₽₴])?|\d+[.,]\d{2}\s*(?:[A-Z]{2,4}|[$€£¥₽₴])?"#
        return try? NSRegularExpression(pattern: pattern, options: [])
    }()

    private static func findAmountAnchorLines(in lines: [String]) -> [Int] {
        guard let regex = amountRegex else { return [] }
        var result: [Int] = []
        for (i, line) in lines.enumerated() {
            let nsRange = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, range: nsRange) else { continue }
            guard let swiftRange = Range(match.range, in: line) else { continue }
            let matchedStr = String(line[swiftRange])
            // Filter out pure 4-digit numbers (card digits, years, etc.)
            if matchedStr.trimmingCharacters(in: .whitespacesAndNewlines).count <= 4 { continue }
            // Filter out date components: if the char immediately after the match is "." / "/" / "-"
            // followed by a digit, this match is part of a date like "26.02.2026" → skip
            let afterMatch = line[swiftRange.upperBound...]
            if let first = afterMatch.first,
               (first == "." || first == "/" || first == "-"),
               afterMatch.dropFirst().first?.isNumber == true {
                continue
            }
            // Filter out tiny amounts (< 0.50) that are likely OCR artifacts
            if let parsed = parseAmount(from: line, baseCurrency: "USD"), parsed.amount < 0.50 { continue }
            result.append(i)
        }
        return result
    }

    // MARK: - Parsing Helpers

    private static let currencySymbols: [Character: String] = [
        "$": "USD", "€": "EUR", "£": "GBP", "¥": "JPY", "₽": "RUB", "₴": "UAH", "฿": "THB"
    ]
    private static let currencyCodes = ["USD", "EUR", "GBP", "JPY", "CAD", "AUD", "CHF", "RUB", "UAH", "USDC", "THB"]

    private static func parseAmount(
        from line: String,
        baseCurrency: String
    ) -> (amount: Double, isCredit: Bool, currency: String)? {
        guard let regex = amountRegex else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              let swiftRange = Range(match.range, in: line) else { return nil }

        let raw = String(line[swiftRange])
        let normalized = normalizeAmountString(raw)

        // Detect sign (explicit "+" = income; "-" or no sign = expense)
        let isCredit = line.hasPrefix("+") || raw.hasPrefix("+")

        // Extract numeric value — OCR may show negative sign for debits, use abs
        let numStr = normalized.components(separatedBy: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz$€£¥₽₴")).joined()
            .trimmingCharacters(in: .whitespaces)
        guard let amountRaw = Double(numStr), amountRaw != 0 else { return nil }
        let amount = abs(amountRaw)
        guard amount >= 0.01 && amount <= 50_000 else { return nil }

        // Detect currency
        var currency = baseCurrency
        for code in currencyCodes {
            if raw.uppercased().contains(code) { currency = code; break }
        }
        if currency == baseCurrency {
            for (sym, code) in currencySymbols {
                if raw.contains(sym) || line.contains(sym) { currency = code; break }
            }
        }

        return (amount, isCredit, currency)
    }

    private static func normalizeAmountString(_ s: String) -> String {
        var t = s.replacingOccurrences(of: " ", with: "")
        if t.range(of: #",\d{2}([A-Za-z]|$)"#, options: .regularExpression) != nil {
            t = t.replacingOccurrences(of: ",", with: ".")
        } else {
            t = t.replacingOccurrences(of: ",", with: "")
        }
        return t
    }

    private static func extractMerchant(from line: String, rule: MerchantRule, anchorLine: String) -> String? {
        switch rule {
        case .beforePipe:
            if let pipeRange = line.range(of: "|") {
                let part = String(line[..<pipeRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                return part.isEmpty ? nil : part
            }
            return cleanMerchant(line)
        case .colonRight:
            if let colonRange = line.range(of: ":") {
                let part = String(line[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                return part.isEmpty ? nil : part
            }
            return cleanMerchant(line)
        case .entireLine:
            return cleanMerchant(line)
        }
    }

    private static func cleanMerchant(_ line: String) -> String? {
        var t = line
        // Remove amounts
        if let regex = amountRegex {
            let range = NSRange(t.startIndex..., in: t)
            t = regex.stringByReplacingMatches(in: t, range: range, withTemplate: "")
        }
        // Remove date patterns
        let datePatterns = [
            #"\d{4}[-./]\d{2}[-./]\d{2}"#,
            #"\d{2}[-./]\d{2}[-./]\d{4}"#,
            #"\d{2}:\d{2}(:\d{2})?"#
        ]
        for pattern in datePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(t.startIndex..., in: t)
                t = regex.stringByReplacingMatches(in: t, range: range, withTemplate: "")
            }
        }
        t = t.trimmingCharacters(in: .init(charactersIn: "|: "))
            .trimmingCharacters(in: .whitespaces)
        return t.count >= 2 ? t : nil
    }

    private static func parseDate(from line: String) -> String? {
        let patterns: [(pattern: String, format: (String, String, String) -> String)] = [
            (#"(\d{4})[-./ ](\d{1,2})[-./ ](\d{1,2})"#, { y, m, d in "\(y)-\(pad(m))-\(pad(d))" }),
            (#"(\d{1,2})[-./ ](\d{1,2})[-./ ](\d{4})"#, { d, m, y in "\(y)-\(pad(m))-\(pad(d))" })
        ]
        for (pattern, format) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  match.numberOfRanges >= 4,
                  let r1 = Range(match.range(at: 1), in: line),
                  let r2 = Range(match.range(at: 2), in: line),
                  let r3 = Range(match.range(at: 3), in: line)
            else { continue }
            let s1 = String(line[r1])
            let s2 = String(line[r2])
            let s3 = String(line[r3])
            let result = format(s1, s2, s3)
            if let y = Int(result.prefix(4)), y >= 2020, y <= 2030 { return result }
        }
        return nil
    }

    private static func parseTime(from line: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d{1,2}):(\d{2})"#),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let r1 = Range(match.range(at: 1), in: line),
              let r2 = Range(match.range(at: 2), in: line)
        else { return nil }
        let h = Int(line[r1]) ?? 0
        let m = Int(line[r2]) ?? 0
        guard h <= 23, m <= 59 else { return nil }
        return String(format: "%02d:%02d", h, m)
    }

    private static func normalizeLines(_ lines: [String]) -> [String] {
        lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func todayISO() -> String {
        String(ISO8601DateFormatter().string(from: Date()).prefix(10))
    }

    private static func pad(_ s: String) -> String {
        s.count == 1 ? "0\(s)" : s
    }

    private static func capitalized(_ s: String) -> String {
        s.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined(separator: " ")
    }

    private static func deduplicateItems(_ items: [ParsedTransactionItem]) -> [ParsedTransactionItem] {
        var seen = Set<String>()
        return items.filter { item in
            let key = "\(item.merchant?.lowercased() ?? "")|\(item.amount)|\(item.date)"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }
}
