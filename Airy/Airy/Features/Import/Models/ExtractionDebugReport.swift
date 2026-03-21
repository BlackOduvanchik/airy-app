//
//  ExtractionDebugReport.swift
//  Airy
//
//  Minimal extraction debug report for per-screenshot observability.
//

import Foundation

enum ExtractionSourceForReport: String {
    case cache
    case gptVision
    case none
}

enum ExtractionStatus: String {
    case complete
    case failed
}

/// Per-screenshot debug report for observability.
struct ExtractionDebugReport: Identifiable {
    let id: UUID
    let imageIndex: Int
    let source: ExtractionSourceForReport
    let imageSentToGPT: Bool
    let extractedTransactions: Int
    let removedByDuplicate: Int
    let finallyShown: Int
    let imageHashPrefix: String?

    init(
        id: UUID = UUID(),
        imageIndex: Int,
        source: ExtractionSourceForReport,
        imageSentToGPT: Bool,
        extractedTransactions: Int,
        removedByDuplicate: Int,
        finallyShown: Int,
        imageHashPrefix: String?
    ) {
        self.id = id
        self.imageIndex = imageIndex
        self.source = source
        self.imageSentToGPT = imageSentToGPT
        self.extractedTransactions = extractedTransactions
        self.removedByDuplicate = removedByDuplicate
        self.finallyShown = finallyShown
        self.imageHashPrefix = imageHashPrefix
    }
}
