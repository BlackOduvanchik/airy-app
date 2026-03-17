//
//  GPTRulesService.swift
//  Airy
//
//  Sends OCR text to OpenAI, receives parsing rules. Rules are saved locally for future use.
//

import Foundation


enum GPTRulesError: LocalizedError {
    case noApiKey
    case invalidResponse(String)
    case network(Error)
    case apiError(statusCode: Int, message: String)
    case quotaExceeded
    case rateLimited  // HTTP 429: too many requests (not billing quota)

    var errorDescription: String? {
        switch self {
        case .noApiKey: return "Add and save your OpenAI API key first."
        case .invalidResponse(let detail): return "Invalid response: \(detail)"
        case .network(let err):
            if let urlErr = err as? URLError, urlErr.code == .cancelled {
                return "Request cancelled. Please try again."
            }
            if (err as NSError).code == NSURLErrorCancelled {
                return "Request cancelled. Please try again."
            }
            return "Network: \(err.localizedDescription)"
        case .apiError(_, let msg): return msg
        case .quotaExceeded: return "Image processing is not available at the moment."
        case .rateLimited: return "Rate limit reached. Slowing down..."
        }
    }
}

/// One transaction extracted by GPT from OCR. Maps to ParsedTransactionItem.
struct GPTExtractionTransaction: Codable {
    let date: String
    let merchant: String?
    let amount: Double
    let currency: String?
    let isCredit: Bool?
    let isSubscription: Bool?
    let categoryId: String?
    let subcategoryId: String?
    let time: String?
    /// When present: success | failed | pending | reversed. Non-success are skipped from main pending.
    let transactionStatus: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
        date = (try? c.decode(String.self, forKey: .date)).flatMap { $0.isEmpty ? nil : $0 } ?? String(today)
        merchant = try c.decodeIfPresent(String.self, forKey: .merchant)
        if let d = try? c.decode(Double.self, forKey: .amount) {
            amount = d
        } else if let s = try? c.decode(String.self, forKey: .amount), let d = Double(s.replacingOccurrences(of: ",", with: ".")) {
            amount = d
        } else {
            throw DecodingError.typeMismatch(Double.self, DecodingError.Context(codingPath: c.codingPath + [CodingKeys.amount], debugDescription: "amount must be number or numeric string"))
        }
        currency = try c.decodeIfPresent(String.self, forKey: .currency)
        isCredit = try c.decodeIfPresent(Bool.self, forKey: .isCredit)
        isSubscription = try c.decodeIfPresent(Bool.self, forKey: .isSubscription)
        categoryId = try c.decodeIfPresent(String.self, forKey: .categoryId)
        subcategoryId = try c.decodeIfPresent(String.self, forKey: .subcategoryId)
        time = try c.decodeIfPresent(String.self, forKey: .time)
        transactionStatus = try c.decodeIfPresent(String.self, forKey: .transactionStatus)
    }

    /// True if this transaction should be included in the main pending list (success only).
    var isSuccessStatus: Bool {
        let s = (transactionStatus ?? "success").lowercased()
        return s == "success" || s.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case date, merchant, amount, currency, isCredit, isSubscription, categoryId, subcategoryId, time, transactionStatus
    }
}

/// OCR layout returned by GPT: describes how to extract fields relative to the amount line.
struct GPTExtractionLayout: Codable {
    /// Line offset: merchant line minus amount line. 0 = same line, -1 = above, +1 = below.
    let merchantLineOffset: Int
    /// How to extract the merchant string from its line.
    let merchantRule: String   // "beforePipe" | "colonRight" | "entireLine"
    /// Line offset: date line minus amount line.
    let dateLineOffset: Int
}

/// GPT response: extracted transactions + optional rules for local parsing next time + optional OCR layout.
struct GPTExtractionResponse: Codable {
    let transactions: [GPTExtractionTransaction]
    let rules: ParsingRules?
    /// OCR layout describing how transactions are structured — used to build a local extraction template.
    let layout: GPTExtractionLayout?

    init(transactions: [GPTExtractionTransaction], rules: ParsingRules?, layout: GPTExtractionLayout? = nil) {
        self.transactions = transactions
        self.rules = rules
        self.layout = layout
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        transactions = (try? c.decode([GPTExtractionTransaction].self, forKey: .transactions)) ?? []
        rules = try? c.decode(ParsingRules.self, forKey: .rules)
        layout = try? c.decode(GPTExtractionLayout.self, forKey: .layout)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(transactions, forKey: .transactions)
        try c.encodeIfPresent(rules, forKey: .rules)
        try c.encodeIfPresent(layout, forKey: .layout)
    }

    private enum CodingKeys: String, CodingKey {
        case transactions, rules, layout
    }
}

/// Batch response: one extraction result per image (same order as request).
struct GPTBatchExtractionResponse: Codable {
    let imageResults: [GPTExtractionResponse]

    init(imageResults: [GPTExtractionResponse]) {
        self.imageResults = imageResults
    }

