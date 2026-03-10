# Airy Backend — Architecture

## Overview

Production-ready TypeScript backend for the Airy iOS expense tracker. Hybrid pipeline: **deterministic extraction first**, **AI classification second**, **storage as source of truth**.

## Principles

- **Deterministic first**: Amounts, dates, currencies, merchants parsed with rules and regex.
- **AI only for**: Category classification, ambiguous merchant/title, subscription likelihood, confidence, multi-transaction resolution.
- **Structured outputs only**: All AI responses are strict JSON with schema + confidence.
- **Privacy-aware**: Prefer OCR text from device; optional image upload only when needed.
- **Local-first compatible**: Sync-friendly IDs and timestamps; backend can run as optional enhancement.

---

## Folder Structure

```
backend/
├── prisma/
│   ├── schema.prisma
│   └── seed.ts
├── src/
│   ├── index.ts              # App entry, Fastify, routes
│   ├── config.ts
│   ├── lib/
│   │   ├── redis.ts
│   │   ├── prisma.ts
│   │   └── logger.ts
│   ├── queues/
│   │   ├── index.ts          # BullMQ setup
│   │   ├── screenshot.job.ts # Process OCR payload
│   │   └── aggregates.job.ts # Refresh monthly/yearly caches
│   ├── services/
│   │   ├── auth.service.ts
│   │   ├── transaction-ingestion.service.ts
│   │   ├── ocr-normalize.service.ts
│   │   ├── transaction-parser.service.ts
│   │   ├── duplicate-detection.service.ts
│   │   ├── merchant-memory.service.ts
│   │   ├── category-classification.service.ts
│   │   ├── subscription-detector.service.ts
│   │   ├── analytics.service.ts
│   │   ├── ai-insight.service.ts
│   │   ├── currency.service.ts
│   │   ├── export.service.ts
│   │   └── billing.service.ts
│   ├── routes/
│   │   ├── index.ts
│   │   ├── auth.routes.ts
│   │   ├── transactions.routes.ts
│   │   ├── subscriptions.routes.ts
│   │   ├── analytics.routes.ts
│   │   ├── insights.routes.ts
│   │   ├── export.routes.ts
│   │   └── entitlements.routes.ts
│   ├── middleware/
│   │   ├── auth.middleware.ts
│   │   └── entitlements.middleware.ts
│   ├── schemas/
│   │   ├── transaction.schema.ts
│   │   ├── ocr-payload.schema.ts
│   │   └── ai-extraction.schema.ts
│   └── observability/
│       ├── metrics.ts
│       └── request-logger.ts
└── tests/
    └── mocks/
```

---

## Service Boundaries

| Service | Responsibility | Deterministic / AI |
|--------|----------------|--------------------|
| **Auth** | JWT issue/verify, user identity | Deterministic |
| **TransactionIngestion** | Orchestrate screenshot pipeline, enqueue jobs | Deterministic |
| **OcrNormalize** | Clean/normalize OCR text (whitespace, encoding) | Deterministic |
| **TransactionParser** | Extract amounts, dates, currencies, merchants from text | Deterministic |
| **DuplicateDetection** | Weighted scoring: hash, amount, date, merchant, OCR similarity | Deterministic |
| **MerchantMemory** | Store/apply user correction rules (category, subscription) | Deterministic |
| **CategoryClassification** | Map merchant/description → category (with AI fallback) | Hybrid: rules first, AI second |
| **SubscriptionDetector** | Recurring pattern detection (merchant, amount, interval) | Deterministic |
| **Analytics** | Precompute monthly/yearly/category/merchant aggregates | Deterministic |
| **AIInsight** | Money Mirror, monthly summary, anomaly; structured JSON only | AI (Anthropic) |
| **Currency** | Fetch rates, convert; cache in Redis | Deterministic |
| **Export** | CSV/JSON generation from transactions | Deterministic |
| **Billing** | Entitlement checks (free vs Pro), limits | Deterministic |

---

## Processing Pipeline (Screenshot Import)

1. **App**: On-device OCR (Apple Vision) → sends OCR text, metadata, `userId`, `localHash`, optional image fingerprint.
2. **API**: `POST /api/transactions/parse-screenshot` → validate payload → enqueue job (or process sync for small payloads).
3. **OcrNormalize**: Normalize line endings, trim, collapse spaces, fix common OCR glitches.
4. **TransactionParser**: Deterministic extraction:
   - Amounts (regex + currency symbols)
   - Currencies (ISO codes, symbols)
   - Dates (multiple formats)
   - Times
   - Merchants (lines/patterns)
5. **CategoryClassification**: Rule-based first (merchant memory, keyword list), then AI for ambiguous → category + confidence.
6. **AI (optional)**: If multiple transactions or low confidence: structured AI call for split/merge, merchant inference, subscription likelihood.
7. **Validate**: Zod schema for each extracted transaction; reject invalid.
8. **DuplicateDetection**: Score vs existing transactions; exact → skip, high score → duplicate candidate, mid → review.
9. **MerchantMemory**: Apply stored rules; override category if rule exists.
10. **Pending review**: If overall confidence < threshold → insert into `PendingTransaction` for user confirm/edit.
11. **Persist**: Accepted transactions → `Transaction`; update `MonthlyAggregate` / caches.
12. **Observability**: Log parse success rate, low-confidence rate, duplicate rate, latency per stage.

