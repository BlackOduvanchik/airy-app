//
//  GPTRulesService.swift
//  Airy
//
//  Sends screenshot to OpenAI, receives extracted transactions.
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

/// One transaction extracted by GPT from screenshot.
struct GPTExtractionTransaction: Codable {
    let date: String
    let merchant: String?
    let amount: Double
    let currency: String?
    let isCredit: Bool?
    let isSubscription: Bool?
    let subscriptionInterval: String?
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
        subscriptionInterval = try c.decodeIfPresent(String.self, forKey: .subscriptionInterval)
        categoryId = try c.decodeIfPresent(String.self, forKey: .categoryId)
        subcategoryId = try c.decodeIfPresent(String.self, forKey: .subcategoryId)
        time = try c.decodeIfPresent(String.self, forKey: .time)
        transactionStatus = try c.decodeIfPresent(String.self, forKey: .transactionStatus)
    }

    /// True if this transaction should be included in the pending review list.
    /// Only exclude clearly invalid statuses. "pending" is allowed because
    /// GPT often marks normal bank transactions as pending, and the user
    /// reviews everything in PendingReview before saving anyway.
    var isSuccessStatus: Bool {
        let s = (transactionStatus ?? "").lowercased().trimmingCharacters(in: .whitespaces)
        let rejected: Set<String> = ["failed", "reversed", "declined", "cancelled", "canceled"]
        return !rejected.contains(s)
    }

    private enum CodingKeys: String, CodingKey {
        case date, merchant, amount, currency, isCredit, isSubscription, subscriptionInterval, categoryId, subcategoryId, time, transactionStatus
    }
}

/// GPT response: extracted transactions.
struct GPTExtractionResponse: Codable {
    let transactions: [GPTExtractionTransaction]

    init(transactions: [GPTExtractionTransaction]) {
        self.transactions = transactions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Decode each transaction individually so one malformed element
        // doesn't silently discard the entire array.
        var txContainer = try c.nestedUnkeyedContainer(forKey: .transactions)
        var result: [GPTExtractionTransaction] = []
        var failures = 0
        while !txContainer.isAtEnd {
            if let tx = try? txContainer.decode(GPTExtractionTransaction.self) {
                result.append(tx)
            } else {
                _ = try? txContainer.decode(GPTAnyCodable.self)
                failures += 1
            }
        }
        if failures > 0 {
            print("[GPT] ⚠️ Skipped \(failures) malformed transaction(s), decoded \(result.count) OK")
        }
        transactions = result
    }

    private enum CodingKeys: String, CodingKey {
        case transactions
    }
}

/// Minimal type-erased Decodable used to advance the decoder past a malformed element.
private struct GPTAnyCodable: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { return }
        if let _ = try? container.decode(Bool.self) { return }
        if let _ = try? container.decode(Int.self) { return }
        if let _ = try? container.decode(Double.self) { return }
        if let _ = try? container.decode(String.self) { return }
        if let _ = try? container.decode([GPTAnyCodable].self) { return }
        if let _ = try? container.decode([String: GPTAnyCodable].self) { return }
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

// MARK: - JSON helpers for safe escaping

private struct CatRef: Encodable { let id: String; let name: String }
private struct SubRef: Encodable { let id: String; let name: String; let parentCategoryId: String }

final class GPTRulesService {
    private let baseURL = URL(string: "https://api.openai.com/v1")!
    private let model = "gpt-5-nano"

    /// Maps API error to user-facing error; 429 → rateLimited or quotaExceeded; other quota → quotaExceeded.
    private static func apiErrorOrQuota(statusCode: Int, message: String) -> GPTRulesError {
        let lower = message.lowercased()
        if statusCode == 429 {
            if lower.contains("quota") || lower.contains("billing") { return .quotaExceeded }
            return .rateLimited
        }
        if lower.contains("quota") || lower.contains("exceeded") { return .quotaExceeded }
        return .apiError(statusCode: statusCode, message: message)
    }

    // MARK: - Extract transactions from image