    init(from decoder: Decoder) throws {
        // Try keyed container with imageResults or image_results (snake_case).
        if let keyed = try? decoder.container(keyedBy: BatchCodingKeys.self) {
            if let arr = try? keyed.decode([GPTExtractionResponse].self, forKey: .imageResults) {
                imageResults = arr
                return
            }
            // Try decoding array element-by-element so one bad element doesn't fail the whole batch.
            if var unkeyed = try? keyed.nestedUnkeyedContainer(forKey: .imageResults) {
                var results: [GPTExtractionResponse] = []
                while !unkeyed.isAtEnd {
                    if let el = try? unkeyed.decode(GPTExtractionResponse.self) {
                        results.append(el)
                    } else {
                        // Skip the failed element so the decoder advances (decode as generic keyed and ignore).
                        _ = try? unkeyed.decode(SkipDecodable.self)
                        results.append(GPTExtractionResponse(transactions: [], rules: nil))
                    }
                }
                imageResults = results
                return
            }
        }
        // Try root as unkeyed container (array at top level).
        var unkeyed = try decoder.unkeyedContainer()
        var results: [GPTExtractionResponse] = []
        while !unkeyed.isAtEnd {
            if let el = try? unkeyed.decode(GPTExtractionResponse.self) {
                results.append(el)
            } else {
                _ = try? unkeyed.decode(SkipDecodable.self)
                results.append(GPTExtractionResponse(transactions: [], rules: nil))
            }
        }
        imageResults = results
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: BatchCodingKeys.self)
        try c.encode(imageResults, forKey: .imageResults)
    }

    private enum BatchCodingKeys: String, CodingKey {
        case imageResults
    }
}

/// Consumes one JSON value from the decoder without decoding to a specific type (used to skip malformed elements).
private struct SkipDecodable: Decodable {
    init(from decoder: Decoder) throws {
        if var unkeyed = try? decoder.unkeyedContainer() {
            while !unkeyed.isAtEnd { _ = try? unkeyed.decode(SkipDecodable.self) }
        } else if let keyed = try? decoder.container(keyedBy: AnyCodingKey.self) {
            for key in keyed.allKeys {
                _ = try? keyed.decode(SkipDecodable.self, forKey: key)
            }
        } else {
            let c = try decoder.singleValueContainer()
            if (try? c.decode(String.self)) != nil { return }
            if (try? c.decode(Double.self)) != nil { return }
            if (try? c.decode(Bool.self)) != nil { return }
            if (try? c.decode(Int.self)) != nil { return }
            _ = try? c.decode(Optional<String>.self)
        }
    }
}

private struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init(stringValue: String) { self.stringValue = stringValue; intValue = nil }
    init?(intValue: Int) { self.intValue = intValue; stringValue = "\(intValue)" }
}

private struct OpenAIErrorBody: Decodable {
    let error: OpenAIError?
    struct OpenAIError: Decodable {
        let message: String?
        let type: String?
        let code: String?
    }
}

final class GPTRulesService {
    private let baseURL = URL(string: "https://api.openai.com/v1")!
    private let model = "gpt-5-nano"

    /// Maps API error to user-facing error; 429 → rateLimited or quotaExceeded; other quota → quotaExceeded.
    private static func apiErrorOrQuota(statusCode: Int, message: String) -> GPTRulesError {
        let lower = message.lowercased()
        if statusCode == 429 {
            // Billing quota exhausted vs. per-minute/day rate limit
            if lower.contains("quota") || lower.contains("billing") { return .quotaExceeded }
            return .rateLimited
        }
        if lower.contains("quota") || lower.contains("exceeded") { return .quotaExceeded }
        return .apiError(statusCode: statusCode, message: message)
    }

