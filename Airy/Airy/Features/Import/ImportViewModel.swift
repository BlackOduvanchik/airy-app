//
//  ImportViewModel.swift
//  Airy
//
//  Image import pipeline: OCR → ExtractionPipeline (cache + GPT) → pending transactions.
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
    /// Total duplicates removed across all images in current queue run (for UI feedback).
    var duplicatesSkippedCount: Int = 0

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

    /// Number of images processed concurrently. Reduced on rate-limit, restored on success streak.
    private var concurrencyLevel: Int = 3
    private var consecutiveSuccesses: Int = 0

    /// Generic labels that must not be used as merchant; replaced with "Other".
    private static let genericMerchantValues: Set<String> = [
        "покупка", "purchase", "payment", "transaction", "оплата", "withdrawal",
        "payout", "transfer", "sale", "expense"
    ]

    /// Returns "Other" if merchant is nil, empty, or a generic label; otherwise returns trimmed merchant.
    static func normalizeMerchant(_ raw: String?) -> String? {
        let s = (raw ?? "").trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return "Other" }
        if genericMerchantValues.contains(s.lowercased()) { return "Other" }
        return s
    }

    /// Apply normalizeMerchant to every item so cache and pipeline results never show generic labels.
    static func normalizeMerchantsInItems(_ items: [ParsedTransactionItem]) -> [ParsedTransactionItem] {
        items.map { item in
            var copy = item
            copy.merchant = normalizeMerchant(item.merchant) ?? item.merchant
            return copy
        }
    }

    /// Apply saved category rule for this merchant (from "Remember rule" in Review); otherwise use item's category.
    private static func effectiveCategory(for item: ParsedTransactionItem) -> (category: String, subcategory: String?) {
        let rawCat = MerchantCategoryRuleStore.shared.categoryId(for: item.merchant) ?? item.categoryId ?? "other"
        let rawSub = MerchantCategoryRuleStore.shared.subcategoryId(for: item.merchant) ?? item.subcategoryId
        // GPT may return category/subcategory names instead of UUIDs — resolve by name lookup.
        let cat = resolveCategoryId(rawCat)
        let sub = resolveSubcategoryId(rawSub, parentCategoryId: cat)
        return (cat, sub)
    }

    /// If the value is already a known category UUID, return it. Otherwise try to match by name.
    private static func resolveCategoryId(_ value: String) -> String {
        let categories = CategoryStore.load()
        if categories.contains(where: { $0.id == value }) { return value }
        let lower = value.lowercased()
        if let match = categories.first(where: { $0.name.lowercased() == lower }) { return match.id }
        return value
    }

    /// If the value is already a known subcategory UUID, return it. Otherwise try to match by name (preferring parent match).
    private static func resolveSubcategoryId(_ value: String?, parentCategoryId: String) -> String? {
        guard let value = value, !value.isEmpty else { return nil }
        let subcategories = SubcategoryStore.load()
        if subcategories.contains(where: { $0.id == value }) { return value }
        let lower = value.lowercased()
        // Prefer subcategory under the same parent
        if let match = subcategories.first(where: { $0.name.lowercased() == lower && $0.parentCategoryId == parentCategoryId }) { return match.id }
        if let match = subcategories.first(where: { $0.name.lowercased() == lower }) { return match.id }
        return value
    }

    /// Store expense as positive magnitude; income as-is. Dashboard expects positive amounts for spending.
    private static func storedAmount(amount: Double, isCredit: Bool) -> Double {
        isCredit ? amount : abs(amount)
    }

    // MARK: - Single image recognition (delegates to ExtractionPipeline)

    private func recognizeAndParseOneImage(_ image: UIImage) async throws -> (items: [ParsedTransactionItem], ocrText: String, hash: String) {
        let pipeline = ExtractionPipeline()
        let result = try await pipeline.run(image: image, baseCurrency: BaseCurrencyStore.baseCurrency)
        return (result.items, result.ocrTextRaw, result.imageHash)
    }

    // MARK: - Process single image (PhotosPickerItem)

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
                let (parsed, ocrText, hash) = try await recognizeAndParseOneImage(image)
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
                    await MainActor.run {
                        LocalDataStore.shared.addPendingTransaction(
                            payload: payload,
                            ocrText: String(ocrText.prefix(2000)),
                            sourceImageHash: hash
                        )
                    }
                    addedThisImage += 1
                    totalAdded += 1
                }
                let removedByDuplicate = parsed.count - addedThisImage
                if addedThisImage == 0 && removedByDuplicate > 0 {
                    print("[Import] ⚠️ All \(removedByDuplicate) extracted transaction(s) were duplicates of existing data")
                }
                let report = ExtractionDebugReport(
                    imageIndex: index,
                    source: .gptVision,
                    imageSentToGPT: true,
                    extractedTransactions: parsed.count,
                    removedByDuplicate: removedByDuplicate,
                    finallyShown: addedThisImage,
                    imageHashPrefix: String(hash.prefix(8))
                )
                await MainActor.run { lastExtractionReports.append(report) }
            } catch {
                let hashPrefix = String(ocrService.imageHash(for: image).prefix(8))
                let report = ExtractionDebugReport(
                    imageIndex: index,
                    source: .none,
                    imageSentToGPT: false,
                    extractedTransactions: 0,
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
            let (parsed, ocrText, hash) = try await recognizeAndParseOneImage(image)

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
                await MainActor.run {
                    LocalDataStore.shared.addPendingTransaction(
                        payload: payload,
                        ocrText: String(ocrText.prefix(2000)),
                        sourceImageHash: hash
                    )
                }
                addedCount += 1
            }

            let removedByDuplicate = parsed.count - addedCount
            if addedCount == 0 && removedByDuplicate > 0 {
                print("[Import] ⚠️ All \(removedByDuplicate) extracted transaction(s) were duplicates of existing data")
            }
            let report = ExtractionDebugReport(
                imageIndex: 0,
                source: .gptVision,
                imageSentToGPT: true,
                extractedTransactions: parsed.count,
                removedByDuplicate: removedByDuplicate,
                finallyShown: addedCount,
                imageHashPrefix: String(hash.prefix(8))
            )
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
                extractedTransactions: 0,
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
    private(set) var pendingToAdd: (items: [ParsedTransactionItem], hash: String, ocrText: String)?
    /// Batches for multi-image; set by processImagesReturningItems.
    private(set) var pendingToAddBatches: [(items: [ParsedTransactionItem], hash: String, ocrText: String)]?


    /// Processes image, returns parsed items for display. Does NOT add to pending until addProcessedToPending.
    func processImageReturningItems(_ image: UIImage) async -> [ParsedTransactionItem] {
        isProcessing = true
        defer { Task { @MainActor in isProcessing = false } }
        return await processImageReturningItemsInternal(image)
    }

    /// Processes multiple images one by one via ExtractionPipeline. No batch GPT.
    func processImagesReturningItems(_ images: [UIImage]) async -> [ParsedTransactionItem] {
        await MainActor.run { errorMessage = nil; resultMessage = nil }
        isProcessing = true
        defer { Task { @MainActor in isProcessing = false } }
        await MainActor.run { lastExtractionReports = [] }
        var allItems: [ParsedTransactionItem] = []
        var batches: [(items: [ParsedTransactionItem], hash: String, ocrText: String)] = []

        for (index, image) in images.enumerated() {
            do {
                let (items, ocrText, hash) = try await recognizeAndParseOneImage(image)
                let itemsToAdd = await filterItemsForPending(items: items, hash: hash, ocrText: ocrText)
                let removedByDuplicate = items.count - itemsToAdd.count
                let report = ExtractionDebugReport(
                    imageIndex: index,
                    source: .gptVision,
                    imageSentToGPT: true,
                    extractedTransactions: items.count,
                    removedByDuplicate: removedByDuplicate,
                    finallyShown: itemsToAdd.count,
                    imageHashPrefix: String(hash.prefix(8))
                )
                await MainActor.run { lastExtractionReports.append(report) }
                allItems.append(contentsOf: itemsToAdd)
                batches.append((itemsToAdd, hash, ocrText))
            } catch OCRServiceError.noNumbersInImage {
                let hashPrefix = String(ocrService.imageHash(for: image).prefix(8))
                let report = ExtractionDebugReport(
                    imageIndex: index,
                    source: .none,
                    imageSentToGPT: false,
                    extractedTransactions: 0,
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
        await MainActor.run {
            pendingToAdd = nil
            pendingToAddBatches = batchesCopy.isEmpty ? nil : batchesCopy
            pendingCount = allItemsCount
            resultMessage = "Found \(allItemsCount) transaction(s). Review in Pending."
        }
        return allItems
    }

    /// Exclude already-saved duplicates and apply saved merchant category rules. Returns items to show in pending.
    private func filterItemsForPending(items: [ParsedTransactionItem], hash: String, ocrText: String) async -> [ParsedTransactionItem] {
        let correctedItems = items
        return await MainActor.run {
            correctedItems
                .filter { item in
                    let amt = Self.storedAmount(amount: item.amount, isCredit: item.isCredit)
                    return !LocalDataStore.shared.isExactDuplicateTransaction(
                        merchant: item.merchant,
                        date: item.date,
                        amount: amt,
                        includePending: false
                    )
                }
                .map { item in
                    let (cat, sub) = Self.effectiveCategory(for: item)
                    var corrected = item
                    corrected.categoryId = cat
                    corrected.subcategoryId = sub
                    return corrected
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
        duplicatesSkippedCount = 0
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
                             batch: (items: [ParsedTransactionItem], hash: String, ocrText: String))
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
                    SubscriptionAnalysisService.shared.checkAndAnalyzeIfNeeded()
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
                            let (items, ocrText, hash) = try await recognizeAndParseOneImage(next.image)
                            let filteredItems = await filterItemsForPending(items: items, hash: hash, ocrText: ocrText)
                            let removedByDuplicate = items.count - filteredItems.count
                            let report = ExtractionDebugReport(
                                imageIndex: imgIndex,
                                source: .gptVision,
                                imageSentToGPT: true,
                                extractedTransactions: items.count,
                                removedByDuplicate: removedByDuplicate,
                                finallyShown: filteredItems.count,
                                imageHashPrefix: String(hash.prefix(8))
                            )
                            let batchTuple = (items: filteredItems, hash: hash, ocrText: ocrText)
                            return ProcessOneResult(itemId: next.id, imageIndex: imgIndex,
                                                   outcome: .success(items: filteredItems, allItems: items,
                                                                     report: report, batch: batchTuple),
                                                   image: next.image, attemptCount: next.attemptCount)
                        } catch OCRServiceError.noNumbersInImage {
                            let hashPrefix = String(ocrService.imageHash(for: next.image).prefix(8))
                            let report = ExtractionDebugReport(
                                imageIndex: imgIndex,
                                source: .none,
                                imageSentToGPT: false,
                                extractedTransactions: 0,
                                removedByDuplicate: 0,
                                finallyShown: 0,
                                imageHashPrefix: hashPrefix
                            )
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
                                    imageIndex: imgIndex,
                                    source: .none,
                                    imageSentToGPT: false,
                                    extractedTransactions: 0,
                                    removedByDuplicate: 0,
                                    finallyShown: 0,
                                    imageHashPrefix: hashPrefix
                                )
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
                        duplicatesSkippedCount += report.removedByDuplicate
                        lastExtractionReports.append(report)
                        lastExtractionReportItems.append(all)
                        if pendingToAddBatches == nil { pendingToAddBatches = [batchTuple] }
                        else { pendingToAddBatches!.append(batchTuple) }
                        pendingCount = liveExtractedItems.count
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
            let (parsed, ocrText, hash) = try await recognizeAndParseOneImage(image)
            let itemsToAdd = await MainActor.run {
                parsed.filter { item in
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
            let report = ExtractionDebugReport(
                imageIndex: 0,
                source: .gptVision,
                imageSentToGPT: true,
                extractedTransactions: parsed.count,
                removedByDuplicate: removedByDuplicate,
                finallyShown: itemsToAdd.count,
                imageHashPrefix: String(hash.prefix(8))
            )
            await MainActor.run {
                lastExtractionReports = [report]
                resultMessage = "Found \(itemsToAdd.count) transaction(s). Review in Pending."
                pendingCount = itemsToAdd.count
                pendingToAdd = (itemsToAdd, hash, ocrText)
            }
            return itemsToAdd
        } catch {
            let hashPrefix = String(ocrService.imageHash(for: image).prefix(8))
            let report = ExtractionDebugReport(
                imageIndex: 0,
                source: .none,
                imageSentToGPT: false,
                extractedTransactions: 0,
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

    // MARK: - Add processed items to pending

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
                        probableDuplicateOfId: probableId
                    )
                    LocalDataStore.shared.addPendingTransaction(
                        payload: payload,
                        ocrText: String(p.ocrText.prefix(2000)),
                        sourceImageHash: p.hash
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
                probableDuplicateOfId: probableId
            )
            LocalDataStore.shared.addPendingTransaction(
                payload: payload,
                ocrText: String(p.ocrText.prefix(2000)),
                sourceImageHash: p.hash
            )
        }
        pendingToAdd = nil
        hasUnreviewedResults = false
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
        let imgHeader = "type,imageIndex,source,imageSentToGPT,extractedTransactions,removedByDuplicate,finallyShown,imageHashPrefix"
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
                "\(report.removedByDuplicate)",
                "\(report.finallyShown)",
                esc(report.imageHashPrefix)
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
}
