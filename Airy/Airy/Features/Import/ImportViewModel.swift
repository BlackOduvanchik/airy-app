//
//  ImportViewModel.swift
//  Airy
//

import SwiftUI
import PhotosUI

@Observable
final class ImportViewModel {
    var resultMessage: String?
    var pendingCount = 0
    var isProcessing = false
    var showPaywall = false
    var errorMessage: String?

    private let ocrService = OCRService()

    func processImage(_ item: PhotosPickerItem) async {
        isProcessing = true
        resultMessage = nil
        errorMessage = nil
        pendingCount = 0
        defer { Task { @MainActor in isProcessing = false } }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                await MainActor.run { resultMessage = "Could not load image" }
                return
            }
            let ocrText = try await ocrService.recognizeText(from: image)
            let hash = ocrService.imageHash(for: image)
            let res = try await APIClient.shared.parseScreenshot(
                ocrText: ocrText,
                localHash: hash,
                baseCurrency: "USD",
                idempotencyKey: nil
            )
            await MainActor.run {
                resultMessage = "Accepted: \(res.accepted), Duplicates skipped: \(res.duplicateSkipped), Pending: \(res.pendingReview)"
                pendingCount = res.pendingIds.count
            }
        } catch APIError.paymentRequired {
            let entitlements = try? await APIClient.shared.getEntitlements()
            await MainActor.run {
                if entitlements?.unlimitedAiAnalysis != true { showPaywall = true }
            }
        } catch {
            await MainActor.run {
                resultMessage = error.localizedDescription
                errorMessage = error.localizedDescription
            }
        }
    }
}