    /// Generate parsing rules from OCR text. Uses built-in app key, or Keychain if set.
    func generateRules(ocrText: String) async throws -> ParsingRules {
        let apiKey = AppSecrets.openAIKey.isEmpty ? KeychainHelper.loadOpenAIKey() : AppSecrets.openAIKey
        guard let key = apiKey, !key.isEmpty else {
            throw GPTRulesError.noApiKey
        }

        let prompt = """
        Analyze this bank/transaction OCR text and return JSON with extraction rules for a Swift parser.
        Rules will be applied locally (regex, no AI at runtime).

        Return ONLY valid JSON, no markdown. Structure:
        {
          "extraJunkPatterns": ["regex1", "regex2"],
          "datePatterns": ["regex for DD.MM.YY", "regex for Mar 11 2025"],
          "currencySymbols": {"$": "USD", "₽": "RUB", "€": "EUR"},
          "defaultCurrency": "USD",
          "amountPattern": "optional regex or null"
        }

        - extraJunkPatterns: regex patterns for lines to skip (e.g. "page \\\\d+", "order #\\\\d+")
        - datePatterns: regex to find dates in this format
        - currencySymbols: symbol → ISO code
        - defaultCurrency: if no symbol found
        - amountPattern: null to use default, or custom regex

        OCR text:
        \(ocrText.prefix(4000))
        """

        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let bodyData1 = try JSONEncoder().encode(ChatRequest(model: model, messages: [
            .init(role: "user", content: prompt)
        ]))

        let bgResponse1: BackgroundResponse
        do {
            bgResponse1 = try await GPTBackgroundSession.shared.submitRequest(request, bodyData: bodyData1)
        } catch {
            throw GPTRulesError.network(error)
        }

        let data = bgResponse1.data
        if bgResponse1.statusCode >= 400 {
            if let errBody = try? JSONDecoder().decode(OpenAIErrorBody.self, from: data),
               let msg = errBody.error?.message, !msg.isEmpty {
                throw Self.apiErrorOrQuota(statusCode: bgResponse1.statusCode, message: msg)
            }
            let raw = String(data: data, encoding: .utf8) ?? "Unknown"
            throw Self.apiErrorOrQuota(statusCode: bgResponse1.statusCode, message: "API error \(bgResponse1.statusCode): \(raw.prefix(200))")
        }
        // Fallback: background session may report status 200 even when API returned an error body.
        if let errBody = try? JSONDecoder().decode(OpenAIErrorBody.self, from: data),
           let msg = errBody.error?.message, !msg.isEmpty {
            throw Self.apiErrorOrQuota(statusCode: 401, message: msg)
        }

        let chatResponse: ChatResponse
        do {
            chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<binary \(data.count) bytes>"
            print("[GPT] ❌ ChatResponse decode failed. Status: \(bgResponse1.statusCode). Raw: \(raw.prefix(500))")
            throw GPTRulesError.invalidResponse("Failed to decode API response: \(error.localizedDescription)")
        }

        guard let content = chatResponse.extractedContent, !content.isEmpty else {
            throw GPTRulesError.invalidResponse("Empty response from model")
        }

        let cleaned = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleaned.data(using: .utf8) else {
            throw GPTRulesError.invalidResponse("Could not convert response to data")
        }

        do {
            return try JSONDecoder().decode(ParsingRules.self, from: jsonData)
        } catch {
            throw GPTRulesError.invalidResponse("Invalid rules format: \(error.localizedDescription)")
        }
    }

