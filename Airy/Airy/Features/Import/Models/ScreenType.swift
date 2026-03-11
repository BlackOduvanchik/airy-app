//
//  ScreenType.swift
//  Airy
//
//  Classifies screenshot into document type for parser selection.
//

import Foundation

enum ScreenType: String, Codable, CaseIterable {
    case singlePaymentConfirmation
    case transactionList
    case bankStatementLike
    case receipt
    case subscriptionReceipt
    case moneyTransfer
    case failedTransactionNotice
    case unknown
}
