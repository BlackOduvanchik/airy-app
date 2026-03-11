# Airy Screenshot Import System — Design Document

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         SCREENSHOT IMPORT PIPELINE                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  [User] → Select 1..N screenshots                                            │
│       → Analyzing Screen (lightweight progress)                               │
│       → Extraction Pipeline (local-first)                                    │
│       → Review Screen (confirm/edit/skip/save all)                            │
│       → Local Storage (transactions + merchant memory + fingerprints)        │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘

Pipeline layers (all local by default):
  A. Screen Type Classifier     → B. Document Structure Extraction
  B. Document Structure         → C. Parser Registry (type-specific parsers)
  C. Parser Registry           → D. Normalization Engine
  D. Normalization              → E. Transaction Status Classifier
  E. Status Classifier          → F. Income/Expense Classifier
  F. Income/Expense            → G. Merchant Memory (lookup)
  G. Merchant Memory           → H. Duplicate Detection
  H. Duplicate Detection       → I. Confidence Engine
  I. Confidence Engine         → J. Review Model (UI)
  J. Review Model              → K. Local Storage
  [Optional] I. Low confidence  → L. External AI Fallback (one-shot, OCR text only)
```

---

## 2. Layered Pipeline

### A. Screen Type Classifier
- **Input**: OCR text + optional Vision block structure
- **Output**: `ScreenType` enum
- **Logic**: Keyword/pattern heuristics per type. No ML. Fast.
- **Types**: `single_payment_confirmation`, `transaction_list`, `bank_statement_like`, `receipt`, `subscription_receipt`, `money_transfer`, `failed_transaction_notice`, `unknown`

### B. Document Structure Extraction
- **Input**: UIImage
- **Output**: `DocumentStructure` (blocks, lines, regions)
- **Logic**: Apple Vision `VNRecognizeTextRequest` with `recognitionLevel = .accurate`. Use `boundingBox` to group lines into rows/blocks. Do not flatten to one blob when row-like structure exists.

### C. Parser Registry
- **Input**: `ScreenType` + `DocumentStructure` (or fallback flat OCR)
- **Output**: `[RawCandidate]` (un-normalized)
- **Parsers**: One per screen type. Default: `TransactionListParser` (current LocalOCRParser logic) for `unknown` and `transaction_list`.

### D. Normalization Engine
- **Input**: `RawCandidate`
- **Output**: `CandidateTransaction` (normalized)
- **Rules**: Dates → ISO 8601, currencies → ISO 4217, decimals (`,` vs `.`), merchant trim, ± signs, localized wording ("від"/"from"/"received from" → income).

### E. Transaction Status Classifier
- **Input**: `CandidateTransaction` + raw OCR context
- **Output**: `TransactionStatus`
- **Logic**: Keywords for failed/declined ("insufficient funds", "declined", "failed", "отклонено", etc.). Default: `success`.

### F. Income/Expense Classifier
- **Input**: `CandidateTransaction` + OCR context
- **Output**: `TransactionType` (expense, income, transfer, unknown)
- **Logic**: Amount sign, keywords ("received", "from", "to", "payment to").

### G. Merchant Memory
- **Input**: amount, date, original merchant
- **Output**: corrected merchant (from `MerchantCorrectionStore`)
- **Extended**: Store category hints (Apple → subscriptions), failed patterns ("insufficient funds" → junk).

### H. Duplicate Detection
- **Input**: image hash, amount, date, merchant, OCR snippet
- **Logic**: Image hash (existing), plus fuzzy match on (amount, date, merchant) against saved transactions.

### I. Confidence Engine
- **Input**: `CandidateTransaction` + parse metadata
- **Output**: `ConfidenceScores` per candidate
- **Thresholds**: high ≥ 0.85, medium 0.5–0.85, low < 0.5

### J. Review Model
- **UI**: Card per candidate. Actions: Confirm, Edit, Skip, Mark duplicate, Remember merchant, Ignore (failed).

### K. Local Storage
- SwiftData: transactions, pending
- UserDefaults/Keychain: merchant corrections, parsing rules, duplicate fingerprints

### L. Optional External AI Fallback
- **Trigger**: OCR poor, confidence low, many ambiguous, unknown layout
- **Input**: OCR text only (no raw image when possible)
- **Output**: Parsed candidates (one-shot). No server persistence.
- **Integration**: GPTRulesService pattern; rules saved locally for future use.

---

## 3. Data Models and Enums

```swift
// MARK: - Screen Classification
enum ScreenType: String, Codable, CaseIterable {
    case singlePaymentConfirmation
    case transactionList
    case bankStatementLike
    case receipt
    case subscriptionReceipt
    case moneyTransfer
    case failedTransactionNotice
    case unknown
}

