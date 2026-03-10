//
//  OCRService.swift
//  Airy
//
//  On-device OCR using Vision; image hashing for duplicate detection.
//

import Foundation
import UIKit
import Vision

enum OCRServiceError: Error {
    case noResults
    case visionError(Error)
}

final class OCRService {
    /// Recognizes text from image using Vision. Returns concatenated string of recognized lines.
    func recognizeText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else { throw OCRServiceError.noResults }
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: OCRServiceError.visionError(error))
                    return
                }
                let results = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = results.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OCRServiceError.visionError(error))
            }
        }
    }

    /// Stable hash for duplicate detection (e.g. same screenshot).
    func imageHash(for image: UIImage) -> String {
        let data = image.jpegData(compressionQuality: 0.5) ?? Data()
        return data.sha256Hex
    }
}

import CryptoKit

private extension Data {
    var sha256Hex: String {
        let hash = SHA256.hash(data: self)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
