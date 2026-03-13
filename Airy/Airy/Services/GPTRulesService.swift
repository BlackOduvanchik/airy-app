//
//  GPTRulesService.swift
//  Airy
//
//  Sends OCR text to OpenAI, receives parsing rules. Rules are saved locally for future use.
//

import Foundation

// #region agent log
private func _debugLog(_ message: String, location: String, data: [String: Any] = [:]) {
    let payload: [String: Any] = [
        "sessionId": "ad783c",
        "location": location,
        "message": message,
        "data": data,
        "timestamp": Int(Date().timeIntervalSince1970 * 1000)
    ]
    guard let json = try? JSONSerialization.data(withJSONObject: payload),
          let line = String(data: json, encoding: .utf8) else { return }
    let path = "/Users/oduvanchik/Desktop/Airy/.cursor/debug-ad783c.log"
    let lineData = (line + "\n").data(using: .utf8)!
    if !FileManager.default.fileExists(atPath: path) {
        FileManager.default.createFile(atPath: path, contents: lineData, attributes: nil)
        return
    }
    guard let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) else { return }
    defer { try? handle.close() }
    handle.seekToEndOfFile()
    handle.write(lineData)
}
// #endregion

enum GPTRulesError: LocalizedError {
    case noApiKey
    case invalidResponse(String)
    case network(Error)
    case apiError(statusCode: Int, message: String)
    case quotaExceeded

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
    }

    private enum CodingKeys: String, CodingKey {
        case date, merchant, amount, currency, isCredit, isSubscription, categoryId, subcategoryId, time
    }
}

