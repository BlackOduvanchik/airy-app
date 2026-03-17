//
//  LocalRowExtractor.swift
//  Airy
//
//  Extracts transaction candidates from grouped OCR row candidates. Each row is classified before becoming a transaction; conservative merchant and status rules apply.
//

import Foundation

/// Result of local extraction from grouped rows: items plus coverage counts for confidence gating.
struct LocalRowExtractionResult {
    var items: [ParsedTransactionItem]
    var validAmountCount: Int
    var validMerchantCount: Int
    var validDateCount: Int
    var excludedByStatusCount: Int
}

/// Extracts transactions from candidate row groups. Rows are classified per-row; status rows (failed/pending/reversed/cancelled) are excluded.
enum LocalRowExtractor {
    private static let amountPatternStr = #"[-+]?\s*\d{1,3}(?:[\s.,]\d{3})*(?:[.,]\d{2})|\d+[.,]\d{2}|\d+"#
    private static let datePatterns: [(pattern: String, order: (Int, Int, Int))] = [
        (#"(\d{4})[-./](\d{1,2})[-./](\d{1,2})"#, (0, 1, 2)),  // y, m, d
        (#"(\d{1,2})[-./](\d{1,2})[-./](\d{2,4})"#, (2, 1, 0)), // d, m, y (y may be 2-digit)
    ]
    private static let datePatternsForStrip = [
        #"\d{4}[-./]\d{1,2}[-./]\d{1,2}"#,
        #"\d{1,2}[-./]\d{1,2}[-./]\d{2,4}"#,
    ]
    private static let currencyCodes = Set(["USD", "EUR", "GBP", "JPY", "CAD", "AUD", "CHF", "RUB", "UAH", "USDC", "THB"])
    private static let currencySymbols: [Character: String] = ["$": "USD", "€": "EUR", "£": "GBP", "¥": "JPY", "₽": "RUB", "₴": "UAH", "฿": "THB"]
    private static let minAmount = 0.01
    private static let maxAmount = 50_000.0

    /// Words that indicate non-success status; rows containing these (as whole word or dominant) are excluded.
    private static let statusExcludeKeywords: Set<String> = ["failed", "failure", "pending", "reversed", "reversal", "cancelled", "canceled", "declined", "refund"]

    /// Merchant/title exclusions: masked card, generic status, balance, generic purchase/payment.
    private static let merchantExcludePatterns = [
        #"\*+\s*\d{4}\s*$"#,
        #"ending in \d{4}"#,
        #"card\s+.*\d{4}"#,
        #"^\d{4}\s*$"#,
        #"balance"#,
        #"available"#,
        #"^total$"#,
        #"^subtotal$"#,
        #"^purchase$"#,
        #"^payment$"#,
        #"^transaction$"#,
        #"^оплата$"#,
        #"^покупка$"#,
    ]
    private static let genericMerchantLike: Set<String> = ["purchase", "payment", "transaction", "оплата", "покупка", "sale", "withdrawal", "payout", "transfer", "expense"]

    static func extract(
        groupedRows: [[String]],
        family: LayoutFamily?,
        archetype: RowArchetype? = nil,
        baseCurrency: String,
        dateFromContext: String?
    ) -> LocalRowExtractionResult {
        // Archetype-guided amount anchor: more precise than family-level bucket
        let archetypeAnchor: String? = archetype.flatMap { a -> String? in
            guard a.confidence >= 0.75 else { return nil }
            switch a.amountPosition {
            case .suffix: return "right"
            case .prefix: return "left"
            case .inline: return "inline"
            case .unknown: return nil
            }
        }
        let anchor = archetypeAnchor ?? family?.amountAnchorDominant ?? family?.amountAnchorBucket ?? "unknown"

        let today = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        var items: [ParsedTransactionItem] = []
        var validAmountCount = 0
        var validMerchantCount = 0
        var validDateCount = 0
        var excludedByStatusCount = 0

        for rowLines in groupedRows {
            // Archetype-guided row pre-filter: skip row groups whose line count is outside
            // the learned range — but only when confidence is high (≥ 0.75) to avoid
            // accidentally discarding valid rows for edge-case layouts.
            if let a = archetype, a.confidence >= 0.75 {
                let lineCount = rowLines.count
                // Allow +1 tolerance around the observed range
                if lineCount < max(1, a.minLineCount - 1) || lineCount > a.maxLineCount + 1 {
                    excludedByStatusCount += 1
                    continue
                }
            }
            guard !rowLines.isEmpty else { continue }
            let rowText = rowLines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            guard !rowText.isEmpty else { continue }

            if hasExcludedStatus(rowText) {
                excludedByStatusCount += 1
                continue
            }

            guard let amountInfo = parseAmount(from: rowText, anchor: anchor, defaultCurrency: baseCurrency),
                  isReasonableAmount(amountInfo.amount) else { continue }
            validAmountCount += 1

            let date = parseDate(from: rowText) ?? dateFromContext ?? today
            if isReasonableDate(date) { validDateCount += 1 }

            guard let merchant = extractConservativeMerchant(from: rowText, amountInfo: amountInfo) else { continue }
            validMerchantCount += 1

            let time = parseTime(from: rowText)
            let isCredit = amountInfo.isCredit || rowText.lowercased().contains("refund") || rowText.lowercased().contains("credit")
            items.append(ParsedTransactionItem(
                amount: amountInfo.amount,
                isCredit: isCredit,
                currency: amountInfo.currency,
                date: date,
                time: time,
                merchant: merchant,
                categoryId: nil,
                subcategoryId: nil,
                isSubscription: nil
            ))
        }

        return LocalRowExtractionResult(
            items: items,
            validAmountCount: validAmountCount,
            validMerchantCount: validMerchantCount,
            validDateCount: validDateCount,
            excludedByStatusCount: excludedByStatusCount
        )
    }

    private static func hasExcludedStatus(_ text: String) -> Bool {
        let lower = text.lowercased()
        let words = lower.split(separator: " ").map { String($0).trimmingCharacters(in: .punctuationCharacters) }
        for w in words {
            if statusExcludeKeywords.contains(w) { return true }
        }
        if lower.contains("failed") || lower.contains("pending") || lower.contains("reversed") || lower.contains("cancelled") || lower.contains("canceled") {
            return true
        }
        return false
    }

    private static func parseAmount(from line: String, anchor: String, defaultCurrency: String) -> (amount: Double, isCredit: Bool, currency: String)? {
        guard let regex = try? NSRegularExpression(pattern: amountPatternStr) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        let matches = regex.matches(in: line, range: range)
        guard !matches.isEmpty else { return nil }
        var results: [(amount: Double, isCredit: Bool, currency: String)] = []
        for m in matches {
            guard m.numberOfRanges > 0, let r = Range(m.range(at: 0), in: line) else { continue }
            let s = String(line[r]).replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: ".")
            if s.contains(".") == false, s.count <= 2 {
                let afterStart = line.index(r.upperBound, offsetBy: 0, limitedBy: line.endIndex)
                if afterStart != nil && afterStart! < line.endIndex && line[afterStart!] == ":" { continue }
            }
            guard let val = Double(s) else { continue }
            let amount = abs(val)
            let isCredit = val > 0
            var currency = defaultCurrency
            let after = line[r.upperBound...].trimmingCharacters(in: .whitespaces)
            for (ch, code) in currencySymbols {
                if after.hasPrefix(String(ch)) { currency = code; break }
            }
            for code in currencyCodes {
                if after.uppercased().hasPrefix(code) { currency = code; break }
            }
            results.append((amount, isCredit, currency))
        }
        guard !results.isEmpty else { return nil }
        if results.count == 1 { return results[0] }
        switch anchor {
        case "right": return results.last
        case "left": return results.first
        default: return results.first
        }
    }

    private static func isReasonableAmount(_ amount: Double) -> Bool {
        amount >= minAmount && amount <= maxAmount
    }

    private static func parseDate(from line: String) -> String? {
        for entry in datePatterns {
            guard let regex = try? NSRegularExpression(pattern: entry.pattern),
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  match.numberOfRanges >= 3 else { continue }
            let s1 = (match.range(at: 1).location != NSNotFound) ? String(line[Range(match.range(at: 1), in: line)!]) : ""
            let s2 = (match.range(at: 2).location != NSNotFound) ? String(line[Range(match.range(at: 2), in: line)!]) : ""
            let s3 = (match.range(at: 3).location != NSNotFound) ? String(line[Range(match.range(at: 3), in: line)!]) : ""
            guard !s1.isEmpty, !s2.isEmpty, !s3.isEmpty else { continue }
            let (yi, mi, di) = entry.order
            let parts = [s1, s2, s3]
            let yStr = parts[yi]
            let mStr = parts[mi]
            let dStr = parts[di]
            var y: Int, m: Int, d: Int
            if yStr.count == 4 {
                guard let yy = Int(yStr), let mm = Int(mStr), let dd = Int(dStr) else { continue }
                y = yy; m = mm; d = dd
            } else {
                guard let dd = Int(dStr), let mm = Int(mStr), var yy = Int(yStr) else { continue }
                if yy < 100 { yy += 2000 }
                y = yy; m = mm; d = dd
            }
            guard y >= 2020, y <= 2030, m >= 1, m <= 12, d >= 1, d <= 31 else { continue }
            return String(format: "%04d-%02d-%02d", y, m, d)
        }
        return nil
    }

    private static func isReasonableDate(_ dateStr: String) -> Bool {
        guard let y = Int(dateStr.prefix(4)) else { return true }
        return y >= 2020 && y <= 2030
    }

    private static func parseTime(from line: String) -> String? {
        let pattern = #"(\d{1,2}):(\d{2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges >= 3 else { return nil }
        let h = Int(line[Range(match.range(at: 1), in: line)!]) ?? 0
        let m = Int(line[Range(match.range(at: 2), in: line)!]) ?? 0
        return String(format: "%02d:%02d", h, m)
    }

    /// Conservative merchant: strip amount/date, exclude masked card, balance, generic words; require title-like (letters, min length).
    private static func extractConservativeMerchant(from line: String, amountInfo: (amount: Double, isCredit: Bool, currency: String)) -> String? {
        var cleaned = line
        if let amountRegex = try? NSRegularExpression(pattern: amountPatternStr) {
            let r = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = amountRegex.stringByReplacingMatches(in: cleaned, range: r, withTemplate: "")
        }
        for patternStr in datePatternsForStrip {
            if let regex = try? NSRegularExpression(pattern: patternStr) {
                let r = NSRange(cleaned.startIndex..., in: cleaned)
                cleaned = regex.stringByReplacingMatches(in: cleaned, range: r, withTemplate: "")
            }
        }
        for code in currencyCodes {
            let suffix = " " + code
            if cleaned.uppercased().hasSuffix(suffix) {
                cleaned = String(cleaned.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        if cleaned.isEmpty { return nil }
        let lower = cleaned.lowercased()
        for patternStr in merchantExcludePatterns {
            if let regex = try? NSRegularExpression(pattern: patternStr, options: .caseInsensitive),
               regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) != nil {
                return nil
            }
        }
        let singleWord = lower.split(separator: " ").map { String($0) }
        if singleWord.count == 1, genericMerchantLike.contains(singleWord[0]) { return nil }
        guard cleaned.count >= 2 else { return nil }
        guard cleaned.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) else { return nil }
        guard !currencyCodes.contains(cleaned.uppercased()) else { return nil }
        return String(cleaned.prefix(256))
    }
}
