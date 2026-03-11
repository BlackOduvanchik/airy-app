//
//  TransactionStatus.swift
//  Airy
//
//  Transaction execution status. Failed/declined must not be auto-saved as spending.
//

import Foundation

enum TransactionStatus: String, Codable {
    case success
    case failed
    case pending
    case reversed
    case informational
}
