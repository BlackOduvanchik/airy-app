//
//  ImportViewModel.swift
//  Airy
//
//  Local-only: OCR + LocalOCRParser, store in SwiftData. No backend.
//

import SwiftUI
import PhotosUI
import UIKit
import BackgroundTasks
import ActivityKit
import UserNotifications

/// Pipeline phase for one import attempt. Observable for debugging and UI.
enum ImportPipelinePhase: String, Equatable {
    case idle
    case imageSelected
    case loadingImage
    case computingHash
    case localAnalysis
    case gptFallback
    case savingResult
    case completed
    case failed
}

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

    /// Last run extraction debug reports (one per screenshot). Cleared at start of import; appended after each image.
    var lastExtractionReports: [ExtractionDebugReport] = []

    /// Current import run id; only this run may update analyzingItems / lastExtractionReports.
    var currentImportRunId: UUID?
    /// Pipeline phase for observability and "Import didn't start" detection.
    var pipelinePhase: ImportPipelinePhase = .idle
    /// Per-attempt session id for logging.
    var importSessionId: UUID?

    private var analysisTask: Task<Void, Never>?

    @available(iOS 16.2, *)
    private var importLiveActivity: Activity<AiryImportAttributes>? {
        get { _importLiveActivity as? Activity<AiryImportAttributes> }
        set { _importLiveActivity = newValue }
    }
    private var _importLiveActivity: Any? = nil

    // MARK: - Singleton
    static let shared = ImportViewModel()

    // MARK: - Background queue

    struct QueuedImage: Identifiable {
        let id = UUID()
        let image: UIImage
        var status: QueueItemStatus = .pending
        var attemptCount: Int = 0      // 0-2; 3 total attempts
        var rateLimitRetries: Int = 0  // incremented on each 429; after 10 → .failed
    }

    enum QueueItemStatus { case pending, processing, completed, failed }

    private(set) var imageQueue: [QueuedImage] = []
    private(set) var liveExtractedItems: [ParsedTransactionItem] = []
    /// Unfiltered items per image, parallel array to lastExtractionReports (used for CSV export).
    private(set) var lastExtractionReportItems: [[ParsedTransactionItem]] = []
    /// True after queue finishes; cleared when user calls addProcessedToPending.
    var hasUnreviewedResults: Bool = false

    var remainingQueueCount: Int {
        imageQueue.filter { $0.status == .pending || $0.status == .processing }.count
    }

    private let ocrService = OCRService()
    private let parser = LocalOCRParser()
    private let gptService = GPTRulesService()
    private let blockClassifier: BlockClassifier = RuleBasedBlockClassifier()

    /// Number of images processed concurrently. Reduced on rate-limit, restored on success streak.
    private var concurrencyLevel: Int = 3
    private var consecutiveSuccesses: Int = 0

    /// Minimum family cluster size to attempt local extraction from grouped rows.
    private static let minFamilyProfileSizeForLocalExtraction = 5
    /// Minimum extracted item count to accept local extraction.
    private static let minLocalExtractionItemCount = 1
    /// Minimum amount coverage ratio (validAmountCount / groupedRows.count) to accept.
    private static let minAmountCoverageRatio = 0.5
    /// Minimum merchant coverage ratio to accept.
    private static let minMerchantCoverageRatio = 0.4
    /// Minimum overall local extraction confidence (0...1) to accept.
    private static let minLocalExtractionConfidence = 0.65

    /// Generic labels that must not be used as merchant; replaced with "Other".
    private static let genericMerchantValues: Set<String> = [
        "покупка", "purchase", "payment", "transaction", "оплата", "withdrawal",
        "payout", "transfer", "purchase", "sale", "expense", "withdrawal", "payment"
    ]

    /// Returns "Other" if merchant is nil, empty, or a generic label; otherwise returns trimmed merchant.
    static func normalizeMerchant(_ raw: String?) -> String? {
        let s = (raw ?? "").trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return "Other" }
        if genericMerchantValues.contains(s.lowercased()) { return "Other" }
        return s
    }

    /// Apply normalizeMerchant to every item so cache and local-parser results never show "покупка" etc.
    static func normalizeMerchantsInItems(_ items: [ParsedTransactionItem]) -> [ParsedTransactionItem] {
        items.map { item in
            var copy = item
            copy.merchant = normalizeMerchant(item.merchant) ?? item.merchant
            return copy
        }
    }

    /// Apply saved category rule for this merchant (from "Remember rule" in Review); otherwise use item's category.
    private static func effectiveCategory(for item: ParsedTransactionItem) -> (category: String, subcategory: String?) {
        let cat = MerchantCategoryRuleStore.shared.categoryId(for: item.merchant) ?? item.categoryId ?? "other"
        let sub = MerchantCategoryRuleStore.shared.subcategoryId(for: item.merchant) ?? item.subcategoryId
        return (cat, sub)
    }

    /// Store expense as positive magnitude; income as-is. Dashboard expects positive amounts for spending.
    private static func storedAmount(amount: Double, isCredit: Bool) -> Double {
        isCredit ? amount : abs(amount)
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
        let runId = UUID()
        await MainActor.run {
            currentImportRunId = runId
            importSessionId = runId
            pipelinePhase = .imageSelected
        }
        isProcessing = true
        resultMessage = nil
        errorMessage = nil
        pendingCount = 0
        defer { Task { @MainActor in isProcessing = false; pipelinePhase = .idle } }
        await MainActor.run { lastExtractionReports = [] }
        pipelinePhase = .loadingImage
        var totalAdded = 0
        for (index, image) in images.enumerated() {
            do {
                let (parsed, ocrText, hash, phase1) = try await recognizeAndParseOneImage(image)
                var addedThisImage = 0
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
                    let probableId: String? = await MainActor.run {
                        if case .probableDuplicate(let id) = LocalDataStore.shared.duplicateClassification(merchant: item.merchant, date: item.date, amount: amt, includePending: false) { return id }
                        return nil
                    }
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
                        subcategory: sub,
                        probableDuplicateOfId: probableId
                    )
                    let sourceFamilyId = phase1.matchedLayoutFamilyId ?? phase1.layoutFamilyId
                    await MainActor.run {
                        LocalDataStore.shared.addPendingTransaction(
                            payload: payload,
                            ocrText: String(ocrText.prefix(2000)),
                            sourceImageHash: hash,
                            sourceFamilyId: sourceFamilyId
                        )
                    }
                    addedThisImage += 1
                    totalAdded += 1
                }
                let removedByDuplicate = parsed.count - addedThisImage
                let finallyShown = addedThisImage
                let report = Self.buildExtractionDebugReport(imageIndex: index, phase1: phase1, extractedItems: parsed, removedByDuplicate: removedByDuplicate, finallyShown: finallyShown)
                await MainActor.run { lastExtractionReports.append(report) }
            } catch {
                let hashPrefix = String(ocrService.imageHash(for: image).prefix(8))
                let report = ExtractionDebugReport(
                    imageIndex: index,
                    source: .none,
                    imageSentToGPT: false,
                    rawRowLikeBlocks: 0,
                    transactionLikeRowEstimate: 0,
                    extractedTransactions: 0,
                    coverageScore: 0,
                    extractionStatus: .failed,
                    removedByValidation: 0,
                    removedByDuplicate: 0,
                    finallyShown: 0,
                    imageHashPrefix: hashPrefix
                )
                await MainActor.run { lastExtractionReports.append(report) }
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
        let runId = UUID()
        await MainActor.run {
            currentImportRunId = runId
            importSessionId = runId
            pipelinePhase = .imageSelected
        }
        isProcessing = true
        resultMessage = nil
        errorMessage = nil
        pendingCount = 0
        defer { Task { @MainActor in isProcessing = false; pipelinePhase = .idle } }
        await MainActor.run { lastExtractionReports = [] }
        pipelinePhase = .loadingImage
        do {
            let (parsed, ocrText, hash, phase1) = try await recognizeAndParseOneImage(image)

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
                let probableId: String? = await MainActor.run {
                    if case .probableDuplicate(let id) = LocalDataStore.shared.duplicateClassification(merchant: item.merchant, date: item.date, amount: amt, includePending: false) { return id }
                    return nil
                }
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
                    subcategory: sub,
                    probableDuplicateOfId: probableId
                )
                let sourceFamilyId = phase1.matchedLayoutFamilyId ?? phase1.layoutFamilyId
                await MainActor.run {
                    LocalDataStore.shared.addPendingTransaction(
                        payload: payload,
                        ocrText: String(ocrText.prefix(2000)),
                        sourceImageHash: hash,
                        sourceFamilyId: sourceFamilyId
                    )
                }
                addedCount += 1
            }

            let removedByDuplicate = parsed.count - addedCount
            let finallyShown = addedCount
            let report = Self.buildExtractionDebugReport(imageIndex: 0, phase1: phase1, extractedItems: parsed, removedByDuplicate: removedByDuplicate, finallyShown: finallyShown)
            let count = addedCount
            await MainActor.run {
                lastExtractionReports = [report]
                resultMessage = parsed.isEmpty ? "No transactions found in image" : "Found \(count) transaction(s). Review in Pending."
                pendingCount = count
            }
        } catch {
            let hashPrefix = String(ocrService.imageHash(for: image).prefix(8))
            let report = ExtractionDebugReport(
                imageIndex: 0,
                source: .none,
                imageSentToGPT: false,
                rawRowLikeBlocks: 0,
                transactionLikeRowEstimate: 0,
                extractedTransactions: 0,
                coverageScore: 0,
                extractionStatus: .failed,
                removedByValidation: 0,
                removedByDuplicate: 0,
                finallyShown: 0,
                imageHashPrefix: hashPrefix
            )
            await MainActor.run {
                lastExtractionReports = [report]
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
    private(set) var pendingToAdd: (items: [ParsedTransactionItem], hash: String, ocrText: String, familyId: String?)?
    /// Batches for multi-image; set by processImagesReturningItems.
    private(set) var pendingToAddBatches: [(items: [ParsedTransactionItem], hash: String, ocrText: String, familyId: String?)]?


    /// Processes image, returns parsed items for display. Does NOT add to pending until addProcessedToPending.
    func processImageReturningItems(_ image: UIImage) async -> [ParsedTransactionItem] {
        isProcessing = true
        defer { Task { @MainActor in isProcessing = false } }
        return await processImageReturningItemsInternal(image)
    }

    /// Processes multiple images one by one: OCR → local rules → cache → single-image GPT per image. No batch GPT.
    func processImagesReturningItems(_ images: [UIImage]) async -> [ParsedTransactionItem] {
        await MainActor.run { errorMessage = nil; resultMessage = nil }
        isProcessing = true
        defer { Task { @MainActor in isProcessing = false } }
        await MainActor.run { lastExtractionReports = [] }
        var allItems: [ParsedTransactionItem] = []
        var batches: [(items: [ParsedTransactionItem], hash: String, ocrText: String, familyId: String?)] = []

        for (index, image) in images.enumerated() {
            do {
                let (items, ocrText, hash, phase1) = try await recognizeAndParseOneImage(image)
                let itemsToAdd = await filterItemsForPending(items: items, hash: hash, ocrText: ocrText)
                let removedByDuplicate = items.count - itemsToAdd.count
                let finallyShown = itemsToAdd.count
                let report = Self.buildExtractionDebugReport(imageIndex: index, phase1: phase1, extractedItems: items, removedByDuplicate: removedByDuplicate, finallyShown: finallyShown)
                await MainActor.run { lastExtractionReports.append(report) }
                allItems.append(contentsOf: itemsToAdd)
                batches.append((itemsToAdd, hash, ocrText, phase1.matchedLayoutFamilyId ?? phase1.layoutFamilyId))
            } catch OCRServiceError.noNumbersInImage {
                let hashPrefix = String(ocrService.imageHash(for: image).prefix(8))
                let report = ExtractionDebugReport(
                    imageIndex: index,
                    source: .none,
                    imageSentToGPT: false,
                    rawRowLikeBlocks: 0,
                    transactionLikeRowEstimate: 0,
                    extractedTransactions: 0,
                    coverageScore: 0,
                    extractionStatus: .failed,
                    removedByValidation: 0,
                    removedByDuplicate: 0,
                    finallyShown: 0,
                    imageHashPrefix: hashPrefix
                )
                await MainActor.run { lastExtractionReports.append(report) }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription; resultMessage = error.localizedDescription }
                return allItems
            }
        }

        let batchesCopy = batches
        let allItemsCount = allItems.count
        if let lastBatch = batches.last {
            ParsingRulesStore.shared.lastOcrSample = String(lastBatch.ocrText.prefix(4000))
        }
        await MainActor.run {
            pendingToAdd = nil
            pendingToAddBatches = batchesCopy.isEmpty ? nil : batchesCopy
            pendingCount = allItemsCount
            resultMessage = "Found \(allItemsCount) transaction(s). Review in Pending."
        }
        return allItems
    }

    /// Returns (items, ocrText, hash) if cache or local rules matched; nil if GPT needed. Throws if no numbers in image.
    private func tryRecognizeWithCacheAndLocal(_ image: UIImage) async throws -> (items: [ParsedTransactionItem], ocrText: String, hash: String)? {
        let hash = ocrService.imageHash(for: image)
        if let cached = ParsingRulesStore.shared.cachedResult(forImageHash: hash), !cached.isEmpty {
            let ocrText = try await ocrService.recognizeText(from: image)
            let fromLocal = ParsingRulesStore.shared.tryMatch(ocrText: ocrText, parser: parser, baseCurrency: "USD") ?? []
            let merged = mergeParsedItems(base: cached, additional: fromLocal)
            let normalized = Self.normalizeMerchantsInItems(merged)
            if normalized.count > cached.count {
                ParsingRulesStore.shared.cacheResult(normalized, forImageHash: hash)
            }
            return (normalized, ocrText, hash)
        }
        let ocrText = try await ocrService.recognizeText(from: image)
        if !OCRService.containsDecimalDigits(ocrText) {
            throw OCRServiceError.noNumbersInImage
        }
        if let local = ParsingRulesStore.shared.tryMatch(ocrText: ocrText, parser: parser, baseCurrency: "USD"), !local.isEmpty {
            return (Self.normalizeMerchantsInItems(local), ocrText, hash)
        }
        return nil
    }

    /// Apply merchant correction and exclude already-saved duplicates. Returns items to show in pending.
    private func filterItemsForPending(items: [ParsedTransactionItem], hash: String, ocrText: String) async -> [ParsedTransactionItem] {
        var copy = items
        for i in copy.indices {
            if let corrected = MerchantCorrectionStore.shared.lookup(
                amount: copy[i].amount,
                date: copy[i].date,
                originalMerchant: copy[i].merchant
            ) {
                copy[i].merchant = corrected
            }
        }
        let correctedItems = copy
        return await MainActor.run {
            correctedItems.filter { item in
                let amt = Self.storedAmount(amount: item.amount, isCredit: item.isCredit)
                return !LocalDataStore.shared.isExactDuplicateTransaction(
                    merchant: item.merchant,
                    date: item.date,
                    amount: amt,
                    includePending: false
                )
            }
        }
    }

    /// Enqueues images for background processing. Kept for backward compatibility.
    func startAnalyzing(images: [UIImage]) {
        Task { @MainActor in enqueue(images) }
    }

    // MARK: - Queue management

    /// Adds images to the background processing queue (max 30 total). Starts queue if idle.
    @MainActor
    func enqueue(_ images: [UIImage]) {
        // Clear finished items so the queue slot count and progress counter reset between batches.
        if !isAnalyzing {
            imageQueue.removeAll { $0.status == .completed || $0.status == .failed }
        }
        let slots = 30 - imageQueue.count
        guard slots > 0, !images.isEmpty else { return }
        let toAdd = Array(images.prefix(slots))
        imageQueue.append(contentsOf: toAdd.map { QueuedImage(image: $0) })
        if !isAnalyzing {
            startQueueProcessing()
        }
    }

    @MainActor
    private func startQueueProcessing() {
        analysisTask?.cancel()
        isAnalyzing = true
        hasUnreviewedResults = false
        liveExtractedItems = []
        lastExtractionReports = []
        lastExtractionReportItems = []
        pendingToAddBatches = nil
        errorMessage = nil
        resultMessage = nil
        pipelinePhase = .imageSelected
        requestNotificationPermissionIfNeeded()
        startImportLiveActivity()
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.processQueue()
        }
        analysisTask = task
    }

    private func processQueue() async {
        struct NextItem {
            let id: UUID
            let image: UIImage
            let attemptCount: Int
        }

        // Result of processing a single image — carries everything needed to update shared state.
        struct ProcessOneResult {
            enum Outcome {
                case success(items: [ParsedTransactionItem], allItems: [ParsedTransactionItem],
                             report: ExtractionDebugReport,
                             batch: (items: [ParsedTransactionItem], hash: String, ocrText: String, familyId: String?))
                case noNumbers(report: ExtractionDebugReport)
                case rateLimited
                case failed(report: ExtractionDebugReport, message: String)
                case requeue  // transient error, attemptCount < 2
            }
            let itemId: UUID
            let imageIndex: Int
            let outcome: Outcome
            let image: UIImage
            let attemptCount: Int
        }

        var processedIndex = 0
        // Small delay after a rate-limit batch before retrying (seconds).
        var rateLimitBackoffSeconds: Double = 0

        outerLoop: while true {
            // Apply backoff if the previous batch hit a rate limit.
            if rateLimitBackoffSeconds > 0 {
                try? await Task.sleep(nanoseconds: UInt64(rateLimitBackoffSeconds * 1_000_000_000))
                rateLimitBackoffSeconds = 0
            }

            // Atomically grab up to concurrencyLevel pending items and mark them .processing.
            let batch: [NextItem] = await MainActor.run { [weak self] in
                guard let self else { return [] }
                var result: [NextItem] = []
                for _ in 0..<concurrencyLevel {
                    guard let item = imageQueue.first(where: { $0.status == .pending }),
                          let idx = imageQueue.firstIndex(where: { $0.id == item.id }) else { break }
                    imageQueue[idx].status = .processing
                    result.append(NextItem(id: item.id, image: item.image, attemptCount: item.attemptCount))
                }
                return result
            }

            guard !batch.isEmpty else {
                // No pending items — check for new arrivals or finalize.
                let shouldStop: Bool = await MainActor.run { [weak self] in
                    guard let self else { return true }
                    // If this task was cancelled (e.g. by resumeIfNeeded starting a new task),
                    // exit silently — the new task will finalize when it actually completes all items.
                    if Task.isCancelled { return true }
                    if imageQueue.contains(where: { $0.status == .pending }) { return false }
                    isAnalyzing = false
                    hasUnreviewedResults = !liveExtractedItems.isEmpty
                    analyzingItems = liveExtractedItems
                    resultMessage = liveExtractedItems.isEmpty ? nil
                        : "Found \(liveExtractedItems.count) transaction(s). Review in Pending."
                    pipelinePhase = liveExtractedItems.isEmpty && errorMessage != nil ? .failed : .completed
                    endImportLiveActivity()
                    sendImportCompletionNotification(count: liveExtractedItems.count)
                    return true
                }
                if shouldStop { break outerLoop }
                continue outerLoop
            }

            // Process the batch concurrently.
            let batchStartIndex = processedIndex
            processedIndex += batch.count
            let results: [ProcessOneResult] = await withTaskGroup(of: ProcessOneResult.self) { group in
                for (offset, next) in batch.enumerated() {
                    let imgIndex = batchStartIndex + offset
                    group.addTask { [weak self] in
                        guard let self else {
                            return ProcessOneResult(itemId: next.id, imageIndex: imgIndex,
                                                   outcome: .requeue, image: next.image,
                                                   attemptCount: next.attemptCount)
                        }
                        do {
                            let (items, ocrText, hash, phase1) = try await recognizeAndParseOneImage(next.image)
                            let filteredItems = await filterItemsForPending(items: items, hash: hash, ocrText: ocrText)
                            let removedByDuplicate = items.count - filteredItems.count
                            let report = Self.buildExtractionDebugReport(
                                imageIndex: imgIndex, phase1: phase1,
                                extractedItems: items,
                                removedByDuplicate: removedByDuplicate,
                                finallyShown: filteredItems.count)
                            let batchTuple = (items: filteredItems, hash: hash, ocrText: ocrText,
                                              familyId: phase1.matchedLayoutFamilyId ?? phase1.layoutFamilyId)
                            return ProcessOneResult(itemId: next.id, imageIndex: imgIndex,
                                                   outcome: .success(items: filteredItems, allItems: items,
                                                                     report: report, batch: batchTuple),
                                                   image: next.image, attemptCount: next.attemptCount)
                        } catch OCRServiceError.noNumbersInImage {
                            let hashPrefix = String(ocrService.imageHash(for: next.image).prefix(8))
                            let report = ExtractionDebugReport(
                                imageIndex: imgIndex, source: .none, imageSentToGPT: false,
                                rawRowLikeBlocks: 0, transactionLikeRowEstimate: 0,
                                extractedTransactions: 0, coverageScore: 0,
                                extractionStatus: .failed, removedByValidation: 0,
                                removedByDuplicate: 0, finallyShown: 0, imageHashPrefix: hashPrefix)
                            return ProcessOneResult(itemId: next.id, imageIndex: imgIndex,
                                                   outcome: .noNumbers(report: report),
                                                   image: next.image, attemptCount: next.attemptCount)
                        } catch GPTRulesError.rateLimited {
                            // Don't count against attemptCount; caller will requeue and back off.
                            return ProcessOneResult(itemId: next.id, imageIndex: imgIndex,
                                                   outcome: .rateLimited,
                                                   image: next.image, attemptCount: next.attemptCount)
                        } catch {
                            if next.attemptCount < 2 {
                                return ProcessOneResult(itemId: next.id, imageIndex: imgIndex,
                                                       outcome: .requeue,
                                                       image: next.image, attemptCount: next.attemptCount)
                            } else {
                                let hashPrefix = String(ocrService.imageHash(for: next.image).prefix(8))
                                let report = ExtractionDebugReport(
                                    imageIndex: imgIndex, source: .none, imageSentToGPT: false,
                                    rawRowLikeBlocks: 0, transactionLikeRowEstimate: 0,
                                    extractedTransactions: 0, coverageScore: 0,
                                    extractionStatus: .failed, removedByValidation: 0,
                                    removedByDuplicate: 0, finallyShown: 0, imageHashPrefix: hashPrefix)
                                return ProcessOneResult(itemId: next.id, imageIndex: imgIndex,
                                                       outcome: .failed(report: report,
                                                                        message: error.localizedDescription),
                                                       image: next.image, attemptCount: next.attemptCount)
                            }
                        }
                    }
                }
                var collected: [ProcessOneResult] = []
                for await r in group { collected.append(r) }
                return collected
            }

            // Apply results on MainActor and update adaptive concurrency.
            let hitRateLimit: Bool = await MainActor.run { [weak self] in
                guard let self else { return false }
                var didHitRateLimit = false
                for result in results {
                    guard let idx = imageQueue.firstIndex(where: { $0.id == result.itemId }) else { continue }
                    switch result.outcome {
                    case .success(let filtered, let all, let report, let batchTuple):
                        imageQueue[idx].status = .completed
                        liveExtractedItems.append(contentsOf: filtered)
                        lastExtractionReports.append(report)
                        lastExtractionReportItems.append(all)
                        if pendingToAddBatches == nil { pendingToAddBatches = [batchTuple] }
                        else { pendingToAddBatches!.append(batchTuple) }
                        pendingCount = liveExtractedItems.count
                        if let last = pendingToAddBatches?.last {
                            ParsingRulesStore.shared.lastOcrSample = String(last.ocrText.prefix(4000))
                        }
                        consecutiveSuccesses += 1
                        if consecutiveSuccesses >= 5 {
                            concurrencyLevel = min(3, concurrencyLevel + 1)
                            consecutiveSuccesses = 0
                        }
                        updateImportLiveActivity()
                    case .noNumbers(let report):
                        imageQueue[idx].status = .failed
                        lastExtractionReports.append(report)
                        lastExtractionReportItems.append([])
                        consecutiveSuccesses = 0
                    case .rateLimited:
                        imageQueue[idx].rateLimitRetries += 1
                        if imageQueue[idx].rateLimitRetries >= 10 {
                            // Permanent rate limit — give up to avoid infinite loop.
                            imageQueue[idx].status = .failed
                            errorMessage = "API rate limit reached. Please try again later."
                        } else {
                            imageQueue[idx].status = .pending
                        }
                        concurrencyLevel = max(1, concurrencyLevel - 1)
                        consecutiveSuccesses = 0
                        didHitRateLimit = true
                    case .requeue:
                        var item = imageQueue[idx]
                        item.status = .pending
                        item.attemptCount += 1
                        imageQueue.remove(at: idx)
                        imageQueue.append(item)
                        consecutiveSuccesses = 0
                    case .failed(let report, let message):
                        imageQueue[idx].status = .failed
                        lastExtractionReports.append(report)
                        lastExtractionReportItems.append([])
                        errorMessage = message
                        consecutiveSuccesses = 0
                    }
                }
                return didHitRateLimit
            }

            // Back off 60s if any item in the batch was rate-limited.
            if hitRateLimit { rateLimitBackoffSeconds = 60 }
        }
    }

    private func processImageReturningItemsInternal(_ image: UIImage) async -> [ParsedTransactionItem] {
        resultMessage = nil
        errorMessage = nil
        pendingCount = 0
        pendingToAdd = nil
        await MainActor.run { lastExtractionReports = [] }
        do {
            let (parsed, ocrText, hash, phase1) = try await recognizeAndParseOneImage(image)
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
                        amount: amt,
                        includePending: false
                    )
                }
            }
            let removedByDuplicate = parsed.count - itemsToAdd.count
            let finallyShown = itemsToAdd.count
            let report = Self.buildExtractionDebugReport(imageIndex: 0, phase1: phase1, extractedItems: parsed, removedByDuplicate: removedByDuplicate, finallyShown: finallyShown)
            await MainActor.run {
                lastExtractionReports = [report]
                resultMessage = "Found \(itemsToAdd.count) transaction(s). Review in Pending."
                pendingCount = itemsToAdd.count
                pendingToAdd = (itemsToAdd, hash, ocrText, phase1.matchedLayoutFamilyId ?? phase1.layoutFamilyId)
                ParsingRulesStore.shared.lastOcrSample = String(ocrText.prefix(4000))
            }
            return itemsToAdd
        } catch {
            let hashPrefix = String(ocrService.imageHash(for: image).prefix(8))
            let report = ExtractionDebugReport(
                imageIndex: 0,
                source: .none,
                imageSentToGPT: false,
                rawRowLikeBlocks: 0,
                transactionLikeRowEstimate: 0,
                extractedTransactions: 0,
                coverageScore: 0,
                extractionStatus: .failed,
                removedByValidation: 0,
                removedByDuplicate: 0,
                finallyShown: 0,
                imageHashPrefix: hashPrefix
            )
            await MainActor.run {
                lastExtractionReports = [report]
                resultMessage = error.localizedDescription
                errorMessage = error.localizedDescription
            }
            return []
        }
    }

    /// Raw line-like blocks (non-empty lines). Same normalization as LocalOCRParser.
    private static func rawRowLikeBlocks(ocrText: String) -> Int {
        let normalized = ocrText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return normalized.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.count
    }

    /// Lines from OCR text (normalized, trimmed, non-empty). Used for block classification.
    private static func ocrLines(ocrText: String) -> [String] {
        let normalized = ocrText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return normalized.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Same normalization as ParsingRulesStore (match path) so layout-family coarse fingerprint matches when saving after GPT. Do not use OCRNormalizer here to avoid dependency on Services target.
    private static func normalizedOCRTextForCoarse(_ raw: String) -> String {
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

    /// Plausible transaction count for coverage denominator (blend of row estimates so completion is not overly strict).
    private static func plausibleEstimate(transactionLikeRowEstimate: Int, strongAmountRowCount: Int, repeatedRowClusterCount: Int) -> Int {
        let base = max(strongAmountRowCount, repeatedRowClusterCount)
        if base > 0 {
            return min(transactionLikeRowEstimate, base + 1)
        }
        return transactionLikeRowEstimate
    }

    /// Returns overall local extraction confidence (0...1): weighted average of amount/merchant/date coverage.
    private static func localExtractionConfidenceScore(validAmountCount: Int, validMerchantCount: Int, validDateCount: Int, totalGroupedRows: Int) -> Double {
        guard totalGroupedRows > 0 else { return 0 }
        let amountRatio = Double(validAmountCount) / Double(totalGroupedRows)
        let merchantRatio = Double(validMerchantCount) / Double(totalGroupedRows)
        let dateRatio = Double(validDateCount) / Double(totalGroupedRows)
        return (amountRatio * 0.4 + merchantRatio * 0.4 + dateRatio * 0.2)
    }

    /// Relaxed gate for expert-maturity families: archetype pre-filtered rows so lower thresholds apply.
    private static func localExtractionAcceptanceGatesRelaxed(
        items: [ParsedTransactionItem],
        validAmountCount: Int,
        validMerchantCount: Int,
        validDateCount: Int,
        totalGroupedRows: Int,
        excludedByStatusCount: Int
    ) -> (accepted: Bool, failReason: GPTFallbackReason?) {
        guard totalGroupedRows > 0 else { return (false, .noGroupedRows) }
        if items.count < minLocalExtractionItemCount { return (false, .noValidItems) }
        let amountCoverage = Double(validAmountCount) / Double(totalGroupedRows)
        if amountCoverage < 0.35 { return (false, .lowAmountCoverage) }
        let merchantCoverage = Double(validMerchantCount) / Double(totalGroupedRows)
        if merchantCoverage < 0.30 { return (false, .lowMerchantCoverage) }
        let confidence = localExtractionConfidenceScore(validAmountCount: validAmountCount, validMerchantCount: validMerchantCount, validDateCount: validDateCount, totalGroupedRows: totalGroupedRows)
        if confidence < 0.50 { return (false, .lowOverallConfidence) }
        if excludedByStatusCount > totalGroupedRows / 2 { return (false, .suspiciousStatusRows) }
        return (true, nil)
    }

    /// Dual gate: check hard minimums and overall confidence. Returns (accepted, failReason).
    private static func localExtractionAcceptanceGates(
        items: [ParsedTransactionItem],
        validAmountCount: Int,
        validMerchantCount: Int,
        validDateCount: Int,
        totalGroupedRows: Int,
        excludedByStatusCount: Int
    ) -> (accepted: Bool, failReason: GPTFallbackReason?) {
        guard totalGroupedRows > 0 else { return (false, .noGroupedRows) }
        if items.count < minLocalExtractionItemCount { return (false, .noValidItems) }
        let amountCoverage = Double(validAmountCount) / Double(totalGroupedRows)
        if amountCoverage < minAmountCoverageRatio { return (false, .lowAmountCoverage) }
        let merchantCoverage = Double(validMerchantCount) / Double(totalGroupedRows)
        if merchantCoverage < minMerchantCoverageRatio { return (false, .lowMerchantCoverage) }
        let confidence = localExtractionConfidenceScore(validAmountCount: validAmountCount, validMerchantCount: validMerchantCount, validDateCount: validDateCount, totalGroupedRows: totalGroupedRows)
        if confidence < minLocalExtractionConfidence { return (false, .lowOverallConfidence) }
        if excludedByStatusCount > totalGroupedRows / 2 { return (false, .suspiciousStatusRows) }
        return (true, nil)
    }

    /// Screen-type heuristic from row counts and extracted count (no OCR text).
    private static func inferScreenType(rawRowLikeBlocks: Int, transactionLikeRowEstimate: Int, strongAmountRowCount: Int, repeatedRowClusterCount: Int, candidatesExtracted: Int) -> ScreenType {
        if repeatedRowClusterCount >= 2 && transactionLikeRowEstimate >= 2 {
            return .transactionList
        }
        if repeatedRowClusterCount <= 1 && candidatesExtracted == 1 && rawRowLikeBlocks < 15 {
            return .singlePaymentConfirmation
        }
        return .unknown
    }

    /// Per-item: merchant, amount, currency, date-or-time present. Mean over items; 0 if empty.
    private static func fieldCompletenessScore(items: [ParsedTransactionItem]) -> Double {
        guard !items.isEmpty else { return 0 }
        let perItem: [Double] = items.map { item in
            var score = 0.0
            if let m = item.merchant, !m.isEmpty { score += 1 }
            if item.amount > 0 { score += 1 }
            if !item.currency.isEmpty { score += 1 }
            let hasDateOrTime = !item.date.isEmpty || (item.time != nil && !(item.time?.isEmpty ?? true))
            if hasDateOrTime { score += 1 }
            return score / 4.0
        }
        return perItem.reduce(0, +) / Double(perItem.count)
    }

    /// Primary expected transaction count by screen type (repeatedRowClusterCount for list).
    private static func expectedTransactionCount(screenType: ScreenType, repeatedRowClusterCount: Int, strongAmountRowCount: Int, transactionLikeRowEstimate: Int) -> Int {
        switch screenType {
        case .transactionList, .bankStatementLike:
            return max(repeatedRowClusterCount, 1)
        case .singlePaymentConfirmation:
            return 1
        case .receipt, .subscriptionReceipt, .moneyTransfer, .failedTransactionNotice, .unknown:
            if repeatedRowClusterCount > 0 { return max(repeatedRowClusterCount, 1) }
            let fallback = plausibleEstimate(transactionLikeRowEstimate: transactionLikeRowEstimate, strongAmountRowCount: strongAmountRowCount, repeatedRowClusterCount: repeatedRowClusterCount)
            return max(fallback, 1)
        }
    }

    /// Screen-type aware completion: (status, confidence 0...1, reason string).
    private static func completionStatus(screenType: ScreenType, extracted: Int, expected: Int, fieldCompletenessScore: Double, removedByValidation: Int, removedByDuplicate: Int) -> (ExtractionStatus, completionConfidence: Double, completionReason: String) {
        if expected == 0 {
            return (.noTransactionRows, 0, "no transaction-like rows")
        }
        if extracted == 0 {
            return (.failed, 0, "no transactions extracted")
        }
        let coverage = expected > 0 ? Double(extracted) / Double(expected) : 0
        let validationLoss = removedByValidation > 0

        switch screenType {
        case .transactionList, .bankStatementLike:
            if coverage >= 0.95 && fieldCompletenessScore >= 0.9 && !validationLoss {
                let reason = "extracted \(extracted) vs \(expected) clusters; field score \(String(format: "%.2f", fieldCompletenessScore))"
                return (.complete, min(1.0, 0.85 + fieldCompletenessScore * 0.15), reason)
            }
            if coverage >= 0.8 && fieldCompletenessScore >= 0.75 {
                let reason = "extracted \(extracted) vs \(expected) clusters; field score \(String(format: "%.2f", fieldCompletenessScore))"
                return (.likelyComplete, 0.7 + fieldCompletenessScore * 0.2, reason)
            }
            if coverage < 0.5 || fieldCompletenessScore < 0.5 {
                return (.poor, 0.3, "low coverage (\(String(format: "%.2f", coverage))) or field score (\(String(format: "%.2f", fieldCompletenessScore)))")
            }
            return (.partial, 0.5, "extracted \(extracted) vs \(expected); field \(String(format: "%.2f", fieldCompletenessScore))")
        case .singlePaymentConfirmation:
            if extracted == 1 && fieldCompletenessScore >= 0.85 {
                return (.complete, 0.9, "single confirmation; field score \(String(format: "%.2f", fieldCompletenessScore))")
            }
            if extracted == 1 && fieldCompletenessScore >= 0.6 {
                return (.likelyComplete, 0.75, "single confirmation; field score \(String(format: "%.2f", fieldCompletenessScore))")
            }
            return extracted >= 1 ? (.partial, 0.5, "single screen; field \(String(format: "%.2f", fieldCompletenessScore))") : (.poor, 0.2, "expected 1, got \(extracted)")
        case .receipt, .subscriptionReceipt, .moneyTransfer, .failedTransactionNotice, .unknown:
            if coverage >= 0.9 && fieldCompletenessScore >= 0.85 {
                return (.complete, 0.85, "extracted \(extracted) vs \(expected); field \(String(format: "%.2f", fieldCompletenessScore))")
            }
            if coverage >= 0.75 && fieldCompletenessScore >= 0.7 {
                return (.likelyComplete, 0.65, "extracted \(extracted) vs \(expected); field \(String(format: "%.2f", fieldCompletenessScore))")
            }
            if extracted == 0 || fieldCompletenessScore < 0.4 {
                return (.poor, 0.25, "extracted \(extracted); field \(String(format: "%.2f", fieldCompletenessScore))")
            }
            return (.partial, 0.5, "extracted \(extracted) vs \(expected); field \(String(format: "%.2f", fieldCompletenessScore))")
        }
    }

    /// coverageScore for display: extracted/expected when expected > 0; else 0. Use expected from expectedTransactionCount.
    private static func coverageScore(extractedTransactions: Int, expectedTransactionCount: Int) -> Double {
        guard expectedTransactionCount > 0 else { return 0 }
        return Double(extractedTransactions) / Double(expectedTransactionCount)
    }

    /// Build debug report from phase1 and extracted items using screen-type aware completion.
    private static func buildExtractionDebugReport(imageIndex: Int, phase1: ExtractionPhase1Report, extractedItems: [ParsedTransactionItem], removedByDuplicate: Int, finallyShown: Int) -> ExtractionDebugReport {
        let fieldScore = fieldCompletenessScore(items: extractedItems)
        let expected = expectedTransactionCount(screenType: phase1.screenType, repeatedRowClusterCount: phase1.repeatedRowClusterCount, strongAmountRowCount: phase1.strongAmountRowCount, transactionLikeRowEstimate: phase1.transactionLikeRowEstimate)
        let (status, confidence, reason) = completionStatus(screenType: phase1.screenType, extracted: phase1.candidatesExtracted, expected: expected, fieldCompletenessScore: fieldScore, removedByValidation: phase1.removedByValidation, removedByDuplicate: removedByDuplicate)
        let cov = coverageScore(extractedTransactions: phase1.candidatesExtracted, expectedTransactionCount: expected)
        return ExtractionDebugReport(
            imageIndex: imageIndex,
            phase1: phase1,
            removedByDuplicate: removedByDuplicate,
            finallyShown: finallyShown,
            coverageScore: cov,
            extractionStatus: status,
            fieldCompletenessScore: fieldScore,
            completionConfidence: confidence,
            completionReason: reason,
            expectedTransactionCountPrimarySignal: expected
        )
    }

    /// Result of OCR block classification: row counts and transaction-like metrics for coverage/abstain logic.
    private struct ClassifyOcrResult {
        let rawRowLikeBlocks: Int
        let transactionLikeRowEstimate: Int
        let strongAmountRowCount: Int
        let repeatedRowClusterCount: Int
        /// Run-lengths of consecutive transactionCandidate blocks (for layout family row structure signature).
        let transactionCandidateRunLengths: [Int]
        /// Candidate row groups: each element is a run of consecutive transactionCandidate line strings. Extractor must classify each before emitting a transaction.
        let groupedTransactionRows: [[String]]
    }

    /// Returns classification result from OCR text using the block classifier.
    private static func classifyOcrBlocks(ocrText: String, classifier: BlockClassifier) -> ClassifyOcrResult {
        let lines = ocrLines(ocrText: ocrText)
        let raw = lines.count
        let classified = classifier.classify(lines: lines)
        let txEstimate = classified.filter { $0.label == .transactionCandidate }.count
        let strongAmountRowCount = strongAmountRowCountFromBlocks(classified)
        let repeatedRowClusterCount = repeatedRowClusterCountFromBlocks(classified)
        let runLengths = transactionCandidateRunLengthsFromBlocks(classified)
        let groupedRows = groupedTransactionRowsFromBlocks(classified)
        return ClassifyOcrResult(
            rawRowLikeBlocks: raw,
            transactionLikeRowEstimate: txEstimate,
            strongAmountRowCount: strongAmountRowCount,
            repeatedRowClusterCount: repeatedRowClusterCount,
            transactionCandidateRunLengths: runLengths,
            groupedTransactionRows: groupedRows
        )
    }

    /// Group consecutive transactionCandidate blocks into candidate row groups (each group = array of line strings).
    private static func groupedTransactionRowsFromBlocks(_ blocks: [ClassifiedBlock]) -> [[String]] {
        var result: [[String]] = []
        var current: [String] = []
        for block in blocks {
            if block.label == .transactionCandidate {
                current.append(block.text)
            } else {
                if !current.isEmpty {
                    result.append(current)
                    current = []
                }
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Run-lengths of consecutive transactionCandidate blocks (e.g. [2, 3, 2]).
    private static func transactionCandidateRunLengthsFromBlocks(_ blocks: [ClassifiedBlock]) -> [Int] {
        var lengths: [Int] = []
        var run = 0
        for block in blocks {
            if block.label == .transactionCandidate {
                run += 1
            } else {
                if run > 0 { lengths.append(run); run = 0 }
            }
        }
        if run > 0 { lengths.append(run) }
        return lengths
    }

    /// Lines that contain amount-like content and (date or merchant-like text). Uses same idea as block classifier.
    private static func strongAmountRowCountFromBlocks(_ blocks: [ClassifiedBlock]) -> Int {
        blocks.filter { block in
            guard block.label == .transactionCandidate else { return false }
            return lineHasDateOrMerchantLike(block.text)
        }.count
    }

    /// Number of clusters of 2+ consecutive transactionCandidate lines.
    private static func repeatedRowClusterCountFromBlocks(_ blocks: [ClassifiedBlock]) -> Int {
        var count = 0
        var runLength = 0
        for block in blocks {
            if block.label == .transactionCandidate {
                runLength += 1
            } else {
                if runLength >= 2 { count += 1 }
                runLength = 0
            }
        }
        if runLength >= 2 { count += 1 }
        return count
    }

    private static let dateLikePatterns = [
        #"\d{1,2}[-./]\d{1,2}[-./]\d{2,4}"#,
        #"\d{4}[-./]\d{1,2}[-./]\d{1,2}"#,
        #"(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+\d"#,
        #"\d{1,2}\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)"#
    ]

    private static func lineHasDateOrMerchantLike(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return false }
        for pattern in dateLikePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               regex.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil { return true }
        }
        let letterCount = t.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        return letterCount >= 2
    }

    /// One image: OCR → check digits → cache by hash → try local rules, else GPT → return (items, ocrText, hash, phase1). Throws on no numbers or GPT failure.
    private func recognizeAndParseOneImage(_ image: UIImage) async throws -> (items: [ParsedTransactionItem], ocrText: String, hash: String, phase1: ExtractionPhase1Report) {
        let hash = ocrService.imageHash(for: image)
        await MainActor.run { pipelinePhase = .computingHash }
        let hashPrefix = String(hash.prefix(8))
        if let cached = ParsingRulesStore.shared.cachedResult(forImageHash: hash), !cached.isEmpty {
            let ocrText = try await ocrService.recognizeText(from: image)
            let classResult = Self.classifyOcrBlocks(ocrText: ocrText, classifier: blockClassifier)
            let fromLocal = ParsingRulesStore.shared.tryMatch(ocrText: ocrText, parser: parser, baseCurrency: "USD") ?? []
            let merged = mergeParsedItems(base: cached, additional: fromLocal)
            let normalized = Self.normalizeMerchantsInItems(merged)
            if normalized.count > cached.count {
                await MainActor.run { pipelinePhase = .savingResult }
                ParsingRulesStore.shared.cacheResult(normalized, forImageHash: hash)
            }
            let candidatesCount = normalized.count
            let phase1 = ExtractionPhase1Report(
                source: .cache,
                imageSentToGPT: false,
                rawRowLikeBlocks: classResult.rawRowLikeBlocks,
                transactionLikeRowEstimate: classResult.transactionLikeRowEstimate,
                strongAmountRowCount: classResult.strongAmountRowCount,
                repeatedRowClusterCount: classResult.repeatedRowClusterCount,
                candidatesExtracted: candidatesCount,
                removedByValidation: 0,
                imageHashPrefix: hashPrefix,
                screenType: Self.inferScreenType(rawRowLikeBlocks: classResult.rawRowLikeBlocks, transactionLikeRowEstimate: classResult.transactionLikeRowEstimate, strongAmountRowCount: classResult.strongAmountRowCount, repeatedRowClusterCount: classResult.repeatedRowClusterCount, candidatesExtracted: candidatesCount),
                localRuleOutcome: nil,
                fallbackTriggered: false,
                matchedRuleId: nil,
                matchedRuleTrustStage: nil,
                reasonLocalRulesDidNotAbstain: nil,
                layoutFamilyId: nil,
                didLocalRulesHelpScreenType: false,
                didLocalRulesHelpRowGrouping: false,
                localAssistConfidence: 0,
                reasonForHardFail: nil,
                matchedLayoutFamilyId: nil,
                didLayoutFamilyMatch: false,
                didLocalImproveRowGrouping: false,
                didLocalImproveExpectedTransactionCount: false,
                didLocalReduceNeedForGPT: false,
                localStructureAssistConfidence: 0,
                layoutFamilySimilarityScore: nil,
                familyClusterSize: nil,
                wasFamilyReused: false,
                wasFamilyMerged: false,
                whyNewFamilyWasCreated: nil,
                localAssistConfidenceComputed: false,
                familyReuseReason: nil,
                matchedStructuralFeatures: nil,
                rejectedStructuralFeatures: nil,
                familyReuseThresholdUsed: nil,
                wasStrongReuse: false,
                wasWeakReuse: false,
                familyRejectionReason: nil,
                familyToleranceExceeded: nil,
                familyProfileSize: nil,
                familyProfileVariance: nil,
                localRowsGrouped: nil,
                localRowsParsed: nil,
                localValidAmountCount: nil,
                localValidMerchantCount: nil,
                localExtractionConfidence: nil,
                localExtractionDecision: nil,
                reasonGPTFallbackTriggered: nil,
                reasonGPTFallbackNotTriggered: nil
            )
            return (normalized, ocrText, hash, phase1)
        }
        let ocrText = try await ocrService.recognizeText(from: image)
        if !OCRService.containsDecimalDigits(ocrText) {
            throw OCRServiceError.noNumbersInImage
        }
        // Normalize once: removes empty lines so GPT offset counts match OCRTemplateMatcher
        let normalizedOcrText = Self.normalizedOCRTextForCoarse(ocrText)

        // --- OCR Template matching (fast local path) ---
        let ocrLinesForTemplate = normalizedOcrText.components(separatedBy: .newlines)
        let templateDiag = OCRTemplateMatcher.bestMatchWithDiagnostics(
            ocrLines: ocrLinesForTemplate, store: OCRTemplateStore.shared, baseCurrency: "USD")
        let tmplMatchTried = templateDiag.storeCount > 0
        let tmplBestConf = templateDiag.bestConfidence
        let tmplStoreCount = templateDiag.storeCount
        if let templateMatch = templateDiag.result {
            // Tag each item with the template id
            let taggedItems = templateMatch.items.map { item -> ParsedTransactionItem in
                var t = item
                t.extractedByTemplateId = templateMatch.templateId
                return t
            }
            let normalizedItems = Self.normalizeMerchantsInItems(taggedItems)
            if !normalizedItems.isEmpty {
                // Update useCount for the matched template
                if let existing = OCRTemplateStore.shared.all().first(where: { $0.id == templateMatch.templateId }) {
                    OCRTemplateStore.shared.upsert(existing)
                }
                var emptyPhase1 = ExtractionPhase1Report(
                    source: .localTemplate,
                    imageSentToGPT: false,
                    rawRowLikeBlocks: 0,
                    transactionLikeRowEstimate: normalizedItems.count,
                    strongAmountRowCount: normalizedItems.count,
                    repeatedRowClusterCount: 0,
                    candidatesExtracted: normalizedItems.count,
                    removedByValidation: 0,
                    imageHashPrefix: hashPrefix,
                    screenType: .transactionList,
                    localRuleOutcome: nil,
                    fallbackTriggered: false,
                    matchedRuleId: nil,
                    matchedRuleTrustStage: nil,
                    reasonLocalRulesDidNotAbstain: nil,
                    layoutFamilyId: nil,
                    didLocalRulesHelpScreenType: false,
                    didLocalRulesHelpRowGrouping: false,
                    localAssistConfidence: templateMatch.confidence,
                    reasonForHardFail: nil,
                    matchedLayoutFamilyId: nil,
                    didLayoutFamilyMatch: false,
                    didLocalImproveRowGrouping: false,
                    didLocalImproveExpectedTransactionCount: false,
                    didLocalReduceNeedForGPT: true,
                    localStructureAssistConfidence: templateMatch.confidence,
                    layoutFamilySimilarityScore: nil,
                    familyClusterSize: nil,
                    wasFamilyReused: false,
                    wasFamilyMerged: false,
                    whyNewFamilyWasCreated: nil,
                    localAssistConfidenceComputed: true,
                    familyReuseReason: "template:\(templateMatch.templateId.prefix(8))",
                    matchedStructuralFeatures: nil,
                    rejectedStructuralFeatures: nil,
                    familyReuseThresholdUsed: "0.95",
                    wasStrongReuse: templateMatch.confidence >= 0.95,
                    wasWeakReuse: false,
                    familyRejectionReason: nil,
                    familyToleranceExceeded: nil,
                    familyProfileSize: nil,
                    familyProfileVariance: nil,
                    localRowsGrouped: normalizedItems.count,
                    localRowsParsed: normalizedItems.count,
                    localValidAmountCount: normalizedItems.count,
                    localValidMerchantCount: normalizedItems.count,
                    localExtractionConfidence: templateMatch.confidence,
                    localExtractionDecision: "template",
                    reasonGPTFallbackTriggered: nil,
                    reasonGPTFallbackNotTriggered: .localExtractionAccepted
                )
                emptyPhase1.templateMatchTried = true
                emptyPhase1.templateMatchBestConfidence = tmplBestConf
                emptyPhase1.templateStoreCount = tmplStoreCount
                emptyPhase1.templateDerived = false
                return (normalizedItems, ocrText, hash, emptyPhase1)
            }
        }
        // ------------------------------------------------

        await MainActor.run { pipelinePhase = .localAnalysis }
        let classResult = Self.classifyOcrBlocks(ocrText: ocrText, classifier: blockClassifier)
        let rowSig = LayoutFamilyStore.rowStructureSignature(transactionCandidateRunLengths: classResult.transactionCandidateRunLengths)
        let normalizedForMatch = Self.normalizedOCRTextForCoarse(ocrText)
        let linesForAnchor = normalizedForMatch.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let amountAnchorBucket = LayoutFamilyStore.amountAnchorBucket(lines: linesForAnchor)
        let localResult = ParsingRulesStore.shared.tryStructureAssist(
            ocrText: ocrText,
            parser: parser,
            baseCurrency: "USD",
            transactionLikeRowEstimate: classResult.transactionLikeRowEstimate,
            strongAmountRowCount: classResult.strongAmountRowCount,
            repeatedRowClusterCount: classResult.repeatedRowClusterCount,
            rowStructureSignature: rowSig,
            amountAnchorBucket: amountAnchorBucket
        )
        if case .confidentParse = localResult.outcome, let localItems = localResult.items, !localItems.isEmpty {
            let items = Self.normalizeMerchantsInItems(localItems)
            ParsingRulesStore.shared.recordSuccessfulLocalUse(ruleId: localResult.matchedRuleId, imageHash: hash)
            let phase1 = ExtractionPhase1Report(
                source: .localRules,
                imageSentToGPT: false,
                rawRowLikeBlocks: classResult.rawRowLikeBlocks,
                transactionLikeRowEstimate: classResult.transactionLikeRowEstimate,
                strongAmountRowCount: classResult.strongAmountRowCount,
                repeatedRowClusterCount: classResult.repeatedRowClusterCount,
                candidatesExtracted: items.count,
                removedByValidation: 0,
                imageHashPrefix: hashPrefix,
                screenType: Self.inferScreenType(rawRowLikeBlocks: classResult.rawRowLikeBlocks, transactionLikeRowEstimate: classResult.transactionLikeRowEstimate, strongAmountRowCount: classResult.strongAmountRowCount, repeatedRowClusterCount: classResult.repeatedRowClusterCount, candidatesExtracted: items.count),
                localRuleOutcome: .confidentParse,
                fallbackTriggered: false,
                matchedRuleId: localResult.matchedRuleId,
                matchedRuleTrustStage: localResult.matchedRuleTrustStage,
                reasonLocalRulesDidNotAbstain: nil,
                layoutFamilyId: localResult.layoutFamilyId,
                didLocalRulesHelpScreenType: localResult.didHelpScreenType,
                didLocalRulesHelpRowGrouping: localResult.didHelpRowGrouping,
                localAssistConfidence: localResult.localAssistConfidence,
                reasonForHardFail: localResult.reasonForHardFail,
                matchedLayoutFamilyId: localResult.layoutFamilyId,
                didLayoutFamilyMatch: localResult.layoutFamilyId != nil,
                didLocalImproveRowGrouping: localResult.didHelpRowGrouping,
                didLocalImproveExpectedTransactionCount: false,
                didLocalReduceNeedForGPT: true,
                localStructureAssistConfidence: localResult.localAssistConfidence,
                layoutFamilySimilarityScore: localResult.layoutFamilySimilarityScore,
                familyClusterSize: localResult.familyClusterSize,
                wasFamilyReused: false,
                wasFamilyMerged: false,
                whyNewFamilyWasCreated: nil,
                localAssistConfidenceComputed: localResult.localAssistConfidenceComputed,
                familyReuseReason: localResult.familyReuseReason,
                matchedStructuralFeatures: localResult.matchedStructuralFeatures,
                rejectedStructuralFeatures: localResult.rejectedStructuralFeatures,
                familyReuseThresholdUsed: localResult.familyReuseThresholdUsed,
                wasStrongReuse: localResult.wasStrongReuse,
                wasWeakReuse: localResult.wasWeakReuse,
                familyRejectionReason: nil,
                familyToleranceExceeded: nil,
                familyProfileSize: localResult.familyClusterSize,
                familyProfileVariance: nil,
                localRowsGrouped: nil,
                localRowsParsed: nil,
                localValidAmountCount: nil,
                localValidMerchantCount: nil,
                localExtractionConfidence: nil,
                localExtractionDecision: nil,
                reasonGPTFallbackTriggered: nil,
                reasonGPTFallbackNotTriggered: .confidentParse
            )
            var p1 = phase1
            p1.templateMatchTried = tmplMatchTried
            p1.templateMatchBestConfidence = tmplBestConf
            p1.templateStoreCount = tmplStoreCount
            return (items, ocrText, hash, p1)
        }
        var gptFallbackReason: GPTFallbackReason? = nil
        var localExtractionReportGrouped: Int? = nil
        var localExtractionReportParsed: Int? = nil
        var localExtractionReportValidAmount: Int? = nil
        var localExtractionReportValidMerchant: Int? = nil
        var localExtractionReportConfidence: Double? = nil
        var localExtractionReportDecision: String? = nil
        if case .structureAssistOnly = localResult.outcome, let familyId = localResult.layoutFamilyId {
            let maturity = LayoutFamilyLearningStore.shared.maturityLevel(forFamilyId: familyId)
            let clusterSize = localResult.familyClusterSize ?? 0
            // apprentice: must meet minFamilyProfileSizeForLocalExtraction (legacy gate)
            // learning/proficient/expert: use maturity-aware extraction with archetype
            if maturity == .apprentice && clusterSize < Self.minFamilyProfileSizeForLocalExtraction {
                gptFallbackReason = .familyProfileSizeTooSmall
            } else if maturity == .apprentice {
                gptFallbackReason = .familyProfileSizeTooSmall
            } else {
                let groupedRows = classResult.groupedTransactionRows
                if groupedRows.isEmpty {
                    gptFallbackReason = .noGroupedRows
                } else {
                    let family = LayoutFamilyStore.shared.family(withId: familyId)
                    let archetype = LayoutFamilyLearningStore.shared.archetype(forFamilyId: familyId)
                    let extraction = LocalRowExtractor.extract(groupedRows: groupedRows, family: family, archetype: archetype, baseCurrency: "USD", dateFromContext: nil)
                    let totalRows = groupedRows.count
                    // Expert families get relaxed gates: archetype already filtered rows,
                    // so lower thresholds are warranted.
                    let isExpert = maturity == .expert
                    let (accepted, failReason) = isExpert
                        ? Self.localExtractionAcceptanceGatesRelaxed(
                            items: extraction.items,
                            validAmountCount: extraction.validAmountCount,
                            validMerchantCount: extraction.validMerchantCount,
                            validDateCount: extraction.validDateCount,
                            totalGroupedRows: totalRows,
                            excludedByStatusCount: extraction.excludedByStatusCount
                          )
                        : Self.localExtractionAcceptanceGates(
                            items: extraction.items,
                            validAmountCount: extraction.validAmountCount,
                            validMerchantCount: extraction.validMerchantCount,
                            validDateCount: extraction.validDateCount,
                            totalGroupedRows: totalRows,
                            excludedByStatusCount: extraction.excludedByStatusCount
                          )
                    localExtractionReportGrouped = totalRows
                    localExtractionReportParsed = totalRows
                    localExtractionReportValidAmount = extraction.validAmountCount
                    localExtractionReportValidMerchant = extraction.validMerchantCount
                    localExtractionReportConfidence = Self.localExtractionConfidenceScore(validAmountCount: extraction.validAmountCount, validMerchantCount: extraction.validMerchantCount, validDateCount: extraction.validDateCount, totalGroupedRows: totalRows)
                    // Archetype extraction disabled: template system replaces this path.
                    // Old archetype results were consistently wrong (wrong family matches).
                    if false && accepted {
                        LayoutFamilyLearningStore.shared.recordExtractionOutcome(familyId: familyId, imageHash: hash, wasAccepted: true, wasUserCorrected: false)
                        let items = Self.normalizeMerchantsInItems(extraction.items)
                        let phase1 = ExtractionPhase1Report(
                            source: .localExtraction,
                            imageSentToGPT: false,
                            rawRowLikeBlocks: classResult.rawRowLikeBlocks,
                            transactionLikeRowEstimate: classResult.transactionLikeRowEstimate,
                            strongAmountRowCount: classResult.strongAmountRowCount,
                            repeatedRowClusterCount: classResult.repeatedRowClusterCount,
                            candidatesExtracted: items.count,
                            removedByValidation: 0,
                            imageHashPrefix: hashPrefix,
                            screenType: Self.inferScreenType(rawRowLikeBlocks: classResult.rawRowLikeBlocks, transactionLikeRowEstimate: classResult.transactionLikeRowEstimate, strongAmountRowCount: classResult.strongAmountRowCount, repeatedRowClusterCount: classResult.repeatedRowClusterCount, candidatesExtracted: items.count),
                            localRuleOutcome: .structureAssistOnly,
                            fallbackTriggered: false,
                            matchedRuleId: nil,
                            matchedRuleTrustStage: nil,
                            reasonLocalRulesDidNotAbstain: nil,
                            layoutFamilyId: familyId,
                            didLocalRulesHelpScreenType: true,
                            didLocalRulesHelpRowGrouping: true,
                            localAssistConfidence: localResult.localAssistConfidence,
                            reasonForHardFail: nil,
                            matchedLayoutFamilyId: familyId,
                            didLayoutFamilyMatch: true,
                            didLocalImproveRowGrouping: true,
                            didLocalImproveExpectedTransactionCount: false,
                            didLocalReduceNeedForGPT: true,
                            localStructureAssistConfidence: localResult.localAssistConfidence,
                            layoutFamilySimilarityScore: localResult.layoutFamilySimilarityScore,
                            familyClusterSize: localResult.familyClusterSize,
                            wasFamilyReused: false,
                            wasFamilyMerged: false,
                            whyNewFamilyWasCreated: nil,
                            localAssistConfidenceComputed: localResult.localAssistConfidenceComputed,
                            familyReuseReason: localResult.familyReuseReason,
                            matchedStructuralFeatures: localResult.matchedStructuralFeatures,
                            rejectedStructuralFeatures: nil,
                            familyReuseThresholdUsed: localResult.familyReuseThresholdUsed,
                            wasStrongReuse: localResult.wasStrongReuse,
                            wasWeakReuse: localResult.wasWeakReuse,
                            familyRejectionReason: nil,
                            familyToleranceExceeded: nil,
                            familyProfileSize: localResult.familyClusterSize,
                            familyProfileVariance: nil,
                            localRowsGrouped: totalRows,
                            localRowsParsed: totalRows,
                            localValidAmountCount: extraction.validAmountCount,
                            localValidMerchantCount: extraction.validMerchantCount,
                            localExtractionConfidence: localExtractionReportConfidence,
                            localExtractionDecision: "used",
                            reasonGPTFallbackTriggered: nil,
                            reasonGPTFallbackNotTriggered: .localExtractionAccepted
                        )
                        return (items, ocrText, hash, phase1)
                    }
                    LayoutFamilyLearningStore.shared.recordExtractionOutcome(familyId: familyId, imageHash: hash, wasAccepted: false, wasUserCorrected: false)
                    LayoutFamilyLearningStore.shared.checkAndApplyDegradation(familyId: familyId)
                    gptFallbackReason = failReason
                    localExtractionReportDecision = "rejected"
                }
            }
        }
        let categories = CategoryStore.load().map { (id: $0.id, name: $0.name) }
        let subcategories = SubcategoryStore.load().map { (id: $0.id, name: $0.name, parentCategoryId: $0.parentCategoryId) }
        let imageBase64 = image.jpegData(compressionQuality: 0.7).map { $0.base64EncodedString() } ?? ""
        let imageSentToGPT = !imageBase64.isEmpty
        await MainActor.run { pipelinePhase = .gptFallback }
        let response: GPTExtractionResponse
        if imageSentToGPT {
            response = try await gptService.extractAndGetRulesFromImage(
                imageBase64: imageBase64,
                ocrText: normalizedOcrText,
                categories: categories,
                subcategories: subcategories,
                baseCurrency: "USD"
            )
        } else {
            response = try await gptService.extractAndGetRules(
                ocrText: normalizedOcrText,
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
        let successOnly = deduped.filter { $0.isSuccessStatus }
        let removedByValidation = response.transactions.count - successOnly.count

        // --- Derive and save OCR template ---
        var templateWasDerived = false
        if !successOnly.isEmpty {
            if let layout = response.layout,
               let rule = MerchantRule(rawValue: layout.merchantRule) {
                // GPT provided the OCR layout directly — use it as-is, no fuzzy search needed
                let template = OCRTemplateStore.shared.findByStructure(
                    merchantOffset: layout.merchantLineOffset,
                    dateOffset: layout.dateLineOffset,
                    rule: rule
                ) ?? OCRTemplate(
                    id: UUID().uuidString,
                    merchantLineOffset: layout.merchantLineOffset,
                    merchantExtractionRule: rule,
                    dateLineOffset: layout.dateLineOffset,
                    linesPerBlock: 3,
                    knownAmountPatterns: [],
                    useCount: 0,
                    lastUsed: Date(),
                    bankHint: nil
                )
                OCRTemplateStore.shared.upsert(template)
                templateWasDerived = true
            } else if let derived = OCRTemplateDeriver.derive(ocrLines: ocrLinesForTemplate, transactions: successOnly) {
                // Fallback: fuzzy-search derivation (text-only GPT path without OCR in prompt)
                OCRTemplateStore.shared.upsert(derived)
                templateWasDerived = true
            }
        }
        // -----------------------------------------------------------------------

        var items = successOnly.map { tx in
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
        items = Self.normalizeMerchantsInItems(items)
        await MainActor.run { pipelinePhase = .savingResult }
        ParsingRulesStore.shared.cacheResult(items, forImageHash: hash)
        let source: ExtractionSourceForReport = imageSentToGPT ? .gptVision : .gptOcrTextOnly
        // Persist layout family after successful GPT extraction for future structure-assist matching.
        let normalizedForCoarse = Self.normalizedOCRTextForCoarse(ocrText)
        let structuralFp = LayoutFamilyStore.structuralFingerprint(normalizedText: normalizedForCoarse)
        let coarseFp = LayoutFamilyStore.coarseFingerprint(normalizedText: normalizedForCoarse)
        let densityBucket = LayoutFamilyStore.densityBucket(normalizedText: normalizedForCoarse)
        let linesForFamilyAnchor = normalizedForCoarse.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let amountAnchorBucketForFamily = LayoutFamilyStore.amountAnchorBucket(lines: linesForFamilyAnchor)
        let inferredScreenType = Self.inferScreenType(rawRowLikeBlocks: classResult.rawRowLikeBlocks, transactionLikeRowEstimate: classResult.transactionLikeRowEstimate, strongAmountRowCount: classResult.strongAmountRowCount, repeatedRowClusterCount: classResult.repeatedRowClusterCount, candidatesExtracted: items.count)
        let family = LayoutFamily(
            screenType: inferredScreenType,
            rowStructureSignature: rowSig,
            amountAlignmentPattern: .unknown,
            merchantPlacementPattern: nil,
            dateTimePlacementPattern: nil,
            ignoreKeywords: [],
            failureKeywords: [],
            coarseFingerprint: coarseFp,
            structuralFingerprint: structuralFp,
            densityBucket: densityBucket,
            amountAnchorBucket: amountAnchorBucketForFamily
        )
        let addResult = LayoutFamilyStore.shared.addOrUpdate(family: family)
        let familyIdForLearning = addResult.familyId

        // Teacher-student learning: map GPT results back to OCR row groups and record structural examples.
        // This is the core of the self-learning loop: after N confirmed screenshots, the system builds
        // a RowArchetype and can extract locally without calling GPT.
        if !successOnly.isEmpty && !classResult.groupedTransactionRows.isEmpty {
            let mappingResult = GPTTeacherMapper.map(
                gptTransactions: successOnly,
                groupedOCRRows: classResult.groupedTransactionRows,
                familyId: familyIdForLearning,
                imageHash: hash
            )
            if mappingResult.mappingConfidence >= 0.65 && !mappingResult.examples.isEmpty {
                LayoutFamilyLearningStore.shared.recordConfirmedExamples(
                    mappingResult.examples,
                    familyId: familyIdForLearning,
                    imageHash: hash
                )
            }
        }

        var phase1 = ExtractionPhase1Report(
            source: source,
            imageSentToGPT: imageSentToGPT,
            rawRowLikeBlocks: classResult.rawRowLikeBlocks,
            transactionLikeRowEstimate: classResult.transactionLikeRowEstimate,
            strongAmountRowCount: classResult.strongAmountRowCount,
            repeatedRowClusterCount: classResult.repeatedRowClusterCount,
            candidatesExtracted: items.count,
            removedByValidation: removedByValidation,
            imageHashPrefix: hashPrefix,
            screenType: inferredScreenType,
            localRuleOutcome: localResult.outcome,
            fallbackTriggered: localResult.outcome != .confidentParse,
            matchedRuleId: localResult.matchedRuleId,
            matchedRuleTrustStage: localResult.matchedRuleTrustStage,
            reasonLocalRulesDidNotAbstain: localResult.reasonAbstain,
            layoutFamilyId: localResult.layoutFamilyId,
            didLocalRulesHelpScreenType: localResult.didHelpScreenType,
            didLocalRulesHelpRowGrouping: localResult.didHelpRowGrouping,
            localAssistConfidence: localResult.localAssistConfidence,
            reasonForHardFail: localResult.reasonForHardFail,
            matchedLayoutFamilyId: localResult.layoutFamilyId,
            didLayoutFamilyMatch: localResult.layoutFamilyId != nil,
            didLocalImproveRowGrouping: localResult.didHelpRowGrouping,
            didLocalImproveExpectedTransactionCount: false,
            didLocalReduceNeedForGPT: localResult.outcome == .confidentParse,
            localStructureAssistConfidence: localResult.localAssistConfidence,
            layoutFamilySimilarityScore: localResult.layoutFamilySimilarityScore,
            familyClusterSize: localResult.familyClusterSize ?? addResult.clusterSize,
            wasFamilyReused: addResult.reused,
            wasFamilyMerged: false,
            whyNewFamilyWasCreated: addResult.reused ? nil : addResult.reason,
            localAssistConfidenceComputed: localResult.localAssistConfidenceComputed,
            familyReuseReason: addResult.reused ? addResult.reason : "new",
            matchedStructuralFeatures: localResult.matchedStructuralFeatures,
            rejectedStructuralFeatures: localResult.rejectedStructuralFeatures,
            familyReuseThresholdUsed: localResult.familyReuseThresholdUsed,
            wasStrongReuse: localResult.wasStrongReuse,
            wasWeakReuse: localResult.wasWeakReuse,
            familyRejectionReason: localResult.familyRejectionReason,
            familyToleranceExceeded: localResult.familyToleranceExceeded,
            familyProfileSize: localResult.familyClusterSize ?? addResult.clusterSize,
            familyProfileVariance: nil,
            localRowsGrouped: localExtractionReportGrouped,
            localRowsParsed: localExtractionReportParsed,
            localValidAmountCount: localExtractionReportValidAmount,
            localValidMerchantCount: localExtractionReportValidMerchant,
            localExtractionConfidence: localExtractionReportConfidence,
            localExtractionDecision: localExtractionReportDecision,
            reasonGPTFallbackTriggered: gptFallbackReason ?? .noFamilyMatch,
            reasonGPTFallbackNotTriggered: nil
        )
        phase1.templateMatchTried = tmplMatchTried
        phase1.templateMatchBestConfidence = tmplBestConf
        phase1.templateStoreCount = tmplStoreCount
        phase1.templateDerived = templateWasDerived
        return (items, ocrText, hash, phase1)
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
                    let classification = LocalDataStore.shared.duplicateClassification(merchant: item.merchant, date: item.date, amount: amt, includePending: false)
                    let probableId: String? = if case .probableDuplicate(let id) = classification { id } else { nil }
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
                        subcategory: sub,
                        probableDuplicateOfId: probableId,
                        extractedByTemplateId: item.extractedByTemplateId
                    )
                    LocalDataStore.shared.addPendingTransaction(
                        payload: payload,
                        ocrText: String(p.ocrText.prefix(2000)),
                        sourceImageHash: p.hash,
                        sourceFamilyId: p.familyId,
                        sourceTemplateId: item.extractedByTemplateId
                    )
                }
            }
            pendingToAddBatches = nil
            hasUnreviewedResults = false
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
            let classification = LocalDataStore.shared.duplicateClassification(merchant: item.merchant, date: item.date, amount: amt, includePending: false)
            let probableId: String? = if case .probableDuplicate(let id) = classification { id } else { nil }
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
                subcategory: sub,
                probableDuplicateOfId: probableId,
                extractedByTemplateId: item.extractedByTemplateId
            )
            LocalDataStore.shared.addPendingTransaction(
                payload: payload,
                ocrText: String(p.ocrText.prefix(2000)),
                sourceImageHash: p.hash,
                sourceFamilyId: p.familyId,
                sourceTemplateId: item.extractedByTemplateId
            )
        }
        pendingToAdd = nil
        hasUnreviewedResults = false
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

    // MARK: - Foreground recovery & background scheduling

    /// Resets items stuck in .processing (e.g. after app suspension) back to .pending and restarts the queue.
    /// Always cancels the old task and restarts — even if isAnalyzing is true — because the old task
    /// may be sleeping inside a rate-limit backoff and won't respond to foreground recovery otherwise.
    @MainActor
    func resumeIfNeeded() {
        for idx in imageQueue.indices where imageQueue[idx].status == .processing {
            imageQueue[idx].status = .pending
        }
        guard imageQueue.contains(where: { $0.status == .pending }) else { return }
        // Cancel any stuck or sleeping old task; restart processQueue directly so we don't
        // clear liveExtractedItems (which startQueueProcessing() would wipe).
        analysisTask?.cancel()
        isAnalyzing = true
        pipelinePhase = .imageSelected
        if importLiveActivity == nil {
            startImportLiveActivity()
        } else {
            updateImportLiveActivity()
        }
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.processQueue()
        }
        analysisTask = task
    }

    /// Schedules a BGProcessingTask so iOS can continue processing the queue in the background.
    func scheduleBackgroundProcessingIfNeeded() {
        guard remainingQueueCount > 0 else { return }
        if #available(iOS 13.0, *) {
            let request = BGProcessingTaskRequest(identifier: "ai.airy.imageProcessing")
            request.requiresNetworkConnectivity = true
            request.requiresExternalPower = false
            try? BGTaskScheduler.shared.submit(request)
        }
    }

    /// Called by BGTaskScheduler when iOS grants background execution time.
    @available(iOS 13.0, *)
    func handleBackgroundTask(_ task: BGProcessingTask) {
        task.expirationHandler = { [weak self] in
            self?.analysisTask?.cancel()
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Reset stuck items and reschedule remainder for next opportunity.
                for idx in imageQueue.indices where imageQueue[idx].status == .processing {
                    imageQueue[idx].status = .pending
                }
                scheduleBackgroundProcessingIfNeeded()
                task.setTaskCompleted(success: false)
            }
        }
        Task { @MainActor [weak self] in
            guard let self else { task.setTaskCompleted(success: false); return }
            resumeIfNeeded()
            // Poll until processing finishes or the expiration handler fires.
            while isAnalyzing {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            task.setTaskCompleted(success: true)
        }
    }

    // MARK: - Live Activity (Dynamic Island)

    /// Starts a Live Activity showing import progress. No-op on iOS < 16.2 or if disabled by user.
    @MainActor
    func startImportLiveActivity() {
        guard #available(iOS 16.2, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let processed = imageQueue.filter { $0.status == .completed || $0.status == .failed }.count
        let state = AiryImportAttributes.ContentState(processed: processed, total: imageQueue.count)
        let content = ActivityContent(state: state, staleDate: nil)
        importLiveActivity = try? Activity.request(
            attributes: AiryImportAttributes(),
            content: content,
            pushType: nil
        )
    }

    /// Updates the Live Activity with current queue progress and last completed transaction.
    @MainActor
    func updateImportLiveActivity() {
        guard #available(iOS 16.2, *) else { return }
        guard let activity = importLiveActivity else { return }
        let processed = imageQueue.filter { $0.status == .completed || $0.status == .failed }.count
        let lastItem = liveExtractedItems.last.map { item in
            AiryImportAttributes.LiveActivityItem(
                merchant: item.merchant ?? "Unknown merchant",
                amount: formatLiveActivityAmount(item)
            )
        }
        let state = AiryImportAttributes.ContentState(
            processed: processed,
            total: imageQueue.count,
            lastCompletedItem: lastItem
        )
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    /// Ends the Live Activity. Dismisses after 5 seconds so user can see final state.
    @MainActor
    func endImportLiveActivity() {
        guard #available(iOS 16.2, *) else { return }
        guard let activity = importLiveActivity else { return }
        let lastItem = liveExtractedItems.last.map { item in
            AiryImportAttributes.LiveActivityItem(
                merchant: item.merchant ?? "Unknown merchant",
                amount: formatLiveActivityAmount(item)
            )
        }
        let final = AiryImportAttributes.ContentState(
            processed: imageQueue.count,
            total: imageQueue.count,
            lastCompletedItem: lastItem
        )
        Task {
            await activity.end(ActivityContent(state: final, staleDate: nil), dismissalPolicy: .after(.now + 5))
        }
        importLiveActivity = nil
    }

    private func formatLiveActivityAmount(_ item: ParsedTransactionItem) -> String {
        let prefix = item.isCredit ? "+" : "-"
        let symbol = item.currency == "USD" ? "$" : item.currency
        return "\(prefix)\(symbol)\(String(format: "%.2f", item.amount))"
    }

    // MARK: - Local Notifications

    /// Requests notification permission (call once at first import start).
    func requestNotificationPermissionIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Sends a local notification when background import finishes.
    func sendImportCompletionNotification(count: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Airy"
        content.body = count > 0
            ? "\(count) transaction\(count == 1 ? "" : "s") extracted and ready to review"
            : "Import complete — no new transactions found"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "ai.airy.import.done.\(UUID().uuidString)",
            content: content,
            trigger: nil  // deliver immediately
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - CSV export

    /// Exports lastExtractionReports + per-image items as a CSV file. Returns a file URL or nil on failure.
    func exportDebugReportsAsCSV() -> URL? {
        var lines: [String] = []
        // Header rows
        let imgHeader = "type,imageIndex,source,imageSentToGPT,extractedTransactions,coverageScore,extractionStatus,screenType,fieldCompletenessScore,completionConfidence,removedByValidation,removedByDuplicate,finallyShown,rawRowLikeBlocks,transactionLikeRowEstimate,strongAmountRowCount,repeatedRowClusterCount,fallbackTriggered,localRuleOutcome,localExtractionConfidence,localExtractionDecision,layoutFamilyId,wasFamilyReused,familyClusterSize,layoutFamilySimilarityScore,wasStrongReuse,wasWeakReuse,imageHashPrefix,templateMatchTried,templateMatchBestConfidence,templateStoreCount,templateDerived"
        let txHeader = "type,imageIndex,merchant,amount,currency,date,time,category,subcategory,isCredit"
        lines.append(imgHeader)
        lines.append(txHeader)
        lines.append("---")

        for (i, report) in lastExtractionReports.enumerated() {
            let items = i < lastExtractionReportItems.count ? lastExtractionReportItems[i] : []
            func esc(_ s: String?) -> String {
                guard let s else { return "" }
                if s.contains(",") || s.contains("\"") || s.contains("\n") {
                    return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                }
                return s
            }
            let imgLine = [
                "[IMG]",
                "\(report.imageIndex)",
                esc(report.source.rawValue),
                report.imageSentToGPT ? "true" : "false",
                "\(report.extractedTransactions)",
                String(format: "%.3f", report.coverageScore),
                esc(report.extractionStatus.rawValue),
                esc(report.screenType.rawValue),
                String(format: "%.3f", report.fieldCompletenessScore),
                String(format: "%.3f", report.completionConfidence),
                "\(report.removedByValidation)",
                "\(report.removedByDuplicate)",
                "\(report.finallyShown)",
                "\(report.rawRowLikeBlocks)",
                "\(report.transactionLikeRowEstimate)",
                "\(report.strongAmountRowCount)",
                "\(report.repeatedRowClusterCount)",
                report.fallbackTriggered ? "true" : "false",
                esc(report.localRuleOutcome?.rawValue),
                report.localExtractionConfidence.map { String(format: "%.3f", $0) } ?? "",
                esc(report.localExtractionDecision),
                esc(report.layoutFamilyId.map { String($0.prefix(8)) }),
                report.wasFamilyReused ? "true" : "false",
                report.familyClusterSize.map { "\($0)" } ?? "",
                report.layoutFamilySimilarityScore.map { String(format: "%.3f", $0) } ?? "",
                report.wasStrongReuse ? "true" : "false",
                report.wasWeakReuse ? "true" : "false",
                esc(report.imageHashPrefix),
                report.templateMatchTried ? "true" : "false",
                String(format: "%.3f", report.templateMatchBestConfidence),
                "\(report.templateStoreCount)",
                report.templateDerived ? "true" : "false"
            ].joined(separator: ",")
            lines.append(imgLine)

            for item in items {
                let txLine = [
                    "[TX]",
                    "\(report.imageIndex)",
                    esc(item.merchant),
                    String(format: "%.2f", item.amount),
                    esc(item.currency),
                    esc(item.date),
                    esc(item.time),
                    esc(item.categoryId),
                    esc(item.subcategoryId),
                    item.isCredit ? "true" : "false"
                ].joined(separator: ",")
                lines.append(txLine)
            }
        }

        let csv = lines.joined(separator: "\n")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        let name = "debug_report_\(formatter.string(from: Date())).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        guard let data = csv.data(using: .utf8) else { return nil }
        try? data.write(to: url)
        return url
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

// MARK: - Extraction debug report (in same file so @Observable macro sees the type)

enum ExtractionSourceForReport: String {
    case cache
    case localRules
    case localExtraction
    case localTemplate
    case gptVision
    case gptOcrTextOnly
    case none  // e.g. no numbers in image
}

/// Structured reason why GPT fallback was triggered (when we did call GPT).
enum GPTFallbackReason: String {
    case noFamilyMatch
    case familyProfileSizeTooSmall
    case noGroupedRows
    case lowAmountCoverage
    case lowMerchantCoverage
    case lowOverallConfidence
    case noValidItems
    case suspiciousStatusRows
}

/// Structured reason why GPT was not triggered.
enum GPTNotTriggeredReason: String {
    case confidentParse
    case localExtractionAccepted
}

/// Status derived from screen-type aware completion (expected count, field completeness, coverage).
enum ExtractionStatus: String {
    case complete
    case likelyComplete
    case partial
    case poor
    case failed
    case noTransactionRows  // no transaction-like content, no denominator
}

/// Phase-1 data from recognizeAndParseOneImage; caller adds removedByDuplicate, finallyShown, completion fields.
struct ExtractionPhase1Report {
    let source: ExtractionSourceForReport
    let imageSentToGPT: Bool
    let rawRowLikeBlocks: Int
    let transactionLikeRowEstimate: Int
    let strongAmountRowCount: Int
    let repeatedRowClusterCount: Int
    let candidatesExtracted: Int
    let removedByValidation: Int
    let imageHashPrefix: String?
    /// Inferred from row counts and candidates (transactionList, singlePaymentConfirmation, etc.).
    let screenType: ScreenType
    /// Set when local rules were tried; nil when source is cache or no local attempt.
    let localRuleOutcome: LocalRuleOutcome?
    /// True when we fell back to GPT after local rules returned abstain or hardFail.
    let fallbackTriggered: Bool
    let matchedRuleId: String?
    let matchedRuleTrustStage: RuleTrustStage?
    /// When source is localRules: why we did not abstain; when fallbackTriggered: reason local abstained/failed.
    let reasonLocalRulesDidNotAbstain: String?
    /// Matched layout family id (when structure-assist matched).
    let layoutFamilyId: String?
    /// Local rules suggested screen type from matched family.
    let didLocalRulesHelpScreenType: Bool
    /// Local rules helped row grouping.
    let didLocalRulesHelpRowGrouping: Bool
    /// Confidence 0...1 that structure assist was useful.
    let localAssistConfidence: Double
    /// When outcome is hardFail or noMatch, short reason.
    let reasonForHardFail: String?
    /// Same as layoutFamilyId; for debug observability label.
    let matchedLayoutFamilyId: String?
    /// True when a layout family was matched (exact or bucket).
    let didLayoutFamilyMatch: Bool
    /// Local rules improved row grouping (from matched family).
    let didLocalImproveRowGrouping: Bool
    /// True when matched family's expected-count hint was used; false for now.
    let didLocalImproveExpectedTransactionCount: Bool
    /// True when outcome was confidentParse (local returned items, no GPT).
    let didLocalReduceNeedForGPT: Bool
    /// Confidence 0...1 that structure assist was useful (same as localAssistConfidence).
    let localStructureAssistConfidence: Double
    /// 1.0 = exact structural match, ~0.5 = bucket-only; nil if no match.
    let layoutFamilySimilarityScore: Double?
    /// useCount of matched family or addOrUpdate result; nil if no match.
    let familyClusterSize: Int?
    /// True if we reused an existing family when saving (addOrUpdate).
    let wasFamilyReused: Bool
    /// True if two families were merged into one (future).
    let wasFamilyMerged: Bool
    /// When a new family was created, short reason; nil if family was reused.
    let whyNewFamilyWasCreated: String?
    /// True when localAssistConfidence was computed from match type.
    let localAssistConfidenceComputed: Bool
    /// Why we reused a family: "strong", "weak", "new", or nil if no match / not applicable.
    let familyReuseReason: String?
    /// Which structural features matched (e.g. "exact" or "lineBucket,density,screenType").
    let matchedStructuralFeatures: String?
    /// When weak reuse was considered but rejected (e.g. "density mismatch").
    let rejectedStructuralFeatures: String?
    /// Threshold used: "strong", "weak", or "none".
    let familyReuseThresholdUsed: String?
    /// True when match was exact structuralFingerprint.
    let wasStrongReuse: Bool
    /// True when match was fallback (bucket + screenType + densityBucket).
    let wasWeakReuse: Bool
    /// When no family matched: reason (hard identity or soft tolerance).
    let familyRejectionReason: String?
    /// Which band was exceeded (lineCountVariance, densityVariance, rowSigVariance, etc.).
    let familyToleranceExceeded: String?
    /// For matched family: e.g. useCount or number of representatives.
    let familyProfileSize: Int?
    /// Optional summary of profile (e.g. "lines L25+L50, density normal(+compact), anchor right").
    let familyProfileVariance: String?
    /// Local extraction: number of grouped rows (candidate runs).
    let localRowsGrouped: Int?
    let localRowsParsed: Int?
    let localValidAmountCount: Int?
    let localValidMerchantCount: Int?
    let localExtractionConfidence: Double?
    let localExtractionDecision: String?
    /// When GPT was called: structured reason.
    let reasonGPTFallbackTriggered: GPTFallbackReason?
    /// When GPT was not called: structured reason.
    let reasonGPTFallbackNotTriggered: GPTNotTriggeredReason?
    /// Template diagnostics — populated regardless of whether template matched.
    var templateMatchTried: Bool = false
    var templateMatchBestConfidence: Double = 0
    var templateStoreCount: Int = 0
    var templateDerived: Bool = false
}

/// Full per-screenshot debug report for observability.
struct ExtractionDebugReport: Identifiable {
    let id: UUID
    let imageIndex: Int
    let source: ExtractionSourceForReport
    let imageSentToGPT: Bool
    let rawRowLikeBlocks: Int
    let transactionLikeRowEstimate: Int
    let strongAmountRowCount: Int
    let repeatedRowClusterCount: Int
    let extractedTransactions: Int
    let coverageScore: Double
    let extractionStatus: ExtractionStatus
    let removedByValidation: Int
    let removedByDuplicate: Int
    let finallyShown: Int
    let imageHashPrefix: String?
    let screenType: ScreenType
    let fieldCompletenessScore: Double
    let completionConfidence: Double
    let completionReason: String?
    let expectedTransactionCountPrimarySignal: Int?
    let localRuleOutcome: LocalRuleOutcome?
    let fallbackTriggered: Bool
    let matchedRuleId: String?
    let matchedRuleTrustStage: RuleTrustStage?
    let reasonLocalRulesDidNotAbstain: String?
    let layoutFamilyId: String?
    let didLocalRulesHelpScreenType: Bool
    let didLocalRulesHelpRowGrouping: Bool
    let localAssistConfidence: Double
    let reasonForHardFail: String?
    let matchedLayoutFamilyId: String?
    let didLayoutFamilyMatch: Bool
    let didLocalImproveRowGrouping: Bool
    let didLocalImproveExpectedTransactionCount: Bool
    let didLocalReduceNeedForGPT: Bool
    let localStructureAssistConfidence: Double
    let layoutFamilySimilarityScore: Double?
    let familyClusterSize: Int?
    let wasFamilyReused: Bool
    let wasFamilyMerged: Bool
    let whyNewFamilyWasCreated: String?
    let localAssistConfidenceComputed: Bool
    let familyReuseReason: String?
    let matchedStructuralFeatures: String?
    let rejectedStructuralFeatures: String?
    let familyReuseThresholdUsed: String?
    let wasStrongReuse: Bool
    let wasWeakReuse: Bool
    let familyRejectionReason: String?
    let familyToleranceExceeded: String?
    let familyProfileSize: Int?
    let familyProfileVariance: String?
    let localRowsGrouped: Int?
    let localRowsParsed: Int?
    let localValidAmountCount: Int?
    let localValidMerchantCount: Int?
    let localExtractionConfidence: Double?
    let localExtractionDecision: String?
    let reasonGPTFallbackTriggered: GPTFallbackReason?
    let reasonGPTFallbackNotTriggered: GPTNotTriggeredReason?
    let templateMatchTried: Bool
    let templateMatchBestConfidence: Double
    let templateStoreCount: Int
    let templateDerived: Bool

    init(
        id: UUID = UUID(),
        imageIndex: Int,
        source: ExtractionSourceForReport,
        imageSentToGPT: Bool,
        rawRowLikeBlocks: Int,
        transactionLikeRowEstimate: Int,
        strongAmountRowCount: Int = 0,
        repeatedRowClusterCount: Int = 0,
        extractedTransactions: Int,
        coverageScore: Double,
        extractionStatus: ExtractionStatus,
        removedByValidation: Int,
        removedByDuplicate: Int,
        finallyShown: Int,
        imageHashPrefix: String?,
        screenType: ScreenType = .unknown,
        fieldCompletenessScore: Double = 0,
        completionConfidence: Double = 0,
        completionReason: String? = nil,
        expectedTransactionCountPrimarySignal: Int? = nil,
        localRuleOutcome: LocalRuleOutcome? = nil,
        fallbackTriggered: Bool = false,
        matchedRuleId: String? = nil,
        matchedRuleTrustStage: RuleTrustStage? = nil,
        reasonLocalRulesDidNotAbstain: String? = nil,
        layoutFamilyId: String? = nil,
        didLocalRulesHelpScreenType: Bool = false,
        didLocalRulesHelpRowGrouping: Bool = false,
        localAssistConfidence: Double = 0,
        reasonForHardFail: String? = nil,
        matchedLayoutFamilyId: String? = nil,
        didLayoutFamilyMatch: Bool = false,
        didLocalImproveRowGrouping: Bool = false,
        didLocalImproveExpectedTransactionCount: Bool = false,
        didLocalReduceNeedForGPT: Bool = false,
        localStructureAssistConfidence: Double = 0,
        layoutFamilySimilarityScore: Double? = nil,
        familyClusterSize: Int? = nil,
        wasFamilyReused: Bool = false,
        wasFamilyMerged: Bool = false,
        whyNewFamilyWasCreated: String? = nil,
        localAssistConfidenceComputed: Bool = false,
        familyReuseReason: String? = nil,
        matchedStructuralFeatures: String? = nil,
        rejectedStructuralFeatures: String? = nil,
        familyReuseThresholdUsed: String? = nil,
        wasStrongReuse: Bool = false,
        wasWeakReuse: Bool = false,
        familyRejectionReason: String? = nil,
        familyToleranceExceeded: String? = nil,
        familyProfileSize: Int? = nil,
        familyProfileVariance: String? = nil,
        localRowsGrouped: Int? = nil,
        localRowsParsed: Int? = nil,
        localValidAmountCount: Int? = nil,
        localValidMerchantCount: Int? = nil,
        localExtractionConfidence: Double? = nil,
        localExtractionDecision: String? = nil,
        reasonGPTFallbackTriggered: GPTFallbackReason? = nil,
        reasonGPTFallbackNotTriggered: GPTNotTriggeredReason? = nil,
        templateMatchTried: Bool = false,
        templateMatchBestConfidence: Double = 0,
        templateStoreCount: Int = 0,
        templateDerived: Bool = false
    ) {
        self.id = id
        self.imageIndex = imageIndex
        self.source = source
        self.imageSentToGPT = imageSentToGPT
        self.rawRowLikeBlocks = rawRowLikeBlocks
        self.transactionLikeRowEstimate = transactionLikeRowEstimate
        self.strongAmountRowCount = strongAmountRowCount
        self.repeatedRowClusterCount = repeatedRowClusterCount
        self.extractedTransactions = extractedTransactions
        self.coverageScore = coverageScore
        self.extractionStatus = extractionStatus
        self.removedByValidation = removedByValidation
        self.removedByDuplicate = removedByDuplicate
        self.finallyShown = finallyShown
        self.imageHashPrefix = imageHashPrefix
        self.screenType = screenType
        self.fieldCompletenessScore = fieldCompletenessScore
        self.completionConfidence = completionConfidence
        self.completionReason = completionReason
        self.expectedTransactionCountPrimarySignal = expectedTransactionCountPrimarySignal
        self.localRuleOutcome = localRuleOutcome
        self.fallbackTriggered = fallbackTriggered
        self.matchedRuleId = matchedRuleId
        self.matchedRuleTrustStage = matchedRuleTrustStage
        self.reasonLocalRulesDidNotAbstain = reasonLocalRulesDidNotAbstain
        self.layoutFamilyId = layoutFamilyId
        self.didLocalRulesHelpScreenType = didLocalRulesHelpScreenType
        self.didLocalRulesHelpRowGrouping = didLocalRulesHelpRowGrouping
        self.localAssistConfidence = localAssistConfidence
        self.reasonForHardFail = reasonForHardFail
        self.matchedLayoutFamilyId = matchedLayoutFamilyId
        self.didLayoutFamilyMatch = didLayoutFamilyMatch
        self.didLocalImproveRowGrouping = didLocalImproveRowGrouping
        self.didLocalImproveExpectedTransactionCount = didLocalImproveExpectedTransactionCount
        self.didLocalReduceNeedForGPT = didLocalReduceNeedForGPT
        self.localStructureAssistConfidence = localStructureAssistConfidence
        self.layoutFamilySimilarityScore = layoutFamilySimilarityScore
        self.familyClusterSize = familyClusterSize
        self.wasFamilyReused = wasFamilyReused
        self.wasFamilyMerged = wasFamilyMerged
        self.whyNewFamilyWasCreated = whyNewFamilyWasCreated
        self.localAssistConfidenceComputed = localAssistConfidenceComputed
        self.familyReuseReason = familyReuseReason
        self.matchedStructuralFeatures = matchedStructuralFeatures
        self.rejectedStructuralFeatures = rejectedStructuralFeatures
        self.familyReuseThresholdUsed = familyReuseThresholdUsed
        self.wasStrongReuse = wasStrongReuse
        self.wasWeakReuse = wasWeakReuse
        self.familyRejectionReason = familyRejectionReason
        self.familyToleranceExceeded = familyToleranceExceeded
        self.familyProfileSize = familyProfileSize
        self.familyProfileVariance = familyProfileVariance
        self.localRowsGrouped = localRowsGrouped
        self.localRowsParsed = localRowsParsed
        self.localValidAmountCount = localValidAmountCount
        self.localValidMerchantCount = localValidMerchantCount
        self.localExtractionConfidence = localExtractionConfidence
        self.localExtractionDecision = localExtractionDecision
        self.reasonGPTFallbackTriggered = reasonGPTFallbackTriggered
        self.reasonGPTFallbackNotTriggered = reasonGPTFallbackNotTriggered
        self.templateMatchTried = templateMatchTried
        self.templateMatchBestConfidence = templateMatchBestConfidence
        self.templateStoreCount = templateStoreCount
        self.templateDerived = templateDerived
    }

    init(imageIndex: Int, phase1: ExtractionPhase1Report, removedByDuplicate: Int, finallyShown: Int, coverageScore: Double, extractionStatus: ExtractionStatus, fieldCompletenessScore: Double, completionConfidence: Double, completionReason: String?, expectedTransactionCountPrimarySignal: Int?) {
        self.id = UUID()
        self.imageIndex = imageIndex
        self.source = phase1.source
        self.imageSentToGPT = phase1.imageSentToGPT
        self.rawRowLikeBlocks = phase1.rawRowLikeBlocks
        self.transactionLikeRowEstimate = phase1.transactionLikeRowEstimate
        self.strongAmountRowCount = phase1.strongAmountRowCount
        self.repeatedRowClusterCount = phase1.repeatedRowClusterCount
        self.extractedTransactions = phase1.candidatesExtracted
        self.coverageScore = coverageScore
        self.extractionStatus = extractionStatus
        self.removedByValidation = phase1.removedByValidation
        self.removedByDuplicate = removedByDuplicate
        self.finallyShown = finallyShown
        self.imageHashPrefix = phase1.imageHashPrefix
        self.screenType = phase1.screenType
        self.fieldCompletenessScore = fieldCompletenessScore
        self.completionConfidence = completionConfidence
        self.completionReason = completionReason
        self.expectedTransactionCountPrimarySignal = expectedTransactionCountPrimarySignal
        self.localRuleOutcome = phase1.localRuleOutcome
        self.fallbackTriggered = phase1.fallbackTriggered
        self.matchedRuleId = phase1.matchedRuleId
        self.matchedRuleTrustStage = phase1.matchedRuleTrustStage
        self.reasonLocalRulesDidNotAbstain = phase1.reasonLocalRulesDidNotAbstain
        self.layoutFamilyId = phase1.layoutFamilyId
        self.didLocalRulesHelpScreenType = phase1.didLocalRulesHelpScreenType
        self.didLocalRulesHelpRowGrouping = phase1.didLocalRulesHelpRowGrouping
        self.localAssistConfidence = phase1.localAssistConfidence
        self.reasonForHardFail = phase1.reasonForHardFail
        self.matchedLayoutFamilyId = phase1.matchedLayoutFamilyId
        self.didLayoutFamilyMatch = phase1.didLayoutFamilyMatch
        self.didLocalImproveRowGrouping = phase1.didLocalImproveRowGrouping
        self.didLocalImproveExpectedTransactionCount = phase1.didLocalImproveExpectedTransactionCount
        self.didLocalReduceNeedForGPT = phase1.didLocalReduceNeedForGPT
        self.localStructureAssistConfidence = phase1.localStructureAssistConfidence
        self.layoutFamilySimilarityScore = phase1.layoutFamilySimilarityScore
        self.familyClusterSize = phase1.familyClusterSize
        self.wasFamilyReused = phase1.wasFamilyReused
        self.wasFamilyMerged = phase1.wasFamilyMerged
        self.whyNewFamilyWasCreated = phase1.whyNewFamilyWasCreated
        self.localAssistConfidenceComputed = phase1.localAssistConfidenceComputed
        self.familyReuseReason = phase1.familyReuseReason
        self.matchedStructuralFeatures = phase1.matchedStructuralFeatures
        self.rejectedStructuralFeatures = phase1.rejectedStructuralFeatures
        self.familyReuseThresholdUsed = phase1.familyReuseThresholdUsed
        self.wasStrongReuse = phase1.wasStrongReuse
        self.wasWeakReuse = phase1.wasWeakReuse
        self.familyRejectionReason = phase1.familyRejectionReason
        self.familyToleranceExceeded = phase1.familyToleranceExceeded
        self.familyProfileSize = phase1.familyProfileSize
        self.familyProfileVariance = phase1.familyProfileVariance
        self.localRowsGrouped = phase1.localRowsGrouped
        self.localRowsParsed = phase1.localRowsParsed
        self.localValidAmountCount = phase1.localValidAmountCount
        self.localValidMerchantCount = phase1.localValidMerchantCount
        self.localExtractionConfidence = phase1.localExtractionConfidence
        self.localExtractionDecision = phase1.localExtractionDecision
        self.reasonGPTFallbackTriggered = phase1.reasonGPTFallbackTriggered
        self.reasonGPTFallbackNotTriggered = phase1.reasonGPTFallbackNotTriggered
        self.templateMatchTried = phase1.templateMatchTried
        self.templateMatchBestConfidence = phase1.templateMatchBestConfidence
        self.templateStoreCount = phase1.templateStoreCount
        self.templateDerived = phase1.templateDerived
    }
}
