//
//  LocalOCRParser.swift
//  Airy
//
//  On-device transaction extraction from OCR text. No backend, no AI.
//

import Foundation

struct ParsedTransactionItem {
    var amount: Double
    var isCredit: Bool
    var currency: String
    var date: String
    var time: String?
    var merchant: String?
}

struct LocalParseResult {
    var accepted: Int
    var duplicateSkipped: Int
    var pendingReview: Int
    var pendingIds: [String]
    var errors: [String]
    var reason: String?
}

final class LocalOCRParser {
    private static let currencySymbols: [Character: String] = ["$": "USD", "€": "EUR", "£": "GBP", "¥": "JPY"]
    private static let currencyCodes = Set(["USD", "EUR", "GBP", "JPY", "CAD", "AUD", "CHF"])

    func parse(ocrText: String, baseCurrency: String = "USD") -> [ParsedTransactionItem] {
        let normalized = normalize(ocrText)
        let lines = normalized.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var results: [ParsedTransactionItem] = []
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10).description

        for i in lines.indices {
            let line = lines[i]
            guard let amountInfo = parseAmount(from: line) else { continue }
            let date = parseDate(from: line) ?? (i > 0 ? parseDate(from: lines[i - 1]) : nil) ?? today
            let time = parseTime(from: line)
            let merchant = extractMerchant(from: line)

            let lower = line.lowercased()
            let refundLike = lower.contains("refund") || lower.contains("credit") || lower.contains("reversal") || lower.contains("reimbursement")

            results.append(ParsedTransactionItem(
                amount: amountInfo.amount,
                isCredit: amountInfo.isCredit || refundLike,
                currency: amountInfo.currency,
                date: date,
                time: time,
                merchant: merchant
            ))
        }
        return results
    }

    private func normalize(_ raw: String) -> String {
        let lines = raw
            .precomposedStringWithCompatibilityMapping
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: "\n")
        return lines
            .map { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let collapsed = trimmed.split(separator: " ").joined(separator: " ")
                return collapsed
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func parseAmount(from line: String) -> (amount: Double, isCredit: Bool, currency: String)? {
        let pattern = #/([-+]?\s*\d{1,3}(?:[.,]\d{3})*(?:[.,]\d{2})?|\d+[.,]\d{2})\s*([A-Z]{3}|[$€£¥])?/#
        guard let match = line.firstMatch(of: pattern) else { return nil }
        let amountStr = String(match.1).replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: ".")
        guard let amountRaw = Double(amountStr) else { return nil }
        let amount = abs(amountRaw)
        let isCredit = amountRaw < 0
        var currency = "USD"
        if let sym = match.2 {
            let s = String(sym)
            if let c = s.first, let code = Self.currencySymbols[c] {
                currency = code
            } else if Self.currencyCodes.contains(s) {
                currency = s
            }
        }
        return (amount, isCredit, currency)
    }

    private func parseDate(from line: String) -> String? {
        let pattern = #/(\d{1,4})[-./](\d{1,2})[-./](\d{1,4})/#
        guard let match = line.firstMatch(of: pattern) else { return nil }
        let s1 = String(match.1)
        let s2 = String(match.2)
        let s3 = String(match.3)
        var y: Int, m: Int, d: Int
        if s1.count == 4 {
            guard let yy = Int(s1), let mm = Int(s2), let dd = Int(s3) else { return nil }
            y = yy; m = mm; d = dd
        } else {
            guard let dd = Int(s1), let mm = Int(s2), var yy = Int(s3) else { return nil }
            if yy < 100 { yy += 2000 }
            y = yy; m = mm; d = dd
        }
        guard y >= 1900, y <= 2100, m >= 1, m <= 12, d >= 1, d <= 31 else { return nil }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    private func parseTime(from line: String) -> String? {
        let pattern = #/(\d{1,2}):(\d{2})(?::(\d{2}))?/#
        guard let match = line.firstMatch(of: pattern) else { return nil }
        let h = Int(match.1) ?? 0
        let m = Int(match.2) ?? 0
        return String(format: "%02d:%02d", h, m)
    }

    private func extractMerchant(from line: String) -> String? {
        var cleaned = line
        for pattern in ["[-+]?\\s*\\d{1,3}(?:[.,]\\d{3})*(?:[.,]\\d{2})?|\\d+[.,]\\d{2}", "\\d{1,4}[-./]\\d{1,2}[-./]\\d{1,4}", "\\d{1,2}:\\d{2}"] {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(cleaned.startIndex..., in: cleaned)
                cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: "")
            }
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? nil : String(cleaned.prefix(256))
    }
}
