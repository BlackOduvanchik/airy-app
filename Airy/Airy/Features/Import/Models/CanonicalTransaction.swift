//
//  CanonicalTransaction.swift
//  Airy
//
//  Deterministic pipeline output: normalized merchant, ISO date, confidence, status.
//  Replaces ParsedTransactionItem at pipeline boundary.
//

import Foundation

/// Source of extraction for this candidate (deterministic path vs fallback).
enum ExtractionSource: String, Codable {
    case localRule
    case cache
    case gpt
}

/// Canonical extracted transaction: single representation for rules, cache, duplicates.
struct CanonicalTransaction: Equatable {
    var normalizedMerchant: String
    var amountDecimal: Decimal
    var isoCurrency: String
    var isoDate: String
    var normalizedTime: String?
    var transactionStatus: TransactionStatus
    var transactionType: TransactionType
    var categoryId: String?
    var subcategoryId: String?
    var confidence: ConfidenceScores
    var reviewRequired: Bool
    var source: ExtractionSource

    /// Amount as Double for existing stores and UI.
    var amountDouble: Double {
        get { NSDecimalNumber(decimal: amountDecimal).doubleValue }
        set { amountDecimal = Decimal(newValue) }
    }

    /// Build from existing parser output; uses confirmed alias store for normalized merchant.
    static func from(
        _ item: ParsedTransactionItem,
        aliasStore: MerchantAliasStore,
        source: ExtractionSource
    ) -> CanonicalTransaction {
        let normalized = aliasStore.normalizeForPipeline(raw: item.merchant)
        let status: TransactionStatus = .success
        let type: TransactionType = item.isCredit ? .income : .expense
        let isoDate = AppFormatters.normalizeISODate(String(item.date.prefix(10)))
        return CanonicalTransaction(
            normalizedMerchant: normalized,
            amountDecimal: Decimal(item.amount),
            isoCurrency: item.currency,
            isoDate: isoDate,
            normalizedTime: item.time,
            transactionStatus: status,
            transactionType: type,
            categoryId: item.categoryId,
            subcategoryId: item.subcategoryId,
            confidence: .defaultHigh(),
            reviewRequired: false,
            source: source
        )
    }

    /// Convert to ParsedTransactionItem for existing pending/save flow.
    func toParsedTransactionItem() -> ParsedTransactionItem {
        ParsedTransactionItem(
            amount: amountDouble,
            isCredit: transactionType == .income,
            currency: isoCurrency,
            date: isoDate,
            time: normalizedTime,
            merchant: normalizedMerchant,
            categoryId: categoryId,
            subcategoryId: subcategoryId,
            isSubscription: nil
        )
    }
}