// MARK: - Transaction Status
enum TransactionStatus: String, Codable {
    case success
    case failed
    case pending
    case reversed
    case informational
}

// MARK: - Transaction Type (income/expense)
enum TransactionType: String, Codable {
    case expense
    case income
    case transfer
    case unknown
}

// MARK: - Confidence
struct ConfidenceScores: Codable {
    var amountConfidence: Double
    var dateConfidence: Double
    var merchantConfidence: Double
    var statusConfidence: Double
    var typeConfidence: Double
    var overallConfidence: Double
}

enum ConfidenceLevel {
    case high   // ≥ 0.85, pre-approved
    case medium // 0.5–0.85, review recommended
    case low    // < 0.5, review required
}

// MARK: - Document Structure (Vision blocks)
struct DocumentStructure {
    var blocks: [TextBlock]
}
struct TextBlock {
    var lines: [String]
    var boundingBox: CGRect?
}

// MARK: - Raw candidate (before normalization)
struct RawCandidate {
    var amount: Double
    var amountRaw: String
    var isCredit: Bool
    var currencyRaw: String?
    var dateRaw: String?
    var timeRaw: String?
    var merchantRaw: String?
    var lineIndex: Int
    var sourceLine: String
}

// MARK: - Candidate transaction (normalized, for review)
struct CandidateTransaction: Identifiable {
    let id: UUID
    var amount: Double
    var currency: String
    var date: String       // ISO 8601
    var time: String?
    var merchant: String?
    var status: TransactionStatus
    var type: TransactionType
    var confidence: ConfidenceScores
    var sourceImageIndex: Int
    var sourceOcrSnippet: String?
    var isDuplicate: Bool
}

// MARK: - Review card (UI model)
struct ReviewTransactionCard: Identifiable {
    let id: UUID
    var candidate: CandidateTransaction
    var reviewAction: ReviewAction?
}
enum ReviewAction {
    case confirm
    case edit(ConfirmPendingOverrides)
    case skip
    case markDuplicate
    case rememberMerchant(category: String?)
    case ignoreFailed
}

// MARK: - Merchant rule (extended)
struct MerchantRule: Codable {
    var key: String           // e.g. (amount, date, originalMerchant) hash
    var correctedMerchant: String
    var categoryHint: String?
    var isFailedPattern: Bool?
}

// MARK: - Duplicate candidate
struct DuplicateCandidate {
    var imageHash: String
    var amount: Double
    var date: String
    var merchant: String?
    var ocrFingerprint: String?
}