    /// Extract transaction data from OCR and get rules for future local parsing. Uses built-in app key.
    func extractAndGetRules(
        ocrText: String,
        categories: [(id: String, name: String)],
        subcategories: [(id: String, name: String, parentCategoryId: String)],
        baseCurrency: String = "USD"
    ) async throws -> GPTExtractionResponse {
        let apiKey = AppSecrets.openAIKey.isEmpty ? KeychainHelper.loadOpenAIKey() : AppSecrets.openAIKey
        guard let key = apiKey, !key.isEmpty else {
            throw GPTRulesError.noApiKey
        }

        let categoriesJson = categories.map { "{\"id\":\"\($0.id)\",\"name\":\"\($0.name.replacingOccurrences(of: "\"", with: "\\\""))\"}" }.joined(separator: ",")
        let subcategoriesJson = subcategories.map { "{\"id\":\"\($0.id)\",\"name\":\"\($0.name.replacingOccurrences(of: "\"", with: "\\\""))\",\"parentCategoryId\":\"\($0.parentCategoryId)\"}" }.joined(separator: ",")

        let prompt = """
        Analyze this bank/transaction OCR text. Return ONLY valid JSON, no markdown.

        Extract every completed transaction visible; do not skip any row. Each line that shows a date and amount is one transaction. One JSON object per transaction row; match rows from top to bottom if the layout is a list.

        1) Extract all transactions. For each give: date (YYYY-MM-DD), merchant (string or null), amount (number), currency (ISO code or null, default \(baseCurrency)), isCredit (boolean), isSubscription (boolean, true if recurring/subscription), categoryId (MUST be one of the category ids from the list below), subcategoryId (optional, one of subcategory ids for that category), time (HH:mm or null).

        MERCHANT rules: Always use the store or brand name as shown on the screen. It may be on the same line as the amount, above it, or sometimes opposite the expense amount — check there too in case the name is there. Do not substitute a generic word (e.g. purchase, payment, "покупка", "оплата") when a specific name is visible. The merchant name may appear in ALL CAPS, with numbers (e.g. 7-Eleven), or abbreviated — use it as displayed or in a readable standard form. For each transaction row, output the merchant name visible for that row; if no specific name is visible, use "Other".

        2) Return parsing rules so the app can parse the same format locally next time. Rules structure: extraJunkPatterns (array of regex strings), datePatterns (array of regex for dates in this format), currencySymbols (object symbol to ISO code), defaultCurrency (string), amountPattern (null or regex).

        Categories (use only these ids for categoryId): [\(categoriesJson)]
        Subcategories (use only these ids for subcategoryId, match parentCategoryId): [\(subcategoriesJson)]

        Return JSON with exactly two keys:
        "transactions": [ { "date", "merchant", "amount", "currency", "isCredit", "isSubscription", "categoryId", "subcategoryId", "time" }, ... ]
        "rules": { "extraJunkPatterns", "datePatterns", "currencySymbols", "defaultCurrency", "amountPattern" }

        OCR text:
        \(ocrText.prefix(4000))
        """

        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let bodyData2 = try JSONEncoder().encode(ChatRequest(model: model, messages: [
            .init(role: "user", content: prompt)
        ]))

        let bgResponse2: BackgroundResponse
        do {
            bgResponse2 = try await GPTBackgroundSession.shared.submitRequest(request, bodyData: bodyData2)
        } catch {
            throw GPTRulesError.network(error)
        }

        let data = bgResponse2.data
        if bgResponse2.statusCode >= 400 {
            if let errBody = try? JSONDecoder().decode(OpenAIErrorBody.self, from: data),
               let msg = errBody.error?.message, !msg.isEmpty {
                throw Self.apiErrorOrQuota(statusCode: bgResponse2.statusCode, message: msg)
            }
            let raw = String(data: data, encoding: .utf8) ?? "Unknown"
            throw Self.apiErrorOrQuota(statusCode: bgResponse2.statusCode, message: "API error \(bgResponse2.statusCode): \(raw.prefix(200))")
        }
        if let errBody = try? JSONDecoder().decode(OpenAIErrorBody.self, from: data),
           let msg = errBody.error?.message, !msg.isEmpty {
            throw Self.apiErrorOrQuota(statusCode: 401, message: msg)
        }

        let chatResponse: ChatResponse
        do {
            chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<binary \(data.count) bytes>"
            print("[GPT] ❌ ChatResponse decode failed. Status: \(bgResponse2.statusCode). Raw: \(raw.prefix(500))")
            throw GPTRulesError.invalidResponse("Failed to decode API response: \(error.localizedDescription)")
        }

        guard let content = chatResponse.extractedContent, !content.isEmpty else {
            throw GPTRulesError.invalidResponse("Empty response from model")
        }

        var cleaned = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = cleaned.firstIndex(of: "{"), let last = cleaned.lastIndex(of: "}"), first < last {
            cleaned = String(cleaned[first ... last])
        }
        guard let jsonData = cleaned.data(using: .utf8) else {
            throw GPTRulesError.invalidResponse("Could not convert response to data")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(GPTExtractionResponse.self, from: jsonData)
        } catch {
            throw GPTRulesError.invalidResponse("Invalid extraction format: \(error.localizedDescription)")
        }
    }

    /// Extract transactions from the screenshot image (Vision). Use this instead of text-only when possible.
    /// Image as base64 JPEG (e.g. from UIImage.jpegData(compressionQuality: 0.7)). Saves tokens and lets GPT see layout/colors.
    func extractAndGetRulesFromImage(
        imageBase64: String,
        ocrText: String = "",
        categories: [(id: String, name: String)],
        subcategories: [(id: String, name: String, parentCategoryId: String)],
        baseCurrency: String = "USD"
    ) async throws -> GPTExtractionResponse {
        let apiKey = AppSecrets.openAIKey.isEmpty ? KeychainHelper.loadOpenAIKey() : AppSecrets.openAIKey
        guard let key = apiKey, !key.isEmpty else {
            throw GPTRulesError.noApiKey
        }

        let categoriesJson = categories.map { "{\"id\":\"\($0.id)\",\"name\":\"\($0.name.replacingOccurrences(of: "\"", with: "\\\""))\"}" }.joined(separator: ",")
        let subcategoriesJson = subcategories.map { "{\"id\":\"\($0.id)\",\"name\":\"\($0.name.replacingOccurrences(of: "\"", with: "\\\""))\",\"parentCategoryId\":\"\($0.parentCategoryId)\"}" }.joined(separator: ",")

        let prompt = """
        Look at this bank/transaction screenshot. Return ONLY valid JSON, no markdown.

        RULES:
        - Do NOT treat the total/balance shown on the card (e.g. "Available", "Balance", "Total") as a transaction — ignore it.
        - Exclude cancelled, failed, or declined transactions (e.g. "insufficient funds", "недостаточно денег", "declined", "failed", "отменено").
        - INCLUDE gifts, incoming transfers, and credits (e.g. "КОТ" with green amount, "received", "подарунок") as income (isCredit: true).
        - Extract every completed transaction visible; do not skip any row. Each line that shows a date and amount is one transaction. One JSON object per transaction row; match rows from top to bottom if the layout is a list.

        1) Extract only real completed transactions. For each: date (YYYY-MM-DD), merchant (string or null), amount (number, use sign or context: positive for income/gifts, negative for expenses), currency (ISO code or null, default \(baseCurrency)), isCredit (true for income/gifts/refunds), isSubscription (true if recurring), categoryId (one of the category ids below), subcategoryId (optional), time (HH:mm or null). For each transaction row, identify the merchant name from that row (or the line above it if the amount is on a separate line).

        MERCHANT rules: Always use the store or brand name as shown on the screen. It may be on the same line as the amount, above it, or sometimes opposite the expense amount — check there too in case the name is there. Do not substitute a generic word (e.g. purchase, payment, "покупка", "оплата") when a specific name is visible. The merchant name may appear in ALL CAPS, with numbers (e.g. 7-Eleven), or abbreviated — use it as displayed or in a readable standard form. For each transaction row, output the merchant name visible for that row; if no specific name is visible, use "Other".

        2) Return parsing rules for the app: extraJunkPatterns, datePatterns, currencySymbols, defaultCurrency, amountPattern.

        \(ocrText.isEmpty ? "" : """
        Raw OCR text extracted from this image:
        ---
        \(ocrText)
        ---

        3) Analyze the OCR structure and return a "layout" object so the app can extract future screenshots of the same bank locally without GPT:
        - "merchantLineOffset": integer — how many lines from the amount line to the merchant line (0 = same line, -1 = one line above, +1 = one line below)
        - "merchantRule": how to extract the merchant string from its line — "beforePipe" (everything before |), "colonRight" (everything after :), or "entireLine" (whole line)
        - "dateLineOffset": integer — how many lines from the amount line to the date line
        """)

        Categories (use only these ids for categoryId): [\(categoriesJson)]
        Subcategories (use only these ids for subcategoryId): [\(subcategoriesJson)]

        Return JSON with exactly \(ocrText.isEmpty ? "two" : "three") keys:
        "transactions": [ { "date", "merchant", "amount", "currency", "isCredit", "isSubscription", "categoryId", "subcategoryId", "time" }, ... ]
        "rules": { "extraJunkPatterns", "datePatterns", "currencySymbols", "defaultCurrency", "amountPattern" }
        \(ocrText.isEmpty ? "" : "\"layout\": { \"merchantLineOffset\": <int>, \"merchantRule\": <string>, \"dateLineOffset\": <int> }")
        """

        let imageUrl = "data:image/jpeg;base64,\(imageBase64)"
        let content: [VisionChatRequest.ContentPart] = [
            .init(type: "text", text: prompt, image_url: nil),
            .init(type: "image_url", text: nil, image_url: .init(url: imageUrl))
        ]
        let body = VisionChatRequest(model: model, messages: [.init(role: "user", content: content)])

        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let bodyDataV = try JSONEncoder().encode(body)

        let bgResponseV: BackgroundResponse
        do {
            bgResponseV = try await GPTBackgroundSession.shared.submitRequest(request, bodyData: bodyDataV)
        } catch {
            throw GPTRulesError.network(error)
        }

        let data = bgResponseV.data
        if bgResponseV.statusCode >= 400 {
            if let errBody = try? JSONDecoder().decode(OpenAIErrorBody.self, from: data),
               let msg = errBody.error?.message, !msg.isEmpty {
                throw Self.apiErrorOrQuota(statusCode: bgResponseV.statusCode, message: msg)
            }
            let raw = String(data: data, encoding: .utf8) ?? "Unknown"
            throw Self.apiErrorOrQuota(statusCode: bgResponseV.statusCode, message: "API error \(bgResponseV.statusCode): \(raw.prefix(200))")
        }
        if let errBody = try? JSONDecoder().decode(OpenAIErrorBody.self, from: data),
           let msg = errBody.error?.message, !msg.isEmpty {
            throw Self.apiErrorOrQuota(statusCode: 401, message: msg)
        }

        let chatResponse: ChatResponse
        do {
            chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<binary \(data.count) bytes>"
            print("[GPT] ❌ ChatResponse decode failed. Status: \(bgResponseV.statusCode). Raw: \(raw.prefix(500))")
            throw GPTRulesError.invalidResponse("Failed to decode API response: \(error.localizedDescription)")
        }
        guard let contentStr = chatResponse.extractedContent, !contentStr.isEmpty else {
            throw GPTRulesError.invalidResponse("Empty response from model")
        }
        var cleaned = contentStr
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = cleaned.firstIndex(of: "{"), let last = cleaned.lastIndex(of: "}"), first < last {
            cleaned = String(cleaned[first ... last])
        }
        guard let jsonData = cleaned.data(using: .utf8) else {
            throw GPTRulesError.invalidResponse("Could not convert response to data")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(GPTExtractionResponse.self, from: jsonData)
        } catch {
            throw GPTRulesError.invalidResponse("Invalid extraction format: \(error.localizedDescription)")
        }
    }

    /// Batch Vision: send multiple images in one request. Returns one extraction result per image (same order). Use to save cost when 2+ images need GPT.
    func extractAndGetRulesFromImages(
        imageBase64s: [String],
        categories: [(id: String, name: String)],
        subcategories: [(id: String, name: String, parentCategoryId: String)],
        baseCurrency: String = "USD"
    ) async throws -> GPTBatchExtractionResponse {
        let apiKey = AppSecrets.openAIKey.isEmpty ? KeychainHelper.loadOpenAIKey() : AppSecrets.openAIKey
        guard let key = apiKey, !key.isEmpty else {
            throw GPTRulesError.noApiKey
        }
        guard !imageBase64s.isEmpty else {
            throw GPTRulesError.invalidResponse("No images provided")
        }

        let categoriesJson = categories.map { "{\"id\":\"\($0.id)\",\"name\":\"\($0.name.replacingOccurrences(of: "\"", with: "\\\""))\"}" }.joined(separator: ",")
        let subcategoriesJson = subcategories.map { "{\"id\":\"\($0.id)\",\"name\":\"\($0.name.replacingOccurrences(of: "\"", with: "\\\""))\",\"parentCategoryId\":\"\($0.parentCategoryId)\"}" }.joined(separator: ",")
        let n = imageBase64s.count
        let prompt = """
        I'm sending \(n) bank/transaction screenshot(s). For EACH image, in order (first image = index 0, second = 1, etc.), extract transactions and parsing rules.

        RULES:
        - Do NOT treat the total/balance shown on the card (e.g. "Available", "Balance", "Total") as a transaction — ignore it.
        - Exclude cancelled, failed, or declined transactions (e.g. "insufficient funds", "declined", "failed").
        - INCLUDE gifts, incoming transfers, and credits as income (isCredit: true).
        - Extract every completed transaction visible; do not skip any row. Each line that shows a date and amount is one transaction. One JSON object per transaction row; match rows from top to bottom if the layout is a list.

        For each screenshot: extract only real completed transactions. For each: date (YYYY-MM-DD), merchant (string or null), amount (number; positive for income, negative for expenses), currency (ISO or null, default \(baseCurrency)), isCredit (true for income/gifts), isSubscription (true if recurring), categoryId (from categories below), subcategoryId (optional), time (HH:mm or null). Use the store/brand name as shown; if no specific name, use "Other".

        For each screenshot also return parsing rules: extraJunkPatterns, datePatterns, currencySymbols, defaultCurrency, amountPattern. If screenshots are from different banks/formats, return DIFFERENT rules per image. If they are the same format, you may return the same rules for each.

        Categories (use only these ids for categoryId): [\(categoriesJson)]
        Subcategories (use only these ids for subcategoryId): [\(subcategoriesJson)]

        Return ONLY valid JSON, no markdown, with exactly this structure:
        {"imageResults": [ {"transactions": [...], "rules": {...} }, {"transactions": [...], "rules": {...} }, ... ]}
        One object in imageResults per image, in the same order as the images (first image = imageResults[0]).
        """

        var content: [VisionChatRequest.ContentPart] = [.init(type: "text", text: prompt, image_url: nil)]
        for base64 in imageBase64s {
            let imageUrl = "data:image/jpeg;base64,\(base64)"
            content.append(.init(type: "image_url", text: nil, image_url: .init(url: imageUrl)))
        }
        let body = VisionChatRequest(model: model, messages: [.init(role: "user", content: content)])

        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let bodyDataV = try JSONEncoder().encode(body)

        let bgResponseV: BackgroundResponse
        do {
            bgResponseV = try await GPTBackgroundSession.shared.submitRequest(request, bodyData: bodyDataV)
        } catch {
            throw GPTRulesError.network(error)
        }

        let data = bgResponseV.data
        if bgResponseV.statusCode >= 400 {
            if let errBody = try? JSONDecoder().decode(OpenAIErrorBody.self, from: data),
               let msg = errBody.error?.message, !msg.isEmpty {
                throw Self.apiErrorOrQuota(statusCode: bgResponseV.statusCode, message: msg)
            }
            let raw = String(data: data, encoding: .utf8) ?? "Unknown"
            throw Self.apiErrorOrQuota(statusCode: bgResponseV.statusCode, message: "API error \(bgResponseV.statusCode): \(raw.prefix(200))")
        }
        if let errBody = try? JSONDecoder().decode(OpenAIErrorBody.self, from: data),
           let msg = errBody.error?.message, !msg.isEmpty {
            throw Self.apiErrorOrQuota(statusCode: 401, message: msg)
        }

        let chatResponse: ChatResponse
        do {
            chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<binary \(data.count) bytes>"
            print("[GPT] ❌ ChatResponse decode failed. Status: \(bgResponseV.statusCode). Raw: \(raw.prefix(500))")
            throw GPTRulesError.invalidResponse("Failed to decode API response: \(error.localizedDescription)")
        }
        guard let contentStr = chatResponse.extractedContent, !contentStr.isEmpty else {
            throw GPTRulesError.invalidResponse("Empty response from model")
        }
        var jsonData = Self.extractJSONDataFromBatchResponse(contentStr)
        if jsonData == nil, let first = contentStr.firstIndex(of: "{"), let last = contentStr.lastIndex(of: "}"), first < last {
            let simple = String(contentStr[first...last])
            jsonData = simple.data(using: .utf8)
        }
        guard let jsonData = jsonData else {
            throw GPTRulesError.invalidResponse("Could not extract JSON from response")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(GPTBatchExtractionResponse.self, from: jsonData)
        } catch {
            if imageBase64s.count == 1, let single = try? decoder.decode(GPTExtractionResponse.self, from: jsonData) {
                return GPTBatchExtractionResponse(imageResults: [single])
            }
            if let manual = Self.parseBatchResponseManually(jsonData: jsonData) {
                return manual
            }
            throw GPTRulesError.invalidResponse("Invalid batch extraction format: \(error.localizedDescription)")
        }
    }

    /// Extracts JSON data from batch API response text (strips markdown, finds root object by brace matching, fixes trailing commas).
    private static func extractJSONDataFromBatchResponse(_ contentStr: String) -> Data? {
        let cleaned = contentStr
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let startIdx = cleaned.firstIndex(of: "{") else { return nil }
        let fromStart = String(cleaned[startIdx...])
        var depth = 0
        var endIdx: String.Index?
        for i in fromStart.indices {
            let c = fromStart[i]
            if c == "{" { depth += 1 }
            else if c == "}" { depth -= 1; if depth == 0 { endIdx = i; break } }
        }
        let jsonStr: String
        if let endIdx = endIdx {
            jsonStr = String(fromStart[...endIdx])
        } else if let last = fromStart.lastIndex(of: "}") {
            jsonStr = String(fromStart[...last])
        } else {
            return nil
        }
        let trailingComma = try? NSRegularExpression(pattern: ",\\s*([}\\]])", options: [])
        let fixed = (trailingComma.flatMap { re in
            let range = NSRange(jsonStr.startIndex..., in: jsonStr)
            return re.stringByReplacingMatches(in: jsonStr, options: [], range: range, withTemplate: "$1")
        }) ?? jsonStr
        return fixed.data(using: .utf8)
    }

    /// Fallback: parse raw JSON by hand to tolerate any structure GPT returns (different keys, nesting, or element shape).
    private static func parseBatchResponseManually(jsonData: Data) -> GPTBatchExtractionResponse? {
        var dataToUse = jsonData
        if (try? JSONSerialization.jsonObject(with: jsonData)) == nil, let str = String(data: jsonData, encoding: .utf8) {
            let fixed = str.replacingOccurrences(of: ",\\s*}", with: "}", options: .regularExpression)
                .replacingOccurrences(of: ",\\s*]", with: "]", options: .regularExpression)
            dataToUse = fixed.data(using: .utf8) ?? jsonData
        }
        guard let top = try? JSONSerialization.jsonObject(with: dataToUse) else { return nil }
        let array: [Any]
        if let dict = top as? [String: Any] {
            if let arr = dict["imageResults"] as? [Any] ?? dict["image_results"] as? [Any] ?? dict["results"] as? [Any] ?? dict["data"] as? [Any] {
                array = arr
            } else if dict["transactions"] != nil {
                array = [top]
            } else if let firstArrayValue = dict.first(where: { $0.value is [Any] })?.value as? [Any] {
                array = firstArrayValue
            } else if let nested = dict.first(where: { ($0.value as? [String: Any])?["imageResults"] != nil || ($0.value as? [String: Any])?["transactions"] != nil })?.value as? [String: Any] {
                if let arr = nested["imageResults"] as? [Any] ?? nested["image_results"] as? [Any] ?? nested["results"] as? [Any] {
                    array = arr
                } else if nested["transactions"] != nil {
                    array = [nested]
                } else {
                    return nil
                }
            } else {
                let ordered = dict.keys.sorted().compactMap { key -> [String: Any]? in
                    guard let v = dict[key] as? [String: Any], v["transactions"] != nil else { return nil }
                    return v
                }
                if !ordered.isEmpty {
                    array = ordered
                } else {
                    return nil
                }
            }
        } else if let arr = top as? [Any] {
            array = arr
        } else {
            return nil
        }
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        var results: [GPTExtractionResponse] = []
        for item in array {
            guard let itemData = try? JSONSerialization.data(withJSONObject: item) else {
                results.append(GPTExtractionResponse(transactions: [], rules: nil))
                continue
            }
            if let el = try? dec.decode(GPTExtractionResponse.self, from: itemData) {
                results.append(el)
            } else {
                results.append(GPTExtractionResponse(transactions: [], rules: nil))
            }
        }
        return GPTBatchExtractionResponse(imageResults: results)
    }

    // MARK: - Subscription Insights

    struct SubscriptionInsightResponse: Decodable {
        let merchant: String
        let currentMarketMonthlyPrice: Double?
        let alternatives: [AlternativeResponse]
        let tip: String
        let monthlySavingsPotential: Double

        struct AlternativeResponse: Decodable {
            let planName: String
            let price: Double
            let interval: String
        }
    }

    func analyzeSubscriptions(
        subscriptions: [(merchant: String, amount: Double, interval: String, currency: String)]
    ) async throws -> [SubscriptionInsightResponse] {
        let apiKey = AppSecrets.openAIKey.isEmpty ? KeychainHelper.loadOpenAIKey() : AppSecrets.openAIKey
        guard let key = apiKey, !key.isEmpty else {
            throw GPTRulesError.noApiKey
        }

        struct SubInput: Encodable {
            let merchant: String
            let amount: Double
            let interval: String
            let currency: String
        }
        let subInputs = subscriptions.map { SubInput(merchant: $0.merchant, amount: $0.amount, interval: $0.interval, currency: $0.currency) }
        let subsJSON: String
        if let encoded = try? JSONEncoder().encode(subInputs),
           let str = String(data: encoded, encoding: .utf8) {
            subsJSON = str
        } else {
            subsJSON = "[]"
        }

        let prompt = """
        You are a personal finance advisor. Analyze these subscription services.
        For each subscription, check if the price matches current market rates (include ~15% tax).
        Suggest cheaper alternatives (annual plan, family plan, student discount) if available.

        Subscriptions:
        \(subsJSON)

        Return ONLY valid JSON array, no markdown:
        [{
          "merchant": "Service Name",
          "currentMarketMonthlyPrice": 14.99,
          "alternatives": [
            {"planName": "Annual Plan (prepaid)", "price": 99.99, "interval": "yearly"},
            {"planName": "Family Plan", "price": 16.99, "interval": "monthly"}
          ],
          "tip": "Your annual plan saves $30/year vs monthly billing.",
          "monthlySavingsPotential": 2.50
        }]

        Rules:
        - Only include alternatives you're confident exist as of 2024-2025
        - Prices should reflect US market with ~15% tax included
        - If no savings possible, set monthlySavingsPotential to 0 and tip to a positive note
        - Be concise in tips (1-2 sentences max)
        - If you don't recognize a merchant, skip it (don't guess)
        """

        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let bodyData = try JSONEncoder().encode(ChatRequest(model: model, messages: [
            .init(role: "user", content: prompt)
        ]))

        print("[SubsInsight] >>> Sending \(subscriptions.count) subs to GPT:")
        for s in subscriptions {
            print("[SubsInsight] >>>  · \(s.merchant) \(s.amount) \(s.currency) / \(s.interval)")
        }

        // Use foreground URLSession (not background) — subscription analysis runs while app is active,
        // and background upload tasks have aggressive system timeouts that cause failures.
        request.httpBody = bodyData
        request.timeoutInterval = 120

        let data: Data
        let httpResponse: HTTPURLResponse
        do {
            let (respData, resp) = try await URLSession.shared.data(for: request)
            data = respData
            httpResponse = resp as! HTTPURLResponse
        } catch {
            print("[SubsInsight] <<< Network error: \(error)")
            throw GPTRulesError.network(error)
        }

        let rawStr = String(data: data, encoding: .utf8) ?? "<binary \(data.count) bytes>"
        print("[SubsInsight] <<< Status: \(httpResponse.statusCode), raw response (\(data.count) bytes):\n\(rawStr.prefix(2000))")
        if httpResponse.statusCode >= 400 {
            if let errBody = try? JSONDecoder().decode(OpenAIErrorBody.self, from: data),
               let msg = errBody.error?.message, !msg.isEmpty {
                throw Self.apiErrorOrQuota(statusCode: httpResponse.statusCode, message: msg)
            }
            let raw = String(data: data, encoding: .utf8) ?? "Unknown"
            throw Self.apiErrorOrQuota(statusCode: httpResponse.statusCode, message: "API error \(httpResponse.statusCode): \(raw.prefix(200))")
        }

        let chatResponse: ChatResponse
        do {
            chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<binary \(data.count) bytes>"
            print("[GPT] ❌ Subscriptions decode failed. Raw: \(raw.prefix(500))")
            throw GPTRulesError.invalidResponse("Failed to decode API response: \(error.localizedDescription)")
        }

        guard let content = chatResponse.extractedContent, !content.isEmpty else {
            throw GPTRulesError.invalidResponse("Empty response from model")
        }

        let cleaned = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleaned.data(using: .utf8) else {
            throw GPTRulesError.invalidResponse("Could not convert subscription response to data")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode([SubscriptionInsightResponse].self, from: jsonData)
        } catch {
            print("[GPT] ❌ Subscription insights JSON parse failed: \(error). Raw: \(cleaned.prefix(500))")
            throw GPTRulesError.invalidResponse("Invalid subscription insights format: \(error.localizedDescription)")
        }
    }
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [Message]
    struct Message: Encodable {
        let role: String
        let content: String
    }
}

