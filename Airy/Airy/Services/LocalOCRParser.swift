//
//  LocalOCRParser.swift
//  Airy
//
//  On-device transaction extraction from OCR text. No backend, no AI.
//

import Foundation

struct ParsedTransactionItem: Equatable, Codable {
    var amount: Double
    var isCredit: Bool
    var currency: String
    var date: String
    var time: String?
    var merchant: String?
    var categoryId: String?
    var subcategoryId: String?
    var isSubscription: Bool?
    /// Non-nil when this item was extracted locally using a saved OCR template.
    var extractedByTemplateId: String?
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
    private static let defaultCurrencySymbols: [Character: String] = ["$": "USD", "€": "EUR", "£": "GBP", "¥": "JPY", "₽": "RUB", "₴": "UAH", "฿": "THB"]
    private static let currencyCodes = Set(["USD", "EUR", "GBP", "JPY", "CAD", "AUD", "CHF", "RUB", "UAH", "USDC", "THB"])
    private static let minAmount = 0.01
    private static let maxAmount = 50_000.0
    private static let minWholeNumberAmount = 5.0
    private static let defaultJunkPatterns = [
        "page \\d+", "^total$", "^subtotal$", "^tax$", "^balance$", "amount due", "^\\d+$",
        "^\\*+\\s*\\d{4}\\s*$", "ending in \\d{4}", "^card\\s+.*\\d{4}\\s*$", "^\\d{4}\\s*$",
        "^account\\s+.*\\d{4}", "ref\\s*#?\\d+", "id\\s*#?\\d+", "order\\s*#?\\d+", "\\d{16,}",
        "^анал[іi]тика$", "^історія$", "^история$", "^history$", "^analytics$", "^усі$", "^всі$", "^all$", "^vci$", "^transaction$",
        "^\\d{1,2}\\s+(янв|февр|мар|апр|май|июн|июл|авг|сен|окт|нояб|дек)[а-я]*\\.?\\s*,?\\s*\\d{4}\\s*$"
    ]
    private static let defaultDatePattern = #"(\d{1,4})[-./](\d{1,2})[-./](\d{1,4})"#
    private static let russianMonthAbbrev: [String: Int] = [
        "янв": 1, "февр": 2, "мар": 3, "апр": 4, "май": 5, "июн": 6,
        "июл": 7, "авг": 8, "сен": 9, "окт": 10, "нояб": 11, "дек": 12
    ]
    private static let currencySymbolChars = "$€£¥₽₴"

    /// Parses OCR text with optional custom rules. For import, use ParsingRulesStore.tryMatch first.
    func parse(ocrText: String, baseCurrency: String = "USD") -> [ParsedTransactionItem] {
        parse(ocrText: ocrText, baseCurrency: baseCurrency, customRules: nil)
    }

    func parse(ocrText: String, baseCurrency: String, customRules: ParsingRules?) -> [ParsedTransactionItem] {
        let junkPatterns = Self.defaultJunkPatterns + (customRules?.extraJunkPatterns ?? [])
        var currencySymbols = Self.defaultCurrencySymbols
        for (k, v) in customRules?.currencySymbols ?? [:] {
            if let c = k.first { currencySymbols[c] = v }
        }
        var defaultCurrency = customRules?.defaultCurrency ?? baseCurrency
        if defaultCurrency == baseCurrency {
            let lower = ocrText.lowercased()
            if lower.contains("usdc") { defaultCurrency = "USDC" }
            else if lower.contains("thb") || lower.contains("฿") || lower.contains("бат") { defaultCurrency = "THB" }
            else if lower.contains("uah") || lower.contains("₴") || lower.contains("грн") { defaultCurrency = "UAH" }
            else if lower.contains("rub") || lower.contains("₽") || lower.contains("руб") { defaultCurrency = "RUB" }
        }
        let datePatterns = (customRules?.datePatterns ?? []) + [Self.defaultDatePattern]
        let hasRussianMonths = ocrText.lowercased().contains("мар") || ocrText.lowercased().contains("февр") || ocrText.lowercased().contains("янв")
        let currencyChars = Self.currencySymbolChars + (customRules?.currencySymbols?.keys.compactMap { $0.first }.map { String($0) }.joined() ?? "")

        let normalized = normalize(ocrText)
        let lines = normalized.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var results: [ParsedTransactionItem] = []
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10).description
        let isCryptoWallet = ocrText.uppercased().contains("USDC")

