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

    var errorDescription: String? {
        switch self {
        case .noApiKey: return "Add and save your OpenAI API key first."
        case .invalidResponse(let detail): return "Invalid response: \(detail)"
        case .network(let err): return "Network: \(err.localizedDescription)"
        case .apiError(_, let msg): return msg
        }
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
    private let model = "gpt-4o-mini"

    /// Generate parsing rules from OCR text. Requires OpenAI API key in Keychain.
    func generateRules(ocrText: String) async throws -> ParsingRules {
        guard let apiKey = KeychainHelper.loadOpenAIKey(), !apiKey.isEmpty else {
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
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ChatRequest(model: model, messages: [
            .init(role: "user", content: prompt)
        ]))

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw GPTRulesError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw GPTRulesError.invalidResponse("Not an HTTP response")
        }

        if http.statusCode >= 400 {
            if let errBody = try? JSONDecoder().decode(OpenAIErrorBody.self, from: data),
               let msg = errBody.error?.message, !msg.isEmpty {
                throw GPTRulesError.apiError(statusCode: http.statusCode, message: msg)
            }
            let raw = String(data: data, encoding: .utf8) ?? "Unknown"
            throw GPTRulesError.apiError(statusCode: http.statusCode, message: "API error \(http.statusCode): \(raw.prefix(200))")
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
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [Message]
    struct Message: Encodable {
        let role: String
        let content: String
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
