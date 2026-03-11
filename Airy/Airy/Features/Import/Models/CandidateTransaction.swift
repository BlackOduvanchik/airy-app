//
//  CandidateTransaction.swift
//  Airy
//
//  Normalized transaction candidate for review. Includes confidence scores.
//

import Foundation

struct ConfidenceScores: Codable, Equatable {
    var amountConfidence: Double
    var dateConfidence: Double
    var merchantConfidence: Double
    var statusConfidence: Double
    var typeConfidence: Double
    var overallConfidence: Double

    static func defaultHigh() -> ConfidenceScores {
        ConfidenceScores(
            amountConfidence: 1,
            dateConfidence: 1,
            merchantConfidence: 1,
            statusConfidence: 1,
            typeConfidence: 1,
            overallConfidence: 1
        )
    }

    static func from(amount: Double, date: Double, merchant: Double, status: Double, type: Double) -> ConfidenceScores {
        let overall = amount * 0.3 + date * 0.2 + merchant * 0.25 + status * 0.1 + type * 0.15
        return ConfidenceScores(
            amountConfidence: amount,
            dateConfidence: date,
            merchantConfidence: merchant,
            statusConfidence: status,
            typeConfidence: type,
            overallConfidence: min(1, max(0, overall))
        )
    }
}

enum ConfidenceLevel {
    case high   // ≥ 0.85
    case medium // 0.5–0.85
    case low    // < 0.5

    static func from(_ score: Double) -> ConfidenceLevel {
        if score >= 0.85 { return .high }
        if score >= 0.5 { return .medium }
        return .low
    }
}

struct CandidateTransaction: Identifiable, Equatable {
    let id: UUID
    var amount: Double
    var currency: String
    var date: String
    var time: String?
    var merchant: String?
    var status: TransactionStatus
    var type: TransactionType
    var confidence: ConfidenceScores
    var sourceImageIndex: Int
    var sourceOcrSnippet: String?
    var isDuplicate: Bool

    init(
        id: UUID = UUID(),
        amount: Double,
        currency: String,
        date: String,
        time: String? = nil,
        merchant: String? = nil,
        status: TransactionStatus = .success,
        type: TransactionType = .expense,
        confidence: ConfidenceScores = .defaultHigh(),
        sourceImageIndex: Int = 0,
        sourceOcrSnippet: String? = nil,
        isDuplicate: Bool = false
    ) {
        self.id = id
        self.amount = amount
        self.currency = currency
        self.date = date
        self.time = time
        self.merchant = merchant
        self.status = status
        self.type = type
        self.confidence = confidence
        self.sourceImageIndex = sourceImageIndex
        self.sourceOcrSnippet = sourceOcrSnippet
        self.isDuplicate = isDuplicate
    }
}
