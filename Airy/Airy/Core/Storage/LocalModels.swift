//
//  LocalModels.swift
//  Airy
//
//  SwiftData models for local-only storage. No backend.
//

import Foundation
import SwiftData

@Model
final class LocalTransaction {
    @Attribute(.unique) var id: String
    var type: String
    var amountOriginal: Double
    var currencyOriginal: String
    var amountBase: Double
    var baseCurrency: String
    var merchant: String?
    var title: String?
    var transactionDate: String
    var transactionTime: String?
    var category: String
    var subcategory: String?
    var isSubscription: Bool?
    var subscriptionInterval: String?
    var sourceType: String?
    var sourceImageHash: String?
    var subscriptionIconLetter: String?
    var subscriptionColorHex: String?
    var createdAt: Date
    var updatedAt: Date?

    init(
        id: String = UUID().uuidString,
        type: String,
        amountOriginal: Double,
        currencyOriginal: String,
        amountBase: Double,
        baseCurrency: String,
        merchant: String? = nil,
        title: String? = nil,
        transactionDate: String,
        transactionTime: String? = nil,
        category: String,
        subcategory: String? = nil,
        isSubscription: Bool? = nil,
        subscriptionInterval: String? = nil,
        sourceType: String? = nil,
        sourceImageHash: String? = nil,
        subscriptionIconLetter: String? = nil,
        subscriptionColorHex: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
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
        self.isSubscription = isSubscription
        self.subscriptionInterval = subscriptionInterval
        self.sourceType = sourceType
        self.sourceImageHash = sourceImageHash
        self.subscriptionIconLetter = subscriptionIconLetter
        self.subscriptionColorHex = subscriptionColorHex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func toTransaction() -> Transaction {
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return Transaction(
            id: id,
            type: type,
            amountOriginal: amountOriginal,
            currencyOriginal: currencyOriginal,
            amountBase: amountBase,
            baseCurrency: baseCurrency,
            merchant: merchant,
            title: title,
            transactionDate: transactionDate,
            transactionTime: transactionTime,
            category: category,
            subcategory: subcategory,
            isSubscription: isSubscription,
            subscriptionInterval: subscriptionInterval,
            sourceType: sourceType,
            createdAt: df.string(from: createdAt),
            updatedAt: updatedAt.map { df.string(from: $0) }
        )
    }
}

@Model
final class LocalPendingTransaction {
    @Attribute(.unique) var id: String
    var payloadData: Data?
    var ocrText: String?
    var sourceImageHash: String?
    /// Layout family id active when this pending transaction was extracted. Used to feed user
    /// feedback (confirm / correct) back to LayoutFamilyLearningStore.
    var sourceFamilyId: String?
    /// OCR template id used to extract this transaction. Non-nil → show "via template" badge.
    var sourceTemplateId: String?
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        payload: PendingTransactionPayload,
        ocrText: String? = nil,
        sourceImageHash: String? = nil,
        sourceFamilyId: String? = nil,
        sourceTemplateId: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.payloadData = (try? JSONEncoder().encode(payload)) ?? nil
        self.ocrText = ocrText
        self.sourceImageHash = sourceImageHash
        self.sourceFamilyId = sourceFamilyId
        self.sourceTemplateId = sourceTemplateId
        self.createdAt = createdAt
    }

    var decodedPayload: PendingTransactionPayload? {
        guard let data = payloadData else { return nil }
        return try? JSONDecoder().decode(PendingTransactionPayload.self, from: data)
    }

    func toPendingTransaction() -> PendingTransaction {
        var payloadDict: [String: AnyCodable]?
        if let p = decodedPayload {
            var d: [String: AnyCodable] = [:]
            if let v = p.type { d["type"] = AnyCodable(v) }
            if let v = p.amountOriginal { d["amountOriginal"] = AnyCodable(v) }
            if let v = p.currencyOriginal { d["currencyOriginal"] = AnyCodable(v) }
            if let v = p.amountBase { d["amountBase"] = AnyCodable(v) }
            if let v = p.baseCurrency { d["baseCurrency"] = AnyCodable(v) }
            if let v = p.merchant { d["merchant"] = AnyCodable(v) }
            if let v = p.transactionDate { d["transactionDate"] = AnyCodable(v) }
            if let v = p.transactionTime { d["transactionTime"] = AnyCodable(v) }
            if let v = p.category { d["category"] = AnyCodable(v) }
            if let v = p.subcategory { d["subcategory"] = AnyCodable(v) }
            if let v = p.probableDuplicateOfId { d["probableDuplicateOfId"] = AnyCodable(v) }
            if let v = p.extractedByTemplateId { d["extractedByTemplateId"] = AnyCodable(v) }
            payloadDict = d
        }
        return PendingTransaction(id: id, payload: payloadDict, confidence: nil, reason: nil)
    }
}