/// Vision request: message content is an array of text + image_url (base64). Temperature omitted so API uses model default (this model does not support 0).
private struct VisionChatRequest: Encodable {
    let model: String
    let messages: [VisionMessage]
    struct VisionMessage: Encodable {
        let role: String
        let content: [ContentPart]
    }
    struct ContentPart: Encodable {
        let type: String
        let text: String?
        let image_url: ImageURL?
        struct ImageURL: Encodable {
            let url: String
        }
        enum CodingKeys: String, CodingKey { case type, text, image_url }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(type, forKey: .type)
            try c.encodeIfPresent(text, forKey: .text)
            try c.encodeIfPresent(image_url, forKey: .image_url)
        }
    }
}

private struct ChatResponse: Decodable {
    let choices: [Choice]?
    let output: [OutputItem]?

    struct Choice: Decodable {
        let message: Message
        struct Message: Decodable {
            let content: String?
        }
    }

    struct OutputItem: Decodable {
        let content: [ContentPart]?
        struct ContentPart: Decodable {
            let text: String?
        }
    }

    /// Extract text content from either Chat Completions or Responses API format.
    var extractedContent: String? {
        if let c = choices?.first?.message.content { return c }
        if let parts = output?.first?.content {
            let joined = parts.compactMap { $0.text }.joined()
            return joined.isEmpty ? nil : joined
        }
        return nil
    }
}
