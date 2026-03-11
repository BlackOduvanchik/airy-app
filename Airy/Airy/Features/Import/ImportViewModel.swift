//
//  ImportViewModel.swift
//  Airy
//
//  Local-only: OCR + LocalOCRParser, store in SwiftData. No backend.
//

import SwiftUI
import PhotosUI
import UIKit

@Observable
final class ImportViewModel {
    var resultMessage: String?
    var pendingCount = 0
    var isProcessing = false
    var showPaywall = false
    var errorMessage: String?

    private let ocrService = OCRService()
    private let parser = LocalOCRParser()

    func processImage(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            await MainActor.run { resultMessage = "Could not load image" }
            return
        }
        await processImage(image)
    }

    func processImage(_ image: UIImage) async {
        isProcessing = true
        resultMessage = nil
        errorMessage = nil
        pendingCount = 0
        defer { Task { @MainActor in isProcessing = false } }
        do {
            let ocrText = try await ocrService.recognizeText(from: image)
            let hash = ocrService.imageHash(for: image)

            let isDup = await MainActor.run { LocalDataStore.shared.duplicateByHash(hash) }
            if isDup {
                await MainActor.run {
                    resultMessage = "Duplicate screenshot skipped"
                    pendingCount = 0
                }
                return
            }

            let parsed = parser.parse(ocrText: ocrText, baseCurrency: "USD")

            if parsed.isEmpty && !ocrText.trimmingCharacters(in: .whitespaces).isEmpty {
                await MainActor.run {
                    resultMessage = "No transactions found in image"
                }
                return
            }

            for item in parsed {
                let payload = PendingTransactionPayload(
                    type: item.isCredit ? "income" : "expense",
                    amountOriginal: item.amount,
                    currencyOriginal: item.currency,
                    amountBase: item.amount,
                    baseCurrency: item.currency,
                    merchant: item.merchant,
                    title: nil,
                    transactionDate: item.date,
                    transactionTime: item.time,
                    category: "other",
                    subcategory: nil
                )
                await MainActor.run {
                    LocalDataStore.shared.addPendingTransaction(
                        payload: payload,
                        ocrText: String(ocrText.prefix(2000)),
                        sourceImageHash: hash
                    )
                }
            }

            let count = parsed.count
            await MainActor.run {
                resultMessage = "Found \(count) transaction(s). Review in Pending."
                pendingCount = count
            }
        } catch {
            await MainActor.run {
                resultMessage = error.localizedDescription
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Attempts to process image from clipboard. Returns true if clipboard had an image.
    func processImageFromClipboard() async -> Bool {
        guard let image = UIPasteboard.general.image else {
            return false
        }
        await processImage(image)
        return true
    }
}