// MARK: - Extraction result (pipeline output)
struct ExtractionResult {
    var screenType: ScreenType
    var candidates: [CandidateTransaction]
    var duplicatesSkipped: Int
    var failedSkipped: Int
    var lowConfidenceCount: Int
    var ocrText: String
    var documentStructure: DocumentStructure?
}
```

---

## 4. UX Flow

### 4.1 Choose Screenshots
- **Entry**: Add → Add Screenshot → Paste from Clipboard **or** Open Gallery
- **Change**: Gallery picker `selectionLimit = 0` (unlimited) to allow multiple selection
- **Flow**: User selects 1..N images → tap Done → app receives `[UIImage]`

### 4.2 Analyzing Screen
- **Display**: Full-screen, gradient background
- **Content**: Thumbnails of selected images (1..N), progress stepper (Upload → Extract → Review), status phrases, live extraction list (staggered reveal)
- **Behavior**: Process images sequentially or in small batches. Show progress per image. No blocking; use Task.

### 4.3 Review Transactions
- **Display**: List of cards, one per candidate
- **Per card**: Merchant, amount, date, status badge (if failed/pending), confidence indicator
- **Actions**: Confirm, Edit, Skip, Mark duplicate, Remember merchant
- **Footer**: "Save all confirmed" — saves only confirmed items
- **Failed/declined**: Shown with "Failed" badge, not auto-saved; user can "Ignore" to dismiss

### 4.4 Save All
- **Trigger**: User taps "Save all confirmed"
- **Behavior**: Persist confirmed candidates to SwiftData, apply merchant corrections, store duplicate fingerprints, clear pending

---

## 5. Confidence and Review Logic

### Confidence Computation
- `amountConfidence`: 1.0 if parsed from line with currency symbol; 0.7 if amount only; 0.4 if ambiguous
- `dateConfidence`: 1.0 if explicit date; 0.5 if inferred from context; 0.2 if today default
- `merchantConfidence`: 1.0 if from merchant memory; 0.8 if extracted; 0.4 if "Transaction"
- `statusConfidence`: 1.0 if explicit failed/success keywords; 0.7 default
- `typeConfidence`: 1.0 if sign + keywords; 0.6 if sign only
- `overallConfidence`: weighted average (e.g. amount 0.3, date 0.2, merchant 0.25, status 0.1, type 0.15)

### Thresholds
- **High (≥ 0.85)**: Pre-approved, user can "Save all" without reviewing each
- **Medium (0.5–0.85)**: Review recommended; card shows "Review" hint
- **Low (< 0.5)**: Review required; card highlighted

### Failed Transactions
- **Detection**: Keywords in OCR: "insufficient funds", "declined", "failed", "denied", "отклонено", "відхилено", etc.
- **Behavior**: `status = .failed`, not auto-saved. Shown in review with "Failed" badge. User can "Ignore" to skip.

---

## 6. Local Memory Strategy

### What to Save After User Correction
1. **Merchant correction**: `MerchantCorrectionStore` — (amount, date, originalMerchant) → correctedMerchant
2. **Category hint**: Extend to `MerchantRule` — merchant → category (e.g. Apple → subscriptions)
3. **Failed pattern**: Store OCR patterns that indicate failed transactions (e.g. "insufficient funds")
4. **Parsing rules**: `ParsingRulesStore` — GPT-generated rules per format fingerprint
5. **Duplicate fingerprint**: Image hash + (amount, date, merchant) for fuzzy duplicate detection

### Storage
- `MerchantCorrectionStore`: UserDefaults, key `merchantCorrections`
- `ParsingRulesStore`: UserDefaults, key `parsingRules`
- `LocalDataStore`: SwiftData (transactions, pending)
- New: `DuplicateFingerprintStore` — UserDefaults, recent (amount, date, merchant) hashes

---

## 7. Optional AI Fallback Strategy

### When to Trigger
1. OCR result is poor (very short or garbled)
2. `overallConfidence` for all candidates < 0.4
3. Screen type = `unknown` and parser returns empty
4. User explicitly requests "Improve with AI" (Settings)

### How It Works
1. Send OCR text only to OpenAI (no image)
2. Prompt: "Extract transactions as JSON: amount, currency, date, merchant, status, type"
3. Parse response, convert to `[CandidateTransaction]`
4. Save rules to `ParsingRulesStore` for future local use
5. No server persistence; treat as one-shot helper

### Constraints
- Require user consent (disclosure in Settings)
- API key stored in Keychain
- Only when local path fails or user opts in

---

## 8. Implementation Plan by Phases

### Phase 1: Foundation (1–2 weeks)
- Add `ScreenType`, `TransactionStatus`, `TransactionType`, `ConfidenceScores`, `CandidateTransaction`
- Refactor `LocalOCRParser` → `TransactionListParser` (one parser in registry)
- Add `ParserRegistry` that dispatches by `ScreenType`
- Add `NormalizationEngine`
- Add `ConfidenceEngine`
- Wire `ImportViewModel` to new pipeline; keep `ParsedTransactionItem` as internal format for now

### Phase 2: Screen Classifier + Document Structure (1 week)
- Implement `ScreenTypeClassifier` (keyword-based)
- Extend `OCRService` to return `DocumentStructure` (Vision blocks) when useful
- Add `TransactionListParser` to use blocks when available

### Phase 3: Status + Type Classifiers (1 week)
- Implement `TransactionStatusClassifier` (failed/declined keywords)
- Implement `IncomeExpenseClassifier`
- Filter failed transactions from auto-save; show in review with badge

### Phase 4: Multi-Image + Review UX (1–2 weeks)
- Update `GalleryPickerView` to allow multiple selection
- Update `MainTabView` to pass `[UIImage]` to analyzing flow
- Process multiple images; aggregate candidates
- Redesign `PendingReviewView` → `TransactionReviewView` with card model, confidence badges, failed handling

### Phase 5: Duplicate + Merchant Memory (1 week)
- Add `DuplicateFingerprintStore` for fuzzy duplicate detection
- Extend `MerchantCorrectionStore` with category hints
- Add "Remember merchant" flow in review

### Phase 6: AI Fallback Integration (1 week)
- Add trigger logic in pipeline when confidence low / empty
- Optional sheet: "Local extraction had low confidence. Use AI to improve?" (with consent)
- Wire `GPTRulesService` to return `[CandidateTransaction]` for fallback path

---

## 9. File-by-File Action Plan

### Create
| File | Purpose |
|------|---------|
| `Airy/Import/Models/ScreenType.swift` | ScreenType enum |
| `Airy/Import/Models/TransactionStatus.swift` | TransactionStatus, TransactionType |
| `Airy/Import/Models/CandidateTransaction.swift` | CandidateTransaction, ConfidenceScores |
| `Airy/Import/Models/ExtractionResult.swift` | ExtractionResult, DocumentStructure |
| `Airy/Import/Models/ReviewModels.swift` | ReviewTransactionCard, ReviewAction |
| `Airy/Services/Import/ScreenTypeClassifier.swift` | Screen type classification |
| `Airy/Services/Import/ParserRegistry.swift` | Parser dispatch by type |
| `Airy/Services/Import/NormalizationEngine.swift` | Date, currency, decimal normalization |
| `Airy/Services/Import/TransactionStatusClassifier.swift` | Failed/success detection |
| `Airy/Services/Import/IncomeExpenseClassifier.swift` | Expense/income/transfer |
| `Airy/Services/Import/ConfidenceEngine.swift` | Confidence scoring |
| `Airy/Services/Import/DuplicateFingerprintStore.swift` | Fuzzy duplicate detection |
| `Airy/Services/Import/ExtractionPipeline.swift` | Orchestrates full pipeline |
| `Airy/Features/Import/TransactionReviewView.swift` | New review UI |
| `Airy/Features/Import/TransactionReviewCard.swift` | Single candidate card |
| `Airy/Features/Import/MultiImagePickerView.swift` | Multi-select gallery |

### Modify
| File | Changes |
|------|---------|
| `LocalOCRParser.swift` | Rename/refactor to `TransactionListParser`, implement `ScreenParser` protocol |
| `OCRService.swift` | Add optional `recognizeTextWithStructure` returning blocks |
| `ImportViewModel.swift` | Use `ExtractionPipeline`, support `[UIImage]`, return `[CandidateTransaction]` |
| `MerchantCorrectionStore.swift` | Add category hints, optional failed patterns |
| `LocalDataStore.swift` | Add `DuplicateFingerprintStore` integration, confirm with `CandidateTransaction` |
| `GalleryPickerView.swift` | Add `selectionLimit` param, support multiple images |
| `MainTabView.swift` | Pass `[UIImage]` to analyzing flow |
| `AnalyzingTransactionsView.swift` | Accept `[UIImage]`, show multi-thumbnail, use `CandidateTransaction` |
| `PendingReviewView.swift` | Replace with `TransactionReviewView` or merge |

### Remove / Deprecate
| File | Action |
|------|--------|
| `ParsedTransactionItem` | Replace with `CandidateTransaction` in pipeline; keep as internal bridge if needed |
| `processImage` (single) | Keep for paste; add `processImages(_ images: [UIImage])` |

### Keep As-Is (for now)
| File | Reason |
|------|--------|
| `ParsingRulesStore.swift` | Used by parser; extend for AI fallback |
| `GPTRulesService.swift` | AI fallback; extend to return candidates |
| `KeychainHelper.swift` | API key storage |
| `LocalModels.swift` | SwiftData models |
| `AddActionSheetView.swift` | Entry point |

---

## 10. Multilingual Parsing

- **Currency symbols**: Extend `currencySymbols` map (₴→UAH, ฿→THB, ₪→ILS, etc.)
- **Date formats**: Add patterns for DD.MM.YYYY, DD/MM/YY, YYYY-MM-DD, "11 Mar 2025", localized month names
- **Keywords**: Failed: "declined", "failed", "insufficient", "отклонено", "відхилено", "refusé", etc.
- **Income**: "received", "from", "від", "от", "de", etc.
- **Storage**: Localized keyword lists per language code (optional; start with EN + common)

---

## 11. Summary

- **Local-first**: All extraction, classification, storage on device.
- **Layered pipeline**: Classifier → Parser → Normalize → Status/Type → Confidence → Review.
- **Failed transactions**: Detected, not auto-saved, shown with badge.
- **Multi-image**: Gallery supports multiple selection; pipeline processes all.
- **Confidence**: Drives review UX; low confidence requires review.
- **AI fallback**: Optional, OCR-only, when local fails or user opts in.
- **Merchant memory**: Corrections + category hints improve future imports.
