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

    /// Set when analyzing screen runs in a detached task; not cancelled when view disappears.
    var analyzingItems: [ParsedTransactionItem]? = nil
    var isAnalyzing: Bool = false

    private let ocrService = OCRService()
    private let parser = LocalOCRParser()
    private let gptService = GPTRulesService()

    /// Generic labels that must not be used as merchant; replaced with "Other".
    private static let genericMerchantValues: Set<String> = [
        "покупка", "purchase", "payment", "transaction", "оплата", "withdrawal",
        "payout", "transfer", "purchase", "sale", "expense", "withdrawal", "payment"
    ]

    /// Returns "Other" if merchant is nil, empty, or a generic label; otherwise returns trimmed merchant.
    private static func normalizeMerchant(_ raw: String?) -> String? {
        let s = (raw ?? "").trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return "Other" }
        if genericMerchantValues.contains(s.lowercased()) { return "Other" }
        return s
    }

    /// Apply saved category rule for this merchant (from "Remember rule" in Review); otherwise use item's category.
    private static func effectiveCategory(for item: ParsedTransactionItem) -> (category: String, subcategory: String?) {
        let cat = MerchantCategoryRuleStore.shared.categoryId(for: item.merchant) ?? item.categoryId ?? "other"
        let sub = MerchantCategoryRuleStore.shared.subcategoryId(for: item.merchant) ?? item.subcategoryId
        return (cat, sub)
    }

    /// Store expense as positive magnitude; income as-is. Dashboard expects positive amounts for spending.
    private static func storedAmount(amount: Double, isCredit: Bool) -> Double {
        let result = isCredit ? amount : abs(amount)
        // #region agent log
        if !isCredit && amount < 0 {
            let payload: [String: Any] = [
                "sessionId": "ad783c", "location": "ImportViewModel.storedAmount", "message": "expense normalized",
                "data": ["raw": amount, "stored": result], "timestamp": Int(Date().timeIntervalSince1970 * 1000), "hypothesisId": "H2"
            ]
            if let json = try? JSONSerialization.data(withJSONObject: payload), let line = String(data: json, encoding: .utf8) {
                let path = "/Users/oduvanchik/Desktop/Airy/.cursor/debug-ad783c.log"
                let lineData = (line + "\n").data(using: .utf8)!
                if FileManager.default.fileExists(atPath: path), let h = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
                    defer { try? h.close() }; h.seekToEndOfFile(); h.write(lineData)
                } else { FileManager.default.createFile(atPath: path, contents: lineData, attributes: nil) }
            }
        }
        // #endregion
        return result
    }

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
                let (parsed, ocrText, hash) = try await recognizeAndParseOneImage(image)
                if parsed.isEmpty { continue }
                for item in parsed {
                    let amt = Self.storedAmount(amount: item.amount, isCredit: item.isCredit)
                    let isDup = await MainActor.run {
                        LocalDataStore.shared.isExactDuplicateTransaction(
                            merchant: item.merchant,
                            date: item.date,
                            amount: amt
                        )
                    }
                    if isDup { continue }
                    let (cat, sub) = Self.effectiveCategory(for: item)
                    let payload = PendingTransactionPayload(
                        type: item.isCredit ? "income" : "expense",
                        amountOriginal: amt,
                        currencyOriginal: item.currency,
                        amountBase: amt,
                        baseCurrency: item.currency,
                        merchant: item.merchant,
                        title: nil,
                        transactionDate: item.date,
                        transactionTime: item.time,
                        category: cat,
                        subcategory: sub
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
            let (parsed, ocrText, hash) = try await recognizeAndParseOneImage(image)

            if parsed.isEmpty {
                await MainActor.run { resultMessage = "No transactions found in image" }
                return
            }

            var addedCount = 0
            for item in parsed {
                let amt = Self.storedAmount(amount: item.amount, isCredit: item.isCredit)
                let isDup = await MainActor.run {
                    LocalDataStore.shared.isExactDuplicateTransaction(
                        merchant: item.merchant,
                        date: item.date,
                        amount: amt
                    )
                }
                if isDup { continue }
                let (cat, sub) = Self.effectiveCategory(for: item)
                let payload = PendingTransactionPayload(
                    type: item.isCredit ? "income" : "expense",
                    amountOriginal: amt,
                    currencyOriginal: item.currency,
                    amountBase: amt,
                    baseCurrency: item.currency,
                    merchant: item.merchant,
                    title: nil,
                    transactionDate: item.date,
                    transactionTime: item.time,
                    category: cat,
                    subcategory: sub
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
        await MainActor.run { errorMessage = nil; resultMessage = nil }
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

    /// Call from analyzing screen. Runs processing in a detached task so view lifecycle does not cancel the request.
    func startAnalyzing(images: [UIImage]) {
        Task { @MainActor in
            isAnalyzing = true
            analyzingItems = nil
            errorMessage = nil
            resultMessage = nil
        }
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let items = await self.processImagesReturningItems(images)
            await MainActor.run {
                self.analyzingItems = items
                self.isAnalyzing = false
            }
        }
    }

    private func processImageReturningItemsInternal(_ image: UIImage) async -> [ParsedTransactionItem] {
        resultMessage = nil
        errorMessage = nil
        pendingCount = 0
        pendingToAdd = nil
        do {
            let (parsed, ocrText, hash) = try await recognizeAndParseOneImage(image)
            guard !parsed.isEmpty else {
                await MainActor.run { resultMessage = "No transactions found in image" }
                return []
            }
            var items = parsed
            for i in items.indices {
                if let corrected = MerchantCorrectionStore.shared.lookup(
                    amount: items[i].amount,
                    date: items[i].date,
                    originalMerchant: items[i].merchant
                ) {
                    items[i].merchant = corrected
                }
            }
            let itemsCopy = items
            let itemsToAdd = await MainActor.run {
                itemsCopy.filter { item in
                    let amt = Self.storedAmount(amount: item.amount, isCredit: item.isCredit)
                    return !LocalDataStore.shared.isExactDuplicateTransaction(
                        merchant: item.merchant,
                        date: item.date,
                        amount: amt
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

    /// One image: OCR → check digits → cache by hash → try local rules, else GPT → return (items, ocrText, hash). Throws on no numbers or GPT failure.
    private func recognizeAndParseOneImage(_ image: UIImage) async throws -> (items: [ParsedTransactionItem], ocrText: String, hash: String) {
        let hash = ocrService.imageHash(for: image)
        if let cached = ParsingRulesStore.shared.cachedResult(forImageHash: hash), !cached.isEmpty {
            let ocrText = try await ocrService.recognizeText(from: image)
            let fromLocal = ParsingRulesStore.shared.tryMatch(ocrText: ocrText, parser: parser, baseCurrency: "USD") ?? []
            let merged = mergeParsedItems(base: cached, additional: fromLocal)
            if merged.count > cached.count {
                ParsingRulesStore.shared.cacheResult(merged, forImageHash: hash)
            }
            return (merged, ocrText, hash)
        }
        let ocrText = try await ocrService.recognizeText(from: image)
        if !OCRService.containsDecimalDigits(ocrText) {
            throw OCRServiceError.noNumbersInImage
        }
        if let local = ParsingRulesStore.shared.tryMatch(ocrText: ocrText, parser: parser, baseCurrency: "USD"), !local.isEmpty {
            return (local, ocrText, hash)
        }
        let categories = CategoryStore.load().map { (id: $0.id, name: $0.name) }
        let subcategories = SubcategoryStore.load().map { (id: $0.id, name: $0.name, parentCategoryId: $0.parentCategoryId) }
        let imageBase64 = image.jpegData(compressionQuality: 0.7).map { $0.base64EncodedString() } ?? ""
        let response: GPTExtractionResponse
        if !imageBase64.isEmpty {
            response = try await gptService.extractAndGetRulesFromImage(
                imageBase64: imageBase64,
                categories: categories,
                subcategories: subcategories,
                baseCurrency: "USD"
            )
        } else {
            response = try await gptService.extractAndGetRules(
                ocrText: ocrText,
                categories: categories,
                subcategories: subcategories,
                baseCurrency: "USD"
            )
        }
        if let rules = response.rules {
            ParsingRulesStore.shared.appendRuleSet(rules: rules, forOcrText: ocrText)
        } else {
            do {
                let rules = try await gptService.generateRules(ocrText: ocrText)
                ParsingRulesStore.shared.appendRuleSet(rules: rules, forOcrText: ocrText)
            } catch { /* keep transactions; rules not saved this time */ }
        }
        let deduped = deduplicateGPTTransactions(response.transactions)
        var items = deduped.map { tx in
            ParsedTransactionItem(
                amount: tx.amount,
                isCredit: tx.isCredit ?? false,
                currency: tx.currency ?? "USD",
                date: tx.date,
                time: tx.time,
                merchant: Self.normalizeMerchant(tx.merchant),
                categoryId: tx.categoryId,
                subcategoryId: tx.subcategoryId,
                isSubscription: tx.isSubscription
            )
        }
        let fromLocal = ParsingRulesStore.shared.tryMatch(ocrText: ocrText, parser: parser, baseCurrency: "USD") ?? []
        items = mergeParsedItems(base: items, additional: fromLocal)
        ParsingRulesStore.shared.cacheResult(items, forImageHash: hash)
        return (items, ocrText, hash)
    }

    /// Adds the last processed items to pending. Call when user taps Confirm.
    @MainActor
    func addProcessedToPending() {
        if let batches = pendingToAddBatches {
            for p in batches {
                for item in p.items {
                    let amt = Self.storedAmount(amount: item.amount, isCredit: item.isCredit)
                    if LocalDataStore.shared.isExactDuplicateTransaction(
                        merchant: item.merchant,
                        date: item.date,
                        amount: amt
                    ) { continue }
                    let (cat, sub) = Self.effectiveCategory(for: item)
                    let payload = PendingTransactionPayload(
                        type: item.isCredit ? "income" : "expense",
                        amountOriginal: amt,
                        currencyOriginal: item.currency,
                        amountBase: amt,
                        baseCurrency: item.currency,
                        merchant: item.merchant,
                        title: nil,
                        transactionDate: item.date,
                        transactionTime: item.time,
                        category: cat,
                        subcategory: sub
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
            let amt = Self.storedAmount(amount: item.amount, isCredit: item.isCredit)
            if LocalDataStore.shared.isExactDuplicateTransaction(
                merchant: item.merchant,
                date: item.date,
                amount: amt
            ) { continue }

            let (cat, sub) = Self.effectiveCategory(for: item)
            let payload = PendingTransactionPayload(
                type: item.isCredit ? "income" : "expense",
                amountOriginal: amt,
                currencyOriginal: item.currency,
                amountBase: amt,
                baseCurrency: item.currency,
                merchant: item.merchant,
                title: nil,
                transactionDate: item.date,
                transactionTime: item.time,
                category: cat,
                subcategory: sub
            )
            LocalDataStore.shared.addPendingTransaction(
                payload: payload,
                ocrText: String(p.ocrText.prefix(2000)),
                sourceImageHash: p.hash
            )
        }
        pendingToAdd = nil
    }

    /// Merge parsed lists: base + any item from additional that is not in base (by date, amount, merchant). Keeps order: base first, then new from additional.
    private func mergeParsedItems(base: [ParsedTransactionItem], additional: [ParsedTransactionItem]) -> [ParsedTransactionItem] {
        let baseKeys = Set(base.map { "\($0.date)|\(abs($0.amount))|\($0.merchant ?? "")" })
        var out = base
        for item in additional {
            let key = "\(item.date)|\(abs(item.amount))|\(item.merchant ?? "")"
            if !baseKeys.contains(key) {
                out.append(item)
            }
        }
        return out
    }

    /// Removes duplicates by (date, amount, merchant) so the same transaction does not appear twice in Live Extraction.
    private func deduplicateGPTTransactions(_ transactions: [GPTExtractionTransaction]) -> [GPTExtractionTransaction] {
        var seen = Set<String>()
        return transactions.filter { tx in
            let key = "\(tx.date)|\(tx.amount)|\(tx.merchant ?? "")"
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }
}