---

## Duplicate Detection Strategy

**Weighted score** (0–1) from:

- `imageHashMatch`: 1.0 if local hash matches existing `sourceImageHash`.
- `amountSimilarity`: 1.0 if exact, decay by relative difference.
- `currencyMatch`: 1.0 if same normalized currency.
- `merchantSimilarity`: Normalized Levenshtein or token overlap.
- `dateProximity`: 1.0 if same day, decay by days difference.
- `ocrSimilarity`: Text similarity (e.g. Jaccard or Levenshtein on normalized OCR).

**Thresholds:**

- Score ≥ 0.95 → auto-skip (duplicate).
- Score 0.7–0.95 → duplicate candidate (mark for review or skip with flag).
- Score < 0.7 → not duplicate.

---

## Merchant Memory Strategy

- **Store**: On user correction (category, subcategory, or “is subscription”) → upsert `MerchantRule`: normalized merchant name, category, subcategory, `isSubscription`, `lastConfirmedAt`, optional aliases.
- **Match**: Normalize incoming merchant (lowercase, trim, alias lookup); if rule exists and not stale, apply category and subscription hint.
- **Conflict**: If AI or parser suggests different category with high confidence, can still apply rule (user wins) or flag for re-confirmation.

---

## Subscription Detection Strategy

- **Input**: All transactions for user.
- **Logic**: Group by normalized merchant; for each merchant, check:
  - Similar amount (e.g. ±5% or fixed tolerance).
  - Regular interval (e.g. ~30 days, ~7 days, ~1 year).
- **Output**: Mark transactions `isRecurringCandidate`; create/update `Subscription` records (merchant, amount, interval, nextBillingDate).
- **States**: `confirmed_subscription` (user confirmed), `subscription_candidate` (auto-detected), `non_subscription`.

---

## Free vs Pro Entitlements

| Entitlement | Free | Pro |
|-------------|------|-----|
| `monthly_ai_limit` | e.g. 10/month | N/A (unlimited) |
| `unlimited_ai_analysis` | false | true |
| `advanced_insights` | false | true (Money Mirror, anomaly) |
| `subscriptions_dashboard` | false | true |
| `yearly_review` | false | true |
| `export_extended` | CSV only | CSV + JSON, date range |
| `cloud_sync` | false | true |

Endpoints check entitlements via `billing.service.ts`; return 402 or 403 with message when feature is Pro-only.

---

## Analytics Aggregation Strategy

- **Precompute**: Background job (e.g. nightly or on transaction write) updates:
  - `MonthlyAggregate`: userId, yearMonth, totalSpent, totalIncome, byCategory, transactionCount.
  - `YearlyAggregate`: userId, year, totals, topCategories, subscriptionTotal.
  - Redis cache: dashboard stats, trend deltas, weekday/weekend, time-of-day (for insights).
- **On read**: Prefer cached aggregates; fallback to live query if cache miss.
- **Anomaly candidates**: Compare current month category spend to rolling average; flag if > 2x or configurable threshold.

---

## Insight Generation Strategy

- **Input**: Precomputed analytics (category breakdown, trends, subscription list, time patterns).
- **Process**: Deterministic metrics → pass to AI with strict JSON schema (e.g. “list of insight objects with type, title, body, metricRef”).
- **Output**: Short, grounded insights; no freeform hallucination. Cache per user/month; refresh on new data or TTL.
- **Monthly summary**: “You spent X% more/less than last month”; bullet list of category deltas (computed), then AI compresses to 1–2 sentences if needed.

---

## Error Handling Strategy

- **Validation**: Zod on all inputs; 400 with field errors.
- **Auth**: 401 Unauthorized, 403 Forbidden.
- **Entitlements**: 402 Payment Required or 403 with code `ENTITLEMENT_REQUIRED`.
- **Rate limits**: 429; use Redis for counters.
- **Server**: 500 with request id; log stack; no sensitive data in response.
- **Queue**: Retry with backoff (e.g. 3 retries); dead-letter for manual inspection.

---

## Cost Optimization

- Cache AI results (e.g. category for merchant) in Redis or DB to avoid repeated calls.
- Batch AI requests where possible (e.g. multiple transactions in one structured call).
- Use small context windows and strict schemas to reduce tokens.
- Enforce `monthly_ai_limit` for free users; use deterministic path when confidence is high.
- Cache exchange rates; use single provider with fallback.

---

## Testing Strategy

- **Unit**: Services in isolation with mocked Prisma/Redis/Anthropic.
- **Integration**: API tests with test DB and Redis; seed data.
- **Mock mode**: `MOCK_AI=true` and optional `MOCK_EXCHANGE_RATES=true` for local dev without API keys; deterministic fixtures for AI responses.

---

## Privacy

- **Default**: App sends OCR text only; no screenshot upload required.
- **Optional**: Endpoint for temporary image upload if extraction quality is low; store only in object storage with TTL and delete after processing.
- **Retention**: Transaction data per user; support export and delete (GDPR). Minimize retention of raw OCR text in logs (e.g. hash only in production logs).
