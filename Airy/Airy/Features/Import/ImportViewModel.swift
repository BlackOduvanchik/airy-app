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

    func processImages(_ items: [PhotosPickerItem]) async {
        var images: [UIImage] = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { continue }
            images.append(image)
        }
        guard !images.isEmpty else {
            await MainActor.run { resultMessage = "Could not load images" }
            return
        }
        await processImagesDirect(images)
    }

    private func processImagesDirect(_ images: [UIImage]) async {
        isProcessing = true
        resultMessage = nil
        errorMessage = nil
        pendingCount = 0
        defer { Task { @MainActor in isProcessing = false } }
        var totalAdded = 0
        for image in images {
            do {
                let ocrText = try await ocrService.recognizeText(from: image)
                let hash = ocrService.imageHash(for: image)
                let parsed = parser.parse(ocrText: ocrText, baseCurrency: "USD")
                if parsed.isEmpty && !ocrText.trimmingCharacters(in: .whitespaces).isEmpty {
                    continue
                }
                for item in parsed {
                    let isDup = await MainActor.run {
                        LocalDataStore.shared.isExactDuplicateTransaction(
                            merchant: item.merchant,
                            date: item.date,
                            amount: item.amount
                        )
                    }
                    if isDup { continue }
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
                    totalAdded += 1
                }
            } catch {
                await MainActor.run {
                    resultMessage = error.localizedDescription
                    errorMessage = error.localizedDescription
                }
                return
            }
        }
        let count = totalAdded
        await MainActor.run {
            resultMessage = "Found \(count) transaction(s). Review in Pending."
            pendingCount = count
        }
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

            let parsed = parser.parse(ocrText: ocrText, baseCurrency: "USD")

            if parsed.isEmpty && !ocrText.trimmingCharacters(in: .whitespaces).isEmpty {
                await MainActor.run {
                    resultMessage = "No transactions found in image"
                }
                return
            }

            var addedCount = 0
            for item in parsed {
                let isDup = await MainActor.run {
                    LocalDataStore.shared.isExactDuplicateTransaction(
                        merchant: item.merchant,
                        date: item.date,
                        amount: item.amount
                    )
                }
                if isDup { continue }

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
                addedCount += 1
            }

            let count = addedCount
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

    /// Pending data for add-on-confirm; set by processImageReturningItems, consumed by addProcessedToPending.
    private(set) var pendingToAdd: (items: [ParsedTransactionItem], hash: String, ocrText: String)?
    /// Batches for multi-image; set by processImagesReturningItems.
    private(set) var pendingToAddBatches: [(items: [ParsedTransactionItem], hash: String, ocrText: String)]?


    /// Processes image, returns parsed items for display. Does NOT add to pending until addProcessedToPending.
    func processImageReturningItems(_ image: UIImage) async -> [ParsedTransactionItem] {
        isProcessing = true
        defer { Task { @MainActor in isProcessing = false } }
        return await processImageReturningItemsInternal(image)
    }

    /// Processes multiple images, returns combined items. Does NOT add to pending until addProcessedToPending.
    func processImagesReturningItems(_ images: [UIImage]) async -> [ParsedTransactionItem] {
        isProcessing = true
        defer { Task { @MainActor in isProcessing = false } }
        var allItems: [ParsedTransactionItem] = []
        var batches: [(items: [ParsedTransactionItem], hash: String, ocrText: String)] = []
        for image in images {
            let items = await processImageReturningItemsInternal(image)
            allItems.append(contentsOf: items)
            if let p = pendingToAdd {
                batches.append(p)
            }
        }
        let batchesCopy = batches
        let allItemsCount = allItems.count
        await MainActor.run {
            pendingToAdd = nil
            pendingToAddBatches = batchesCopy.isEmpty ? nil : batchesCopy
            pendingCount = allItemsCount
        }
        return allItems
    }

    private func processImageReturningItemsInternal(_ image: UIImage) async -> [ParsedTransactionItem] {
        resultMessage = nil
        errorMessage = nil
        pendingCount = 0
        pendingToAdd = nil
        do {
            let ocrText = try await ocrService.recognizeText(from: image)
            let hash = await Task.detached(priority: .userInitiated) { [ocrService = self.ocrService] in
                ocrService.imageHash(for: image)
            }.value
            var parsed = parser.parse(ocrText: ocrText, baseCurrency: "USD")
            for i in parsed.indices {
                if let corrected = MerchantCorrectionStore.shared.lookup(
                    amount: parsed[i].amount,
                    date: parsed[i].date,
                    originalMerchant: parsed[i].merchant
                ) {
                    parsed[i].merchant = corrected
                }
            }
            if parsed.isEmpty && !ocrText.trimmingCharacters(in: .whitespaces).isEmpty {
                await MainActor.run { resultMessage = "No transactions found in image" }
                return []
            }
            let parsedCopy = parsed
            let itemsToAdd = await MainActor.run {
                parsedCopy.filter { item in
                    !LocalDataStore.shared.isExactDuplicateTransaction(
                        merchant: item.merchant,
                        date: item.date,
                        amount: item.amount
                    )
                }
            }
            await MainActor.run {
                resultMessage = "Found \(itemsToAdd.count) transaction(s). Review in Pending."
                pendingCount = itemsToAdd.count
                pendingToAdd = (itemsToAdd, hash, ocrText)
                ParsingRulesStore.shared.lastOcrSample = String(ocrText.prefix(4000))
            }
            return itemsToAdd
        } catch {
            await MainActor.run {
                resultMessage = error.localizedDescription
                errorMessage = error.localizedDescription
            }
            return []
        }
    }

    /// Adds the last processed items to pending. Call when user taps Confirm.
    @MainActor
    func addProcessedToPending() {
        if let batches = pendingToAddBatches {
            for p in batches {
                for item in p.items {
                    if LocalDataStore.shared.isExactDuplicateTransaction(
                        merchant: item.merchant,
                        date: item.date,
                        amount: item.amount
                    ) { continue }
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
                    LocalDataStore.shared.addPendingTransaction(
                        payload: payload,
                        ocrText: String(p.ocrText.prefix(2000)),
                        sourceImageHash: p.hash
                    )
                }
            }
            pendingToAddBatches = nil
            return
        }
        guard let p = pendingToAdd else { return }
        for item in p.items {
            if LocalDataStore.shared.isExactDuplicateTransaction(
                merchant: item.merchant,
                date: item.date,
                amount: item.amount
            ) { continue }

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
            LocalDataStore.shared.addPendingTransaction(
                payload: payload,
                ocrText: String(p.ocrText.prefix(2000)),
                sourceImageHash: p.hash
            )
        }
        pendingToAdd = nil
    }
}