    /// Extract transactions from screenshot image via GPT Vision.
    func extractTransactionsFromImage(
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

        let categoriesJson = (try? String(data: JSONEncoder().encode(categories.map { CatRef(id: $0.id, name: $0.name) }), encoding: .utf8)) ?? "[]"
        let subcategoriesJson = (try? String(data: JSONEncoder().encode(subcategories.map { SubRef(id: $0.id, name: $0.name, parentCategoryId: $0.parentCategoryId) }), encoding: .utf8)) ?? "[]"

        let prompt = """
        Look at this bank/transaction screenshot. Return ONLY valid JSON, no markdown.

        RULES:
        - Do NOT treat the total/balance shown on the card (e.g. "Available", "Balance", "Total") as a transaction — ignore it.
        - Exclude cancelled, failed, or declined transactions (e.g. "insufficient funds", "declined", "failed", "отменено").
        - INCLUDE gifts, incoming transfers, and credits (e.g. green amount, "received", "подарунок") as income (isCredit: true).
        - Extract every completed transaction visible; do not skip any row. Each line that shows a date and amount is one transaction. One JSON object per transaction row; match rows from top to bottom if the layout is a list.

        For each transaction return:
        - date (YYYY-MM-DD)
        - merchant (string or null — use the store/brand name as shown, not generic words like "payment" or "покупка"; if no name visible, use "Other")
        - amount (number, positive)
        - currency (ISO code or null, default \(baseCurrency))
        - isCredit (true for income/gifts/refunds, false for expenses)
        - isSubscription (true if recurring subscription)
        - subscriptionInterval (only when isSubscription is true: "monthly", "yearly", or "weekly")
        - categoryId (MUST be one of the "id" values from the categories list below — return UUID, NOT name)
        - subcategoryId (optional, MUST be one of the "id" values from the subcategories list — parentCategoryId must match chosen categoryId)
        - time (HH:mm or null)
        - transactionStatus ("success", "failed", "pending", or "reversed")

        CATEGORY rules: If the screenshot shows a category hierarchy from another app (e.g. parent "Квартира" with subcategory "Интернет"), find the best-matching category by name and use its "id" as categoryId, then find subcategory and use its "id" as subcategoryId. Always return UUID ids, never names.

        MERCHANT rules: Always use the store or brand name as shown on the screen. It may be on the same line as the amount, above it, or opposite the expense amount. The merchant name may appear in ALL CAPS, with numbers (e.g. 7-Eleven), or abbreviated — use it as displayed or in readable form.

        \(ocrText.isEmpty ? "" : """
        Raw OCR text extracted from this image:
        ---
        \(ocrText.prefix(4000))
        ---
        """)

        Categories (use only "id" values for categoryId): \(categoriesJson)
        Subcategories (use only "id" values for subcategoryId, parentCategoryId must match chosen categoryId): \(subcategoriesJson)

        Return JSON with exactly one key:
        {"transactions": [{"date", "merchant", "amount", "currency", "isCredit", "isSubscription", "subscriptionInterval", "categoryId", "subcategoryId", "time", "transactionStatus"}, ...]}
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

        let langCode = await MainActor.run { LanguageManager.shared.current.rawValue }
        let langMap: [String: String] = [
            "en": "English", "ru": "Russian", "uk": "Ukrainian", "be": "Belarusian",
            "de": "German", "fr": "French", "es": "Spanish", "pt": "Portuguese",
            "zh-Hans": "Chinese (Simplified)", "ja": "Japanese"
        ]
        let langName = langMap[langCode] ?? "English"

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
        Suggest cheaper PAID alternatives: annual prepaid plans, current promotions, or family plans.
        IMPORTANT: Write ALL text fields ("planName", "tip") in \(langName).

        Subscriptions:
        \(subsJSON)

        Return ONLY valid JSON array, no markdown:
        [{
          "merchant": "Service Name",
          "currentMarketMonthlyPrice": 14.99,
          "alternatives": [
            {"planName": "Annual Plan (prepaid)", "price": 99.99, "interval": "yearly"}
          ],
          "tip": "Annual plan saves $30/year vs monthly billing.",
          "monthlySavingsPotential": 2.50
        }]

        Rules:
        - NEVER suggest free plans or free tiers — the user is paying, so they need the paid version
        - Only suggest alternatives that cost less per month than what the user currently pays
        - Focus on: annual prepaid discounts, current promotions, bundle/family plans
        - Only include alternatives you're confident exist as of 2025-2026
        - Do NOT suggest student, military, or any other eligibility-restricted discounts
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

        request.httpBody = bodyData
        request.timeoutInterval = 120

        let data: Data
        let httpResponse: HTTPURLResponse
        do {
            let (respData, resp) = try await URLSession.shared.data(for: request)
            data = respData
            httpResponse = resp as! HTTPURLResponse
        } catch {
            throw GPTRulesError.network(error)
        }

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
            throw GPTRulesError.invalidResponse("Invalid subscription insights format: \(error.localizedDescription)")
        }
    }
}

// MARK: - Request / Response types

private struct ChatRequest: Encodable {
    let model: String
    let messages: [Message]
    struct Message: Encodable {
        let role: String
        let content: String
    }
}

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

    var extractedContent: String? {
        if let c = choices?.first?.message.content { return c }
        if let parts = output?.first?.content {
            let joined = parts.compactMap { $0.text }.joined()
            return joined.isEmpty ? nil : joined
        }
        return nil
    }
}
