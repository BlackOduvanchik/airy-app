//
//  ExtractionPipeline.swift
//  Airy
//
//  OCR → number check → image hash cache → GPT Vision → cache result.
//  One image per run; always GPT, no local parsing.
//

import Foundation
import UIKit

// MARK: - Shared transaction model

struct ParsedTransactionItem: Equatable, Codable {
    var amount: Double
    var isCredit: Bool
    var currency: String
    var date: String
    var time: String?
    var merchant: String?
    var categoryId: String?
    var subcategoryId: String?
    var isSubscription: Bool?
    var subscriptionInterval: String?
}

// MARK: - Pipeline result

struct ExtractionPipelineResult {
    let items: [ParsedTransactionItem]
    let imageHash: String
    let ocrTextRaw: String
}

// MARK: - Pipeline

final class ExtractionPipeline {
    private let ocrService = OCRService()
    private let gptService = GPTRulesService()
    private let aliasStore = MerchantAliasStore.shared

    /// Run full pipeline for one image. Throws on OCR/network errors.
    func run(image: UIImage, baseCurrency: String = "USD") async throws -> ExtractionPipelineResult {
        // 1. Image hash
        let imageHash = ocrService.imageHash(for: image)

        // 2. OCR
        let ocrTextRaw = try await ocrService.recognizeText(from: image)
        guard OCRService.containsDecimalDigits(ocrTextRaw) else {
            throw OCRServiceError.noNumbersInImage
        }

        // 3. Cache hit → return immediately
        if let cached = ImageHashCacheStore.shared.cachedResult(forImageHash: imageHash), !cached.isEmpty {
            print("[Extraction] ✅ Cache hit for hash \(imageHash.prefix(8))… → \(cached.count) item(s)")
            return ExtractionPipelineResult(items: cached, imageHash: imageHash, ocrTextRaw: ocrTextRaw)
        }

        // 4. Send to GPT (cap categories to prevent prompt bloat)
        let categories = CategoryStore.load().prefix(50).map { (id: $0.id, name: $0.name) }
        let subcategories = SubcategoryStore.load().prefix(150).map { (id: $0.id, name: $0.name, parentCategoryId: $0.parentCategoryId) }
        let imageBase64 = await Task.detached { image.jpegData(compressionQuality: 0.7)?.base64EncodedString() ?? "" }.value

        let response = try await gptService.extractTransactionsFromImage(
            imageBase64: imageBase64,
            ocrText: ocrTextRaw,
            categories: categories,
            subcategories: subcategories,
            baseCurrency: baseCurrency
        )

        // 5. Map → dedup → normalize merchants → alias corrections
        print("[Extraction] GPT returned \(response.transactions.count) transaction(s)")
        let deduped = deduplicateGPTTransactions(response.transactions)
        let successOnly = deduped.filter { $0.isSuccessStatus }
        if deduped.count != response.transactions.count || successOnly.count != deduped.count {
            print("[Extraction] After dedup: \(deduped.count), after status filter: \(successOnly.count)")
        }
        if successOnly.count < deduped.count {
            let rejected = deduped.filter { !$0.isSuccessStatus }
            let statuses = rejected.map { $0.transactionStatus ?? "nil" }
            print("[Extraction] ❌ Rejected statuses: \(statuses)")
        }
        var items = successOnly.map { tx in
            ParsedTransactionItem(
                amount: tx.amount,
                isCredit: tx.isCredit ?? false,
                currency: tx.currency ?? baseCurrency,
                date: tx.date,
                time: tx.time,
                merchant: ImportViewModel.normalizeMerchant(tx.merchant),
                categoryId: tx.categoryId,
                subcategoryId: tx.subcategoryId,
                isSubscription: tx.isSubscription,
                subscriptionInterval: tx.subscriptionInterval
            )
        }
        items = ImportViewModel.normalizeMerchantsInItems(items)
        for i in items.indices {
            if let corrected = aliasStore.resolveToNormalizedMerchant(raw: items[i].merchant) {
                items[i].merchant = corrected
            }
        }

        // 6. Cache (skip if any item has zero amount — likely a GPT extraction error)
        let hasZeroAmount = items.contains { $0.amount == 0 }
        if !hasZeroAmount {
            ImageHashCacheStore.shared.cacheResult(items, forImageHash: imageHash)
        }
        if items.isEmpty {
            print("[Extraction] ⚠️ Pipeline produced 0 items from GPT response of \(response.transactions.count) transaction(s)")
        } else {
            print("[Extraction] ✅ Pipeline done: \(items.count) item(s), cached: \(!hasZeroAmount)")
        }

        return ExtractionPipelineResult(items: items, imageHash: imageHash, ocrTextRaw: ocrTextRaw)
    }

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
