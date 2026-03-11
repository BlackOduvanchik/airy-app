//
//  ExtractionResult.swift
//  Airy
//
//  Output of the extraction pipeline.
//

import Foundation
import CoreGraphics

struct DocumentStructure {
    var blocks: [TextBlock]
}

struct TextBlock {
    var lines: [String]
    var boundingBox: CGRect?
}

struct ExtractionResult {
    var screenType: ScreenType
    var candidates: [CandidateTransaction]
    var duplicatesSkipped: Int
    var failedSkipped: Int
    var lowConfidenceCount: Int
    var ocrText: String
    var documentStructure: DocumentStructure?
}