/// GPT response: extracted transactions + optional rules for local parsing next time.
struct GPTExtractionResponse: Codable {
    let transactions: [GPTExtractionTransaction]
    let rules: ParsingRules?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        transactions = (try? c.decode([GPTExtractionTransaction].self, forKey: .transactions)) ?? []
        rules = try? c.decode(ParsingRules.self, forKey: .rules)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(transactions, forKey: .transactions)
        try c.encodeIfPresent(rules, forKey: .rules)
    }

    private enum CodingKeys: String, CodingKey {
        case transactions, rules
    }
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

    /// Longer timeout for GPT (default 60s can trigger "request timed out" while server still processes).
    private static var longTimeoutSession: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 120
        c.timeoutIntervalForResource = 180
        return URLSession(configuration: c)
    }()

    /// Maps API error to user-facing error; quota/exceeded → friendly message.
    private static func apiErrorOrQuota(statusCode: Int, message: String) -> GPTRulesError {
        let lower = message.lowercased()
        if lower.contains("quota") || lower.contains("exceeded") {
            return .quotaExceeded
        }
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
        request.httpBody = try JSONEncoder().encode(ChatRequest(model: model, messages: [
            .init(role: "user", content: prompt)
        ]))

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await Self.longTimeoutSession.data(for: request)
        } catch {
            throw GPTRulesError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw GPTRulesError.invalidResponse("Not an HTTP response")
        }

        if http.statusCode >= 400 {
            if let errBody = try? JSONDecoder().decode(OpenAIErrorBody.self, from: data),
               let msg = errBody.error?.message, !msg.isEmpty {
                throw Self.apiErrorOrQuota(statusCode: http.statusCode, message: msg)
            }
            let raw = String(data: data, encoding: .utf8) ?? "Unknown"
            throw Self.apiErrorOrQuota(statusCode: http.statusCode, message: "API error \(http.statusCode): \(raw.prefix(200))")
        }

        let chatResponse: ChatResponse
        do {
            chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            throw GPTRulesError.invalidResponse("Failed to decode API response: \(error.localizedDescription)")
        }

        guard let content = chatResponse.choices.first?.message.content, !content.isEmpty else {
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

        1) Extract all transactions. For each give: date (YYYY-MM-DD), merchant (string or null), amount (number), currency (ISO code or null, default \(baseCurrency)), isCredit (boolean), isSubscription (boolean, true if recurring/subscription), categoryId (MUST be one of the category ids from the list below), subcategoryId (optional, one of subcategory ids for that category), time (HH:mm or null).

        MERCHANT rules: Use the store, brand, or establishment name (e.g. TOPS, Starbucks, McDonald's) — usually the first or most prominent name on the line with the amount. Do NOT use generic labels like "покупка", "purchase", "payment", "transaction", "оплата", "withdrawal". If you only see a generic word next to the amount, look for the store/company name on the same line or above (often left of the amount). If no specific merchant is found, use "Other".

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
        request.httpBody = try JSONEncoder().encode(ChatRequest(model: model, messages: [
            .init(role: "user", content: prompt)
        ]))

        // #region agent log
        _debugLog("GPT extractAndGetRules request start", location: "GPTRulesService.extractAndGetRules", data: ["timeout": 120])
        // #endregion
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await Self.longTimeoutSession.data(for: request)
        } catch {
            // #region agent log
            _debugLog("GPT extractAndGetRules request failed", location: "GPTRulesService.extractAndGetRules", data: ["error": String(describing: error)])
            // #endregion
            throw GPTRulesError.network(error)
        }
        // #region agent log
        _debugLog("GPT extractAndGetRules request completed", location: "GPTRulesService.extractAndGetRules", data: ["statusCode": (response as? HTTPURLResponse)?.statusCode ?? 0])
        // #endregion

        guard let http = response as? HTTPURLResponse else {
            throw GPTRulesError.invalidResponse("Not an HTTP response")
        }

        if http.statusCode >= 400 {
            if let errBody = try? JSONDecoder().decode(OpenAIErrorBody.self, from: data),
               let msg = errBody.error?.message, !msg.isEmpty {
                throw Self.apiErrorOrQuota(statusCode: http.statusCode, message: msg)
            }
            let raw = String(data: data, encoding: .utf8) ?? "Unknown"
            throw Self.apiErrorOrQuota(statusCode: http.statusCode, message: "API error \(http.statusCode): \(raw.prefix(200))")
        }

        let chatResponse: ChatResponse
        do {
            chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            throw GPTRulesError.invalidResponse("Failed to decode API response: \(error.localizedDescription)")
        }

        guard let content = chatResponse.choices.first?.message.content, !content.isEmpty else {
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
            let rawPreview = String(data: jsonData, encoding: .utf8).map { String($0.prefix(3000)) } ?? ""
            _debugLog("GPT extraction decode failed (text)", location: "GPTRulesService.extractAndGetRules", data: ["decodeError": String(describing: error), "rawPreview": rawPreview])
            throw GPTRulesError.invalidResponse("Invalid extraction format: \(error.localizedDescription)")
        }
    }

    /// Extract transactions from the screenshot image (Vision). Use this instead of text-only when possible.
    /// Image as base64 JPEG (e.g. from UIImage.jpegData(compressionQuality: 0.7)). Saves tokens and lets GPT see layout/colors.
    func extractAndGetRulesFromImage(
        imageBase64: String,
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

        1) Extract only real completed transactions. For each: date (YYYY-MM-DD), merchant (string or null), amount (number, use sign or context: positive for income/gifts, negative for expenses), currency (ISO code or null, default \(baseCurrency)), isCredit (true for income/gifts/refunds), isSubscription (true if recurring), categoryId (one of the category ids below), subcategoryId (optional), time (HH:mm or null).

        MERCHANT rules: Use the store, brand, or establishment name (e.g. TOPS, Starbucks, McDonald's) — usually the first or most prominent name on the line with the amount. Do NOT use generic labels like "покупка", "purchase", "payment", "transaction", "оплата", "withdrawal". If you only see a generic word next to the amount, look for the store/company name on the same line or above (often left of the amount). If no specific merchant is found, use "Other".

        2) Return parsing rules for the app: extraJunkPatterns, datePatterns, currencySymbols, defaultCurrency, amountPattern.

        Categories (use only these ids for categoryId): [\(categoriesJson)]
        Subcategories (use only these ids for subcategoryId): [\(subcategoriesJson)]

        Return JSON with exactly two keys:
        "transactions": [ { "date", "merchant", "amount", "currency", "isCredit", "isSubscription", "categoryId", "subcategoryId", "time" }, ... ]
        "rules": { "extraJunkPatterns", "datePatterns", "currencySymbols", "defaultCurrency", "amountPattern" }
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
        request.httpBody = try JSONEncoder().encode(body)

        // #region agent log
        _debugLog("GPT extractAndGetRulesFromImage request start", location: "GPTRulesService.extractAndGetRulesFromImage", data: ["timeout": 120])
        // #endregion
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await Self.longTimeoutSession.data(for: request)
        } catch {
            // #region agent log
            _debugLog("GPT extractAndGetRulesFromImage request failed", location: "GPTRulesService.extractAndGetRulesFromImage", data: ["error": String(describing: error)])
            // #endregion
            throw GPTRulesError.network(error)
        }
        // #region agent log
        _debugLog("GPT extractAndGetRulesFromImage request completed", location: "GPTRulesService.extractAndGetRulesFromImage", data: ["statusCode": (response as? HTTPURLResponse)?.statusCode ?? 0])
        // #endregion

        guard let http = response as? HTTPURLResponse else {
            throw GPTRulesError.invalidResponse("Not an HTTP response")
        }
        if http.statusCode >= 400 {
            if let errBody = try? JSONDecoder().decode(OpenAIErrorBody.self, from: data),
               let msg = errBody.error?.message, !msg.isEmpty {
                throw Self.apiErrorOrQuota(statusCode: http.statusCode, message: msg)
            }
            let raw = String(data: data, encoding: .utf8) ?? "Unknown"
            throw Self.apiErrorOrQuota(statusCode: http.statusCode, message: "API error \(http.statusCode): \(raw.prefix(200))")
        }

        let chatResponse: ChatResponse
        do {
            chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            throw GPTRulesError.invalidResponse("Failed to decode API response: \(error.localizedDescription)")
        }
        guard let contentStr = chatResponse.choices.first?.message.content, !contentStr.isEmpty else {
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
            let rawPreview = String(data: jsonData, encoding: .utf8).map { String($0.prefix(3000)) } ?? ""
            _debugLog("GPT extraction decode failed (image)", location: "GPTRulesService.extractAndGetRulesFromImage", data: ["decodeError": String(describing: error), "rawPreview": rawPreview])
            throw GPTRulesError.invalidResponse("Invalid extraction format: \(error.localizedDescription)")
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

/// Vision request: message content is an array of text + image_url (base64).
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
    let choices: [Choice]
    struct Choice: Decodable {
        let message: Message
        struct Message: Decodable {
            let content: String?
        }
    }
}
