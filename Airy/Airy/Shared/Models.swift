//
//  Models.swift
//  Airy
//
//  Shared data models used across the app. Local-only.
//

import Foundation

// MARK: - Transaction

struct Transaction: Codable, Identifiable, Hashable, Sendable {
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

// MARK: - UpdateTransactionBody

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

// MARK: - PendingTransaction

struct PendingTransaction: Codable, Identifiable, Equatable {
    let id: String
    let payload: [String: AnyCodable]?
    let confidence: Double?
    let reason: String?
    /// Pre-decoded payload; populated at construction time to avoid repeated JSON decode.
    let cachedPayload: PendingTransactionPayload?

    var decodedPayload: PendingTransactionPayload? { cachedPayload }

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
        if let p = payload {
            let dict = p.mapValues(\.value)
            if let data = try? JSONSerialization.data(withJSONObject: dict) {
                cachedPayload = try? JSONDecoder().decode(PendingTransactionPayload.self, from: data)
            } else { cachedPayload = nil }
        } else { cachedPayload = nil }
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

// MARK: - PendingTransactionPayload

/// Typed shape of pending transaction payload (all optional for robustness).
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
    let probableDuplicateOfId: String?

    init(
        type: String? = nil, amountOriginal: Double? = nil, currencyOriginal: String? = nil,
        amountBase: Double? = nil, baseCurrency: String? = nil, merchant: String? = nil,
        title: String? = nil, transactionDate: String? = nil, transactionTime: String? = nil,
        category: String? = nil, subcategory: String? = nil, probableDuplicateOfId: String? = nil
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

// MARK: - Subscription

struct Subscription: Codable, Identifiable, Sendable {
    let id: String
    let merchant: String
    let amount: Double
    let currency: String
    let interval: String
    let nextBillingDate: String?
    let status: String
    let templateTransactionId: String?
    let categoryId: String?
    let subcategoryId: String?
    let title: String?
    let iconLetter: String?
    let colorHex: String?

    enum CodingKeys: String, CodingKey {
        case id, merchant, amount, currency, interval, nextBillingDate, status
        case templateTransactionId, categoryId, subcategoryId, title, iconLetter, colorHex
    }

    init(id: String, merchant: String, amount: Double, currency: String, interval: String,
         nextBillingDate: String?, status: String, templateTransactionId: String? = nil,
         categoryId: String? = nil, subcategoryId: String? = nil, title: String? = nil,
         iconLetter: String? = nil, colorHex: String? = nil) {
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

// MARK: - ConfirmPendingOverrides

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

    init(type: String? = nil, amountOriginal: Double? = nil, currencyOriginal: String? = nil,
         amountBase: Double? = nil, baseCurrency: String? = nil, merchant: String? = nil,
         transactionDate: String? = nil, transactionTime: String? = nil, category: String? = nil,
         subcategory: String? = nil, subcategoryId: String? = nil, isSubscription: Bool? = nil,
         subscriptionInterval: String? = nil) {
        self.type = type; self.amountOriginal = amountOriginal; self.currencyOriginal = currencyOriginal
        self.amountBase = amountBase; self.baseCurrency = baseCurrency; self.merchant = merchant
        self.transactionDate = transactionDate; self.transactionTime = transactionTime
        self.category = category; self.subcategory = subcategory; self.subcategoryId = subcategoryId
        self.isSubscription = isSubscription; self.subscriptionInterval = subscriptionInterval
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

// MARK: - CreateTransactionBody

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

// MARK: - AnyCodable

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
