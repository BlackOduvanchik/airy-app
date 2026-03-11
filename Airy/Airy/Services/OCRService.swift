//
//  OCRService.swift
//  Airy
//
//  On-device OCR using Vision; image hashing for duplicate detection.
//

import Foundation
import ImageIO
import UIKit
@preconcurrency import Vision

private extension CGImagePropertyOrientation {
    init(_ ui: UIImage.Orientation) {
        switch ui {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

enum OCRServiceError: Error {
    case noResults
    case visionError(Error)
}

final class OCRService {
    /// Recognizes text from image using Vision. Returns concatenated string of recognized lines.
    func recognizeText(from image: UIImage) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            // Run entire OCR on background: image.cgImage and handler.perform can block
            DispatchQueue.global(qos: .userInitiated).async {
                guard let cgImage = image.cgImage else {
                    continuation.resume(throwing: OCRServiceError.noResults)
                    return
                }
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
                let orientation = CGImagePropertyOrientation(image.imageOrientation)
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: OCRServiceError.visionError(error))
                }
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