        for i in lines.indices {
            let line = lines[i]
            guard let amountInfo = parseAmountPreferred(from: line, currencySymbols: currencySymbols, defaultCurrency: defaultCurrency) else { continue }
            guard isReasonableAmount(amountInfo.amount) else { continue }
            guard !isJunkLine(line, patterns: junkPatterns) else { continue }

            var date = parseDate(from: line, patterns: datePatterns)
            if date == nil && hasRussianMonths {
                date = parseRussianDate(from: line) ?? parseRussianDate(from: lines[max(0, i - 1)])
            }
            if date == nil {
                for j in (max(0, i - 5)..<i).reversed() {
                    let d = parseDate(from: lines[j], patterns: datePatterns) ?? (hasRussianMonths ? parseRussianDate(from: lines[j]) : nil)
                    if let d = d {
                        date = d
                        break
                    }
                }
            }
            let dateResolved = date ?? today
            guard isReasonableDate(dateResolved) else { continue }

            let time = parseTime(from: line)
            var merchant = extractMerchant(from: line)
            if merchant == nil || (merchant?.lowercased() == "transaction") || (merchant?.count ?? 0) < 2 {
                for offset in [1, 2, 3] {
                    if i >= offset,
                       !lines[i - offset].isEmpty,
                       merchantContainsLetter(lines[i - offset]),
                       parseAmount(from: lines[i - offset], currencySymbols: currencySymbols, defaultCurrency: defaultCurrency) == nil,
                       !isJunkLine(lines[i - offset], patterns: junkPatterns) {
                        let candidate = stripCurrencyFromMerchant(lines[i - offset].trimmingCharacters(in: .whitespaces))
                        if candidate.count >= 2, !Self.currencyCodes.contains(candidate.uppercased()), candidate.lowercased() != "transaction" {
                            merchant = candidate
                            break
                        }
                    }
                }
                if (merchant == nil || (merchant?.lowercased() == "transaction") || (merchant?.count ?? 0) < 2) {
                    for offset in [1, 2, 3] {
                        if i + offset < lines.count,
                           !lines[i + offset].isEmpty,
                           merchantContainsLetter(lines[i + offset]),
                           parseAmount(from: lines[i + offset], currencySymbols: currencySymbols, defaultCurrency: defaultCurrency) == nil,
                           !isJunkLine(lines[i + offset], patterns: junkPatterns) {
                            let candidate = stripCurrencyFromMerchant(lines[i + offset].trimmingCharacters(in: .whitespaces))
                            if candidate.count >= 2, !Self.currencyCodes.contains(candidate.uppercased()), candidate.lowercased() != "transaction" {
                                merchant = candidate
                                break
                            }
                        }
                    }
                }
            }
            var merchantFinal = (merchant ?? "Transaction").trimmingCharacters(in: .whitespaces)
            merchantFinal = merchantFinal.replacingOccurrences(of: "*", with: " ").split(separator: " ").joined(separator: " ")
            let knownMerchants: [String: String] = ["clickup": "ClickUp", "amp ais services": "AIS Services", "ais services": "AIS Services"]
            if let known = knownMerchants[merchantFinal.lowercased()] { merchantFinal = known }
            else { merchantFinal = merchantFinal.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined(separator: " ") }
            guard merchantFinal.count >= 2 else { continue }
            guard merchantFinal.lowercased() != "transaction" else { continue }
            guard merchantContainsLetter(merchantFinal) else { continue }
            guard !Self.currencyCodes.contains(merchantFinal.uppercased()) else { continue }

            let lineUpper = line.uppercased()
            let hasCurrencyContext = line.contains(where: { currencyChars.contains($0) })
                || Self.currencyCodes.contains(where: { lineUpper.contains($0) })
            if !hasCurrencyContext && amountInfo.amount >= 1000 && amountInfo.amount < 10000 {
                continue
            }

            let lower = line.lowercased()
            let refundLike = lower.contains("refund") || lower.contains("credit") || lower.contains("reversal") || lower.contains("reimbursement")

            if isCryptoWallet && amountInfo.currency != "USDC" { continue }

            results.append(ParsedTransactionItem(
                amount: amountInfo.amount,
                isCredit: amountInfo.isCredit || refundLike,
                currency: amountInfo.currency,
                date: dateResolved,
                time: time,
                merchant: merchantFinal,
                categoryId: nil,
                subcategoryId: nil,
                isSubscription: nil
            ))
        }
        return deduplicateParsed(results)
    }

    private func deduplicateParsed(_ items: [ParsedTransactionItem]) -> [ParsedTransactionItem] {
        var seen = Set<String>()
        return items.filter { item in
            let key = "\(item.merchant?.lowercased() ?? "")|\(item.amount)|\(item.date)"
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private func isReasonableAmount(_ amount: Double) -> Bool {
        guard amount >= Self.minAmount && amount <= Self.maxAmount else { return false }
        if amount == amount.rounded() && amount < Self.minWholeNumberAmount { return false }
        return true
    }

    private func isReasonableDate(_ dateStr: String) -> Bool {
        guard let y = Int(dateStr.prefix(4)) else { return true }
        return y >= 2020 && y <= 2030
    }

    private func merchantContainsLetter(_ s: String) -> Bool {
        s.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }

    private func stripCurrencyFromMerchant(_ s: String) -> String {
        var t = s
        for code in Self.currencyCodes {
            let suffix = " " + code
            if t.uppercased().hasSuffix(suffix) {
                t = String(t.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return t
    }

    private func isJunkLine(_ line: String, patterns: [String]) -> Bool {
        let lower = line.lowercased().trimmingCharacters(in: .whitespaces)
        if lower.isEmpty { return true }
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) != nil {
                return true
            }
        }
        return false
    }

    private func normalizeAmountString(_ s: String) -> String {
        var t = s.replacingOccurrences(of: " ", with: "")
        if t.range(of: #",\d{2}$"#, options: .regularExpression) != nil {
            t = t.replacingOccurrences(of: ",", with: ".")
        } else {
            t = t.replacingOccurrences(of: ",", with: "")
        }
        return t
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

    /// When multiple amount+currency pairs exist: for crypto wallets, USDC is left (primary), USD/THB right (conversion) — prefer USDC.
    private func parseAmountPreferred(from line: String, currencySymbols: [Character: String], defaultCurrency: String) -> (amount: Double, isCredit: Bool, currency: String)? {
        var all = parseAllAmounts(from: line, currencySymbols: currencySymbols, defaultCurrency: defaultCurrency)
        guard !all.isEmpty else { return nil }
        if all.count == 1 { return all[0] }
        let maxAmt = all.map(\.amount).max() ?? 0
        if maxAmt >= 10 {
            all = all.filter { $0.amount >= 1 || $0.amount == maxAmt }
        }
        if all.contains(where: { $0.currency == "USDC" }) {
            if let usdc = all.first(where: { $0.currency == "USDC" }) { return usdc }
        }
        let preferredOrder = ["THB", "UAH", "RUB", "USD", "EUR"]
        for code in preferredOrder {
            if let found = all.first(where: { $0.currency == code }) { return found }
        }
        return all.first
    }

    private func parseAllAmounts(from line: String, currencySymbols: [Character: String], defaultCurrency: String) -> [(amount: Double, isCredit: Bool, currency: String)] {
        let pattern = #/([-+]?\s*(\d{1,3}(?:[\s.,]\d{3})*(?:[.,]\d{2})|\d+[.,]\d{2}|\d+))\s*([A-Z]{3,4}|[$€£¥₽₴])?/#
        var results: [(amount: Double, isCredit: Bool, currency: String)] = []
        var searchStart = line.startIndex
        while let match = line[searchStart...].firstMatch(of: pattern) {
            let amountStr = normalizeAmountString(String(match.1))
            if amountStr.count <= 2, amountStr.allSatisfy(\.isNumber),
               line[match.0.endIndex...].hasPrefix(":") { searchStart = match.0.endIndex; continue }
            if match.0.startIndex > line.startIndex {
                let idx = line.index(before: match.0.startIndex)
                if line[idx] == ":" { searchStart = match.0.endIndex; continue }
            }
            if let amountRaw = Double(amountStr) {
                let amount = abs(amountRaw)
                let isCredit = amountRaw > 0
                var currency = defaultCurrency
                if let sym = match.3 {
                    let s = String(sym)
                    if let c = s.first, let code = currencySymbols[c] {
                        currency = code
                    } else if Self.currencyCodes.contains(s) {
                        currency = s
                    }
                }
                results.append((amount, isCredit, currency))
            }
            searchStart = match.0.endIndex
        }
        return results
    }

    private func parseAmount(from line: String, currencySymbols: [Character: String], defaultCurrency: String) -> (amount: Double, isCredit: Bool, currency: String)? {
        parseAmountPreferred(from: line, currencySymbols: currencySymbols, defaultCurrency: defaultCurrency)
    }

    private func parseRussianDate(from line: String) -> String? {
        let pattern = #"(\d{1,2})\s+(янв|февр|мар|апр|май|июн|июл|авг|сен|окт|нояб|дек)[а-я]*\.?\s*,?\s*(\d{4})"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges >= 4 else { return nil }
        let dStr = (match.range(at: 1).location != NSNotFound) ? String(line[Range(match.range(at: 1), in: line)!]) : ""
        let mStr = (match.range(at: 2).location != NSNotFound) ? String(line[Range(match.range(at: 2), in: line)!]).lowercased().prefix(4).description : ""
        let yStr = (match.range(at: 3).location != NSNotFound) ? String(line[Range(match.range(at: 3), in: line)!]) : ""
        guard let d = Int(dStr), let y = Int(yStr), let m = Self.russianMonthAbbrev[mStr] else { return nil }
        guard y >= 1900, y <= 2100, d >= 1, d <= 31 else { return nil }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    private func parseDate(from line: String, patterns: [String]) -> String? {
        for patternStr in patterns {
            guard let regex = try? NSRegularExpression(pattern: patternStr),
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  match.numberOfRanges >= 4 else { continue }
            let s1 = (match.range(at: 1).location != NSNotFound) ? String(line[Range(match.range(at: 1), in: line)!]) : ""
            let s2 = (match.range(at: 2).location != NSNotFound) ? String(line[Range(match.range(at: 2), in: line)!]) : ""
            let s3 = (match.range(at: 3).location != NSNotFound) ? String(line[Range(match.range(at: 3), in: line)!]) : ""
            guard !s1.isEmpty, !s2.isEmpty, !s3.isEmpty else { continue }
            var y: Int, m: Int, d: Int
            if s1.count == 4 {
                guard let yy = Int(s1), let mm = Int(s2), let dd = Int(s3) else { continue }
                y = yy; m = mm; d = dd
            } else {
                guard let dd = Int(s1), let mm = Int(s2), var yy = Int(s3) else { continue }
                if yy < 100 { yy += 2000 }
                y = yy; m = mm; d = dd
            }
            guard y >= 1900, y <= 2100, m >= 1, m <= 12, d >= 1, d <= 31 else { continue }
            return String(format: "%04d-%02d-%02d", y, m, d)
        }
        return nil
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
        for pattern in ["[-+]?\\s*\\d{1,3}(?:[\\s.,]\\d{3})*(?:[.,]\\d{2})|\\d+[.,]\\d{2}|\\d+(?=\\s+(?:USDC|USD|THB|UAH|RUB|EUR|GBP))", "\\d{1,4}[-./]\\d{1,2}[-./]\\d{1,4}", "\\d{1,2}:\\d{2}"] {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(cleaned.startIndex..., in: cleaned)
                cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: "")
            }
        }
        for code in Self.currencyCodes {
            let suffix = " " + code
            if cleaned.uppercased().hasSuffix(suffix) {
                cleaned = String(cleaned.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? nil : String(cleaned.prefix(256))
    }
}
