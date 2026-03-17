//
//  ExtractionPipeline.swift
//  Airy
//
//  Deterministic order: OCR → normalize → local rules → cache → single-image GPT fallback.
//  One image per run; no batch GPT.
//

import Foundation
import UIKit

struct ExtractionPipelineResult {
    let items: [ParsedTransactionItem]
    let imageHash: String
    let normalizedOCRText: String
    let ocrFingerprint: String
    let screenFingerprint: String
    let ocrTextRaw: String
}

final class ExtractionPipeline {
    private let ocrService = OCRService()
    private let parser = LocalOCRParser()
    private let gptService = GPTRulesService()
    private let aliasStore = MerchantAliasStore.shared

    /// Run full pipeline for one image. Returns items (empty if no numbers in image); throws on OCR/network errors.
    func run(image: UIImage, baseCurrency: String = "USD") async throws -> ExtractionPipelineResult {
        let imageHash = ocrService.imageHash(for: image)
        let ocrTextRaw = try await ocrService.recognizeText(from: image)
        guard OCRService.containsDecimalDigits(ocrTextRaw) else {
            throw OCRServiceError.noNumbersInImage
        }

        let normalizedOCRText = OCRNormalizer.normalizedOCRText(ocrTextRaw)
        let ocrFingerprint = OCRNormalizer.ocrFingerprint(normalizedText: normalizedOCRText)
        let screenFingerprint = OCRNormalizer.screenFingerprint(normalizedText: normalizedOCRText)

        if let cached = ParsingRulesStore.shared.cachedResult(forImageHash: imageHash), !cached.isEmpty {
            let result = ExtractionRulesMatcher.tryStructuredThenLegacyWithOutcome(ocrText: normalizedOCRText, parser: parser, baseCurrency: baseCurrency, transactionLikeRowEstimate: nil, strongAmountRowCount: nil, repeatedRowClusterCount: nil)
            let fromLocal = result.items ?? []
            let merged = mergeParsedItems(base: cached, additional: fromLocal)
            let normalized = ImportViewModel.normalizeMerchantsInItems(merged)
            return ExtractionPipelineResult(
                items: normalized,
                imageHash: imageHash,
                normalizedOCRText: normalizedOCRText,
                ocrFingerprint: ocrFingerprint,
                screenFingerprint: screenFingerprint,
                ocrTextRaw: ocrTextRaw
            )
        }

        let localResult = ExtractionRulesMatcher.tryStructuredThenLegacyWithOutcome(ocrText: normalizedOCRText, parser: parser, baseCurrency: baseCurrency, transactionLikeRowEstimate: nil, strongAmountRowCount: nil, repeatedRowClusterCount: nil)
        if case .confidentParse = localResult.outcome, let localItems = localResult.items, !localItems.isEmpty {
            let normalized = ImportViewModel.normalizeMerchantsInItems(localItems)
            ParsingRulesStore.shared.recordSuccessfulLocalUse(ruleId: localResult.matchedRuleId, imageHash: imageHash)
            ParsingRulesStore.shared.cacheResult(normalized, forImageHash: imageHash)
            return ExtractionPipelineResult(
                items: normalized,
                imageHash: imageHash,
                normalizedOCRText: normalizedOCRText,
                ocrFingerprint: ocrFingerprint,
                screenFingerprint: screenFingerprint,
                ocrTextRaw: ocrTextRaw
            )
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
                baseCurrency: baseCurrency
            )
        } else {
            response = try await gptService.extractAndGetRules(
                ocrText: ocrTextRaw,
                categories: categories,
                subcategories: subcategories,
                baseCurrency: baseCurrency
            )
        }

        if let rules = response.rules {
            ParsingRulesStore.shared.appendRuleSet(rules: rules, forOcrText: normalizedOCRText)
        } else {
            do {
                let rules = try await gptService.generateRules(ocrText: normalizedOCRText)
                ParsingRulesStore.shared.appendRuleSet(rules: rules, forOcrText: normalizedOCRText)
            } catch { }
        }

        let deduped = deduplicateGPTTransactions(response.transactions)
        let successOnly = deduped.filter { $0.isSuccessStatus }
        var items = successOnly.map { tx in
            ParsedTransactionItem(
                amount: tx.amount,
                isCredit: tx.isCredit ?? false,
                currency: tx.currency ?? "USD",
                date: tx.date,
                time: tx.time,
                merchant: ImportViewModel.normalizeMerchant(tx.merchant),
                categoryId: tx.categoryId,
                subcategoryId: tx.subcategoryId,
                isSubscription: tx.isSubscription
            )
        }
        let postGptLocal = ExtractionRulesMatcher.tryStructuredThenLegacy(ocrText: normalizedOCRText, parser: parser, baseCurrency: baseCurrency) ?? []
        items = mergeParsedItems(base: items, additional: postGptLocal)
        items = ImportViewModel.normalizeMerchantsInItems(items)
        for i in items.indices {
            if let corrected = aliasStore.resolveToNormalizedMerchant(raw: items[i].merchant) ?? MerchantCorrectionStore.shared.lookup(amount: items[i].amount, date: items[i].date, originalMerchant: items[i].merchant) {
                items[i].merchant = corrected
            }
        }
        ParsingRulesStore.shared.cacheResult(items, forImageHash: imageHash)
        return ExtractionPipelineResult(
            items: items,
            imageHash: imageHash,
            normalizedOCRText: normalizedOCRText,
            ocrFingerprint: ocrFingerprint,
            screenFingerprint: screenFingerprint,
            ocrTextRaw: ocrTextRaw
        )
    }

    private func mergeParsedItems(base: [ParsedTransactionItem], additional: [ParsedTransactionItem]) -> [ParsedTransactionItem] {
        let baseKeys = Set(base.map { "\($0.date)|\(abs($0.amount))|\($0.merchant ?? "")" })
        var out = base
        for item in additional {
            let key = "\(item.date)|\(abs(item.amount))|\(item.merchant ?? "")"
            if !baseKeys.contains(key) { out.append(item) }
        }
        return out
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
