//
//  APIClient.swift
//  Airy
//

import Foundation

actor APIClient {
    static let shared = APIClient()
    private let baseURL: URL
    private let session: URLSession
    var authToken: String?

    init(baseURL: URL = Endpoints.baseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func setAuthToken(_ token: String?) {
        authToken = token
    }

    func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        body: (any Encodable)? = nil,
        query: [String: String]? = nil,
        idempotencyKey: String? = nil
    ) async throws -> T {
        let pathTrimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard let url = URL(string: pathTrimmed, relativeTo: baseURL) else { throw APIError.invalidResponse }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        if let query = query, !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let key = idempotencyKey {
            request.setValue(key, forHTTPHeaderField: "Idempotency-Key")
        }
        if let body = body {
            request.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode >= 400 {
            let message = (try? JSONDecoder().decode(APIErrorBody.self, from: data))?.error ?? String(data: data, encoding: .utf8) ?? "Unknown error"
            if http.statusCode == 402 { throw APIError.paymentRequired(message) }
            throw APIError.http(statusCode: http.statusCode, message: message)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func parseScreenshot(ocrText: String, localHash: String?, baseCurrency: String, idempotencyKey: String?) async throws -> ParseScreenshotResponse {
        struct Body: Encodable {
            let ocrText: String
            let localHash: String?
            let baseCurrency: String
        }
        return try await request(
            Endpoints.parseScreenshot,
            method: "POST",
            body: Body(ocrText: ocrText, localHash: localHash, baseCurrency: baseCurrency),
            idempotencyKey: idempotencyKey
        ) as ParseScreenshotResponse
    }

    func getPendingTransactions() async throws -> PendingTransactionsResponse {
        try await request(Endpoints.transactionsPending) as PendingTransactionsResponse
    }

    func rejectPending(id: String) async throws {
        struct Empty: Decodable {}
        _ = try await request("\(Endpoints.transactionsPending)/\(id)", method: "DELETE") as Empty
    }

    func confirmPending(id: String, overrides: ConfirmPendingOverrides? = nil) async throws {
        struct Empty: Decodable {}
        if let overrides = overrides, !overrides.isEmpty {
            _ = try await request("\(Endpoints.transactionsPending)/\(id)/confirm", method: "POST", body: overrides) as Empty
        } else {
            _ = try await request("\(Endpoints.transactionsPending)/\(id)/confirm", method: "POST") as Empty
        }
    }

    func createTransaction(_ body: CreateTransactionBody) async throws -> Transaction {
        try await request(Endpoints.transactions, method: "POST", body: body) as Transaction
    }

    func getTransactions(limit: Int? = nil, cursor: String? = nil, month: String? = nil, year: String? = nil) async throws -> TransactionsListResponse {
        var query: [String: String] = [:]
        if let limit = limit { query["limit"] = String(limit) }
        if let cursor = cursor { query["cursor"] = cursor }
        if let month = month { query["month"] = month }
        if let year = year { query["year"] = year }
        return try await request(Endpoints.transactions, query: query.isEmpty ? nil : query) as TransactionsListResponse
    }

    func getTransaction(id: String) async throws -> Transaction {
        try await request("\(Endpoints.transactions)/\(id)") as Transaction
    }

    func updateTransaction(id: String, body: UpdateTransactionBody) async throws -> Transaction {
        try await request("\(Endpoints.transactions)/\(id)", method: "PATCH", body: body) as Transaction
    }

    func deleteTransaction(id: String) async throws {
        struct Empty: Decodable {}
        _ = try await request("\(Endpoints.transactions)/\(id)", method: "DELETE") as Empty
    }

    func getDashboard() async throws -> DashboardResponse {
        try await request(Endpoints.analyticsDashboard) as DashboardResponse
    }

    func getMonthlySummary(month: String?) async throws -> MonthlySummaryResponse {
        var query: [String: String]?
        if let month = month { query = ["month": month] }
        return try await request(Endpoints.insightsMonthlySummary, query: query) as MonthlySummaryResponse
    }

    func getBehavioralInsights() async throws -> [InsightItem] {
        try await request(Endpoints.insightsBehavioral) as [InsightItem]
    }

    func getMoneyMirror(month: String?) async throws -> MoneyMirrorResponse {
        var query: [String: String]?
        if let month = month { query = ["month": month] }
        return try await request(Endpoints.insightsMoneyMirror, query: query) as MoneyMirrorResponse
    }

    func getSubscriptions() async throws -> SubscriptionsResponse {
        try await request(Endpoints.subscriptions) as SubscriptionsResponse
    }

    func getEntitlements() async throws -> EntitlementsResponse {
        try await request(Endpoints.entitlements) as EntitlementsResponse
    }

    func registerOrLogin(externalId: String, email: String?) async throws -> AuthResponse {
        struct Body: Encodable {
            let externalId: String
            let email: String?
        }
        return try await request(Endpoints.authRegister, method: "POST", body: Body(externalId: externalId, email: email)) as AuthResponse
    }

    func loginWithApple(identityToken: String, email: String?) async throws -> AuthResponse {
        struct Body: Encodable {
            let identityToken: String
            let email: String?
        }
        return try await request(Endpoints.authApple, method: "POST", body: Body(identityToken: identityToken, email: email)) as AuthResponse
    }

    func syncBilling(productId: String?, transactionId: String?, expiresAt: String?) async throws -> EntitlementsResponse {
        struct Body: Encodable {
            let productId: String?
            let transactionId: String?
            let expiresAt: String?
        }
        return try await request(Endpoints.billingSync, method: "POST", body: Body(productId: productId, transactionId: transactionId, expiresAt: expiresAt)) as EntitlementsResponse
    }
}

// MARK: - Response types

struct ParseScreenshotResponse: Codable {
    let accepted: Int
    let duplicateSkipped: Int
    let pendingReview: Int
    let pendingIds: [String]
    let errors: [String]
    let reason: String?
    let aiAnalysesRemaining: Int?
    enum CodingKeys: String, CodingKey {
        case accepted, duplicateSkipped, pendingReview, pendingIds, errors, reason
        case aiAnalysesRemaining = "ai_analyses_remaining"
    }
}

struct PendingTransactionsResponse: Codable {
    let pending: [PendingTransaction]
}

struct CreateTransactionBody: Encodable {
    let type: String
    let amountOriginal: Double
    let currencyOriginal: String
    let amountBase: Double
    let baseCurrency: String
    let merchant: String?
    let title: String?
    let transactionDate: String
    let transactionTime: String?
    let category: String
    let subcategory: String?
    let isSubscription: Bool?
    let subscriptionInterval: String?
    let comment: String?
    let sourceType: String?
}

struct UpdateTransactionBody: Encodable {
    let amountOriginal: Double?
    let amountBase: Double?
    let merchant: String?
    let category: String?
    let subcategory: String?
    let transactionDate: String?
    let isSubscription: Bool?
    let subscriptionInterval: String?
    let comment: String?
}

/// Optional overrides when confirming a pending transaction (edit-before-confirm).
struct ConfirmPendingOverrides: Encodable {
    var type: String?
    var amountOriginal: Double?
    var currencyOriginal: String?
    var amountBase: Double?
    var baseCurrency: String?
    var merchant: String?
    var transactionDate: String?
    var transactionTime: String?
    var category: String?
    var subcategory: String?
    var subcategoryId: String?
    var isSubscription: Bool?
    var subscriptionInterval: String?

    init(type: String? = nil, amountOriginal: Double? = nil, currencyOriginal: String? = nil, amountBase: Double? = nil, baseCurrency: String? = nil, merchant: String? = nil, transactionDate: String? = nil, transactionTime: String? = nil, category: String? = nil, subcategory: String? = nil, subcategoryId: String? = nil, isSubscription: Bool? = nil, subscriptionInterval: String? = nil) {
        self.type = type
        self.amountOriginal = amountOriginal
        self.currencyOriginal = currencyOriginal
        self.amountBase = amountBase
        self.baseCurrency = baseCurrency
        self.merchant = merchant
        self.transactionDate = transactionDate
        self.transactionTime = transactionTime
        self.category = category
        self.subcategory = subcategory
        self.subcategoryId = subcategoryId
        self.isSubscription = isSubscription
        self.subscriptionInterval = subscriptionInterval
    }

    var isEmpty: Bool {
        type == nil && amountOriginal == nil && currencyOriginal == nil && amountBase == nil
            && baseCurrency == nil && merchant == nil && transactionDate == nil && transactionTime == nil
            && category == nil && subcategory == nil && subcategoryId == nil
            && isSubscription == nil && subscriptionInterval == nil
    }

    enum CodingKeys: String, CodingKey {
        case type, amountOriginal, currencyOriginal, amountBase, baseCurrency
        case merchant, transactionDate, transactionTime, category, subcategory, subcategoryId
        case isSubscription, subscriptionInterval
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let v = type { try c.encode(v, forKey: .type) }
        if let v = amountOriginal { try c.encode(v, forKey: .amountOriginal) }
        if let v = currencyOriginal { try c.encode(v, forKey: .currencyOriginal) }
        if let v = amountBase { try c.encode(v, forKey: .amountBase) }
        if let v = baseCurrency { try c.encode(v, forKey: .baseCurrency) }
        if let v = merchant { try c.encode(v, forKey: .merchant) }
        if let v = transactionDate { try c.encode(v, forKey: .transactionDate) }
        if let v = transactionTime { try c.encode(v, forKey: .transactionTime) }
        if let v = category { try c.encode(v, forKey: .category) }
        if let v = subcategory { try c.encode(v, forKey: .subcategory) }
        if let v = subcategoryId { try c.encode(v, forKey: .subcategoryId) }
        if let v = isSubscription { try c.encode(v, forKey: .isSubscription) }
        if let v = subscriptionInterval { try c.encode(v, forKey: .subscriptionInterval) }
    }
}

struct Transaction: Codable, Identifiable, Hashable {
    let id: String
    let type: String
    let amountOriginal: Double
    let currencyOriginal: String
    let amountBase: Double
    let baseCurrency: String
    let merchant: String?
    let title: String?
    let transactionDate: String
    let transactionTime: String?
    let category: String
    let subcategory: String?
    let isSubscription: Bool?
    let subscriptionInterval: String?
    let sourceType: String?
    let createdAt: String?
    let updatedAt: String?

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Transaction, rhs: Transaction) -> Bool { lhs.id == rhs.id }
}

struct TransactionsListResponse: Codable {
    let transactions: [Transaction]
    let nextCursor: String?
    let hasMore: Bool?
}

struct PendingTransaction: Codable, Identifiable, Equatable {
    let id: String
    let payload: [String: AnyCodable]?
    let confidence: Double?
    let reason: String?
    /// Pre-decoded payload; populated at construction time to avoid repeated JSON decode.
    let cachedPayload: PendingTransactionPayload?

    var decodedPayload: PendingTransactionPayload? { cachedPayload }

    // Exclude cachedPayload from Codable so existing JSON decoding paths are unaffected.
    enum CodingKeys: String, CodingKey {
        case id, payload, confidence, reason
    }

    init(id: String, payload: [String: AnyCodable]?, confidence: Double?, reason: String?, cachedPayload: PendingTransactionPayload? = nil) {
        self.id = id
        self.payload = payload
        self.confidence = confidence
        self.reason = reason
        self.cachedPayload = cachedPayload
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        payload = try c.decodeIfPresent([String: AnyCodable].self, forKey: .payload)
        confidence = try c.decodeIfPresent(Double.self, forKey: .confidence)
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        // Decode payload lazily for API path (rare); local path uses cachedPayload directly.
        if let p = payload {
            let dict = p.mapValues(\.value)
            if let data = try? JSONSerialization.data(withJSONObject: dict) {
                cachedPayload = try? JSONDecoder().decode(PendingTransactionPayload.self, from: data)
            } else { cachedPayload = nil }
        } else { cachedPayload = nil }
    }

    // Payload is immutable once created; id equality is sufficient.
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

/// Typed shape of pending transaction payload from backend (all optional for robustness).
struct PendingTransactionPayload: Codable, Equatable {
    let type: String?
    let amountOriginal: Double?
    let currencyOriginal: String?
    let amountBase: Double?
    let baseCurrency: String?
    let merchant: String?
    let title: String?
    let transactionDate: String?
    let transactionTime: String?
    let category: String?
    let subcategory: String?
    /// When set, show "Possible duplicate of …" in review (probable duplicate of saved transaction).
    let probableDuplicateOfId: String?

    init(
        type: String? = nil,
        amountOriginal: Double? = nil,
        currencyOriginal: String? = nil,
        amountBase: Double? = nil,
        baseCurrency: String? = nil,
        merchant: String? = nil,
        title: String? = nil,
        transactionDate: String? = nil,
        transactionTime: String? = nil,
        category: String? = nil,
        subcategory: String? = nil,
        probableDuplicateOfId: String? = nil
    ) {
        self.type = type
        self.amountOriginal = amountOriginal
        self.currencyOriginal = currencyOriginal
        self.amountBase = amountBase
        self.baseCurrency = baseCurrency
        self.merchant = merchant
        self.title = title
        self.transactionDate = transactionDate
        self.transactionTime = transactionTime
        self.category = category
        self.subcategory = subcategory
        self.probableDuplicateOfId = probableDuplicateOfId
    }
}

struct DashboardResponse: Codable {
    let thisMonth: MonthSummary
    let previousMonthSpent: Double
    let deltaPercent: Double
}

struct MonthSummary: Codable {
    let totalSpent: Double
    let totalIncome: Double
    let byCategory: [String: Double]?
    let transactionCount: Int?
}

struct MonthlySummaryResponse: Codable {
    let summary: String
    let details: [String]
    let deltaPercent: Double
}

struct InsightItem: Codable {
    let type: String?
    let title: String
    let body: String
    let metricRef: String?
}

struct MoneyMirrorResponse: Codable {
    let behavioral: [InsightItem]
    let anomalies: [AnomalyItem]
    let summary: String?
}

struct AnomalyItem: Codable {
    let category: String
    let currentAmount: Double
    let averageAmount: Double
    let ratio: Double
}

struct SubscriptionsResponse: Codable {
    let subscriptions: [Subscription]
}

struct Subscription: Codable, Identifiable {
    let id: String
    let merchant: String
    let amount: Double
    let currency: String
    let interval: String
    let nextBillingDate: String?
    let status: String
    /// Local only: id of the template transaction to update when a payment is recorded.
    let templateTransactionId: String?
    /// Local only: category id for icon and display name.
    let categoryId: String?
    /// Local only: subcategory id for icon and display name.
    let subcategoryId: String?
    /// Local only: description/title added to the product (transaction).
    let title: String?
    /// Local only: custom icon letter for display (default: first letter of merchant).
    let iconLetter: String?
    /// Local only: custom hex color for icon (default: merchantColor mapping).
    let colorHex: String?

    enum CodingKeys: String, CodingKey {
        case id, merchant, amount, currency, interval, nextBillingDate, status
        case templateTransactionId
        case categoryId
        case subcategoryId
        case title
        case iconLetter
        case colorHex
    }

    init(id: String, merchant: String, amount: Double, currency: String, interval: String, nextBillingDate: String?, status: String, templateTransactionId: String? = nil, categoryId: String? = nil, subcategoryId: String? = nil, title: String? = nil, iconLetter: String? = nil, colorHex: String? = nil) {
        self.id = id
        self.merchant = merchant
        self.amount = amount
        self.currency = currency
        self.interval = interval
        self.nextBillingDate = nextBillingDate
        self.status = status
        self.templateTransactionId = templateTransactionId
        self.categoryId = categoryId
        self.subcategoryId = subcategoryId
        self.title = title
        self.iconLetter = iconLetter
        self.colorHex = colorHex
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        merchant = try c.decode(String.self, forKey: .merchant)
        amount = try c.decode(Double.self, forKey: .amount)
        currency = try c.decode(String.self, forKey: .currency)
        interval = try c.decode(String.self, forKey: .interval)
        nextBillingDate = try c.decodeIfPresent(String.self, forKey: .nextBillingDate)
        status = try c.decode(String.self, forKey: .status)
        templateTransactionId = try c.decodeIfPresent(String.self, forKey: .templateTransactionId)
        categoryId = try c.decodeIfPresent(String.self, forKey: .categoryId)
        subcategoryId = try c.decodeIfPresent(String.self, forKey: .subcategoryId)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        iconLetter = try c.decodeIfPresent(String.self, forKey: .iconLetter)
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(merchant, forKey: .merchant)
        try c.encode(amount, forKey: .amount)
        try c.encode(currency, forKey: .currency)
        try c.encode(interval, forKey: .interval)
        try c.encodeIfPresent(nextBillingDate, forKey: .nextBillingDate)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(templateTransactionId, forKey: .templateTransactionId)
        try c.encodeIfPresent(categoryId, forKey: .categoryId)
        try c.encodeIfPresent(subcategoryId, forKey: .subcategoryId)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(iconLetter, forKey: .iconLetter)
        try c.encodeIfPresent(colorHex, forKey: .colorHex)
    }
}

struct EntitlementsResponse: Codable {
    let monthlyAiLimit: Int?
    let unlimitedAiAnalysis: Bool?
    let advancedInsights: Bool?
    let subscriptionsDashboard: Bool?
    let yearlyReview: Bool?
    let exportExtended: Bool?
    let cloudSync: Bool?
    enum CodingKeys: String, CodingKey {
        case monthlyAiLimit = "monthly_ai_limit"
        case unlimitedAiAnalysis = "unlimited_ai_analysis"
        case advancedInsights = "advanced_insights"
        case subscriptionsDashboard = "subscriptions_dashboard"
        case yearlyReview = "yearly_review"
        case exportExtended = "export_extended"
        case cloudSync = "cloud_sync"
    }
}

struct AuthResponse: Codable {
    let token: String
    let user: AuthUser
}

struct AuthUser: Codable {
    let id: String
    let email: String?
}

enum APIError: Error {
    case invalidResponse
    case http(statusCode: Int, message: String)
    case paymentRequired(String)
}

struct APIErrorBody: Codable {
    let error: String?
    let code: String?
}

struct AnyEncodable: Encodable {
    private let encode: (Encoder) throws -> Void
    init<T: Encodable>(_ value: T) {
        encode = value.encode
    }
    func encode(to encoder: Encoder) throws { try encode(encoder) }
}

struct AnyCodable: Codable {
    let value: Any
    init(_ value: Any) { self.value = value }
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let d = try? container.decode(Double.self) { value = d }
        else if let s = try? container.decode(String.self) { value = s }
        else if let b = try? container.decode(Bool.self) { value = b }
        else if let a = try? container.decode([AnyCodable].self) { value = a.map(\.value) }
        else if let o = try? container.decode([String: AnyCodable].self) { value = Dictionary(uniqueKeysWithValues: o.map { ($0.key, $0.value.value) }) }
        else { value = NSNull() }
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let d as Double: try container.encode(d)
        case let s as String: try container.encode(s)
        case let b as Bool: try container.encode(b)
        default: try container.encodeNil()
        }
    }
}
