//
//  TransactionType.swift
//  Airy
//
//  Income vs expense vs transfer classification.
//

import Foundation

enum TransactionType: String, Codable {
    case expense
    case income
    case transfer
    case unknown
}
