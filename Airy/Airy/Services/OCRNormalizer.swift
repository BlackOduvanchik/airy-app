//
//  OCRNormalizer.swift
//  Airy
//
//  Deterministic normalization after OCR: same input → same normalized text and fingerprints.
//

import Foundation
import CryptoKit

struct OCRNormalizer {
    /// Deterministic normalized OCR text: Unicode NFC, normalized line breaks and whitespace.
    static func normalizedOCRText(_ raw: String) -> String {
        raw
            .precomposedStringWithCompatibilityMapping
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: "\n")
            .map { line in
                line.trimmingCharacters(in: .whitespaces)
                    .split(separator: " ")
                    .joined(separator: " ")
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// Fingerprint of normalized OCR for cache/rule lookup.
    static func ocrFingerprint(normalizedText: String) -> String {
        let data = Data(normalizedText.utf8)
        let hash = SHA256.hash(data: data)
        return hash.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// Structural fingerprint (line count + length) so small OCR variance can still match.
    static func screenFingerprint(normalizedText: String) -> String {
        let lines = normalizedText.split(separator: "\n")
        let lineCount = lines.count
        let totalLen = normalizedText.count
        let firstChars = lines.prefix(20).map { $0.prefix(1).description }.joined()
        let data = Data("\(lineCount)|\(totalLen)|\(firstChars)".utf8)
        let hash = SHA256.hash(data: data)
        return hash.prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}
