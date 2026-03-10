# Airy Project — Full Completeness Audit

**Assumption:** This must become a real production iOS app.  
**Scope:** iOS application + backend. Verification that every part of the system exists and is fully defined.

---

## 1. iOS application architecture

**Fully defined:** No  
**Implementing files/modules:** None. No Swift files, no Xcode project (`.xcodeproj`), no iOS target in the workspace.

**Missing pieces:**
- No iOS app codebase. The workspace contains only the backend (`backend/`). There is no `Airy/` or `ios/` app directory with Swift sources.
- Architecture is only described in conversation/plan: SwiftUI, SwiftData or local SQLite, Apple Vision for OCR, cloud mascot UI. None of this is implemented.

**Unclear logic:** N/A — no implementation to audit.

**Implementation gaps:**
- Entire iOS application is missing: no app target, no Info.plist, no asset catalog, no SwiftUI views, no data layer, no networking client.

---

## 2. Screen structure

**Fully defined:** No  
**Implementing files/modules:** None. No iOS screens exist.

**Missing pieces:**
- No view files for: onboarding, dashboard, transaction list, screenshot import, pending review, subscriptions, insights/Money Mirror, settings, paywall.
- No storyboards or SwiftUI view hierarchy.

**Unclear logic:** N/A.

**Implementation gaps:**
- All screens are unimplemented. Backend API supports the flows (transactions, pending, subscriptions, insights, export, entitlements) but no client UI.

---

## 3. Navigation system

**Fully defined:** No  
**Implementing files/modules:** None.

**Missing pieces:**
- No `NavigationStack` / `NavigationView`, no tab bar, no coordinator or router pattern.
- No deep linking or universal links configuration.

**Unclear logic:** N/A.

**Implementation gaps:**
- Full navigation layer is missing on iOS.

---

## 4. View models

**Fully defined:** No  
**Implementing files/modules:** None.

**Missing pieces:**
- No ObservableObject or @Observable view models for: dashboard, transaction list, screenshot flow, pending review, subscriptions, insights, settings.
- No clear separation between UI and business logic on the client.

**Unclear logic:** N/A.

**Implementation gaps:**
- No view model layer; backend services cannot be consumed by any client logic in-repo.

---

## 5. Services layer (backend)

**Fully defined:** Yes  
**Implementing files/modules:**
- `src/services/auth.service.ts` — findOrCreateUserByExternalId, findUserById, getJwtSecret
- `src/services/transaction-ingestion.service.ts` — ingestScreenshot (orchestration)
- `src/services/ocr-normalize.service.ts` — normalizeOcrText, linesFromNormalized
- `src/services/transaction-parser.service.ts` — parseTransactionsFromOcr, ParsedItem with amount/isCredit
- `src/services/duplicate-detection.service.ts` — findDuplicateByHash, getRecentTransactions, checkDuplicateBatch, checkDuplicate
- `src/services/merchant-memory.service.ts` — upsertMerchantRule, getMerchantRule, getMerchantRulesBatch, listMerchantRules, deleteMerchantRule
- `src/services/category-classification.service.ts` — classifyCategory (rules + optional preResolvedRule)
- `src/services/subscription-detector.service.ts` — detectSubscriptions
- `src/services/analytics.service.ts` — getMonthlyAggregate, getYearlyAggregate, getDashboardData, refreshMonthlyAggregate, invalidateDashboardCache
- `src/services/ai-insight.service.ts` — getMonthlySummary, getBehavioralInsights, invalidateInsightsCache
- `src/services/currency.service.ts` — getRates, convert
- `src/services/export.service.ts` — exportCsv, exportJson (with pagination)
- `src/services/billing.service.ts` — getEntitlements, checkEntitlement, consumeAiAnalysis, getAiUsageRemaining

**Missing pieces:** None for core flows.

**Unclear logic:**
- Category classification has no AI fallback in code; ARCHITECTURE mentions "AI for ambiguous" but `classifyCategory` only uses rules + keywords, no Anthropic call.

**Implementation gaps:**
- `requireEntitlement` middleware exists but is never used; routes call `checkEntitlement` inline instead.

---

## 6. Screenshot import flow

**Fully defined:** Yes (backend only)  
**Implementing files/modules:**
- API: `POST /api/transactions/parse-screenshot` (sync), `POST /api/transactions/parse-screenshot/async` in `src/routes/transactions.routes.ts`
- `src/services/transaction-ingestion.service.ts` — full pipeline: normalize → parse → hash duplicate check → batch recent + rules → duplicate batch → classify → convert → toInsert/toPending → single Prisma transaction → enqueue aggregates + subscriptions → invalidate caches
- `src/queues/screenshot.job.ts` — processScreenshotJob calls ingestScreenshot for async path
- Idempotency via `Idempotency-Key` and Redis; rate limit per user for parse-screenshot

**Missing pieces:**
- iOS: no camera/photo picker, no on-device OCR (Vision), no UI to send OCR text + localHash + baseCurrency to the API.

**Unclear logic:** None on backend.

**Implementation gaps:**
- Client-side screenshot capture and OCR pipeline is entirely missing.

---

## 7. OCR pipeline

**Fully defined:** Partially  
**Implementing files/modules:**
- Backend: `src/services/ocr-normalize.service.ts` — normalizeOcrText (NFKC, line endings, trim, collapse spaces), linesFromNormalized. Receives OCR text from client; no server-side OCR.
- Backend: `src/services/transaction-parser.service.ts` — regex-based extraction from normalized text (amounts, dates, times, currencies, merchants); isCredit and refund keywords.

**Missing pieces:**
- iOS: no integration with VNRecognizeTextRequest or any Vision framework. No code that produces OCR text from an image to send to the backend.
- Backend assumes OCR text is provided; there is no fallback “upload image and run OCR on server” (ARCHITECTURE mentions optional image upload with TTL; not implemented).

**Unclear logic:** N/A.

**Implementation gaps:**
- On-device OCR (iOS) is missing. Backend OCR handling is “normalize + parse text” only.

---

## 8. Transaction extraction engine

**Fully defined:** Partially  
**Implementing files/modules:**
- `src/services/transaction-parser.service.ts` — deterministic extraction: parseAmountFromLine (with sign/isCredit), parseDateFromLine, parseTimeFromLine; parseTransactionsFromOcr builds ParsedItem[] (amount, isCredit, currency, date, time, merchant, rawLine).
- `src/schemas/ai-extraction.schema.ts` — Zod schemas for AI-extracted transactions (aiExtractedTransactionSchema, aiExtractionResponseSchema).

**Missing pieces:**
- No code path that uses `ai-extraction.schema.ts`. Pipeline uses only deterministic parser + category classification (rules/keywords). No structured AI call for “multiple transactions or low confidence” as in ARCHITECTURE.
- No AI extraction service that calls Anthropic with OCR text and returns aiExtractionResponseSchema-validated data.

**Unclear logic:**
- Documented “AI (optional): If multiple transactions or low confidence: structured AI call” is not implemented; schema exists but is dead code.

**Implementation gaps:**
- Optional AI extraction step (using aiExtractionResponseSchema) is missing from the ingestion pipeline.

---

## 9. Duplicate detection system

**Fully defined:** Yes  
**Implementing files/modules:**
- `src/services/duplicate-detection.service.ts` — findDuplicateByHash(userId, sourceImageHash); getRecentTransactions(userId, limit); checkDuplicateBatch(inputs, recent); checkDuplicate(input) uses hash-first then batch. Weights: imageHash, amount, currency, merchant, date, ocrSimilarity. Thresholds: AUTO_SKIP 0.95, DUPLICATE_CANDIDATE 0.7. Levenshtein for merchant and text similarity.

**Missing pieces:** None.

**Unclear logic:** None.

**Implementation gaps:** None.

---

## 10. Merchant memory system

**Fully defined:** Yes  
**Implementing files/modules:**
- `src/services/merchant-memory.service.ts` — normalizeMerchant (exported), upsertMerchantRule, getMerchantRule, getMerchantRulesBatch, listMerchantRules, deleteMerchantRule. Unique on (userId, merchantNormalized).
- Ingestion uses getMerchantRulesBatch and preResolvedRule in classifyCategory.
- PATCH /transactions/:id calls upsertMerchantRule when category or isSubscription is updated and merchant is present.
- `src/routes/merchant-memory.routes.ts` — GET/POST/DELETE merchant-rules.

**Missing pieces:** None.

**Unclear logic:** None.

**Implementation gaps:** None.

---

## 11. Subscription detection engine

**Fully defined:** Yes  
**Implementing files/modules:**
- `src/services/subscription-detector.service.ts` — detectSubscriptions(userId): load all expense transactions, group by normalized merchant; for each group with ≥2 similar amounts and regular interval (monthly/yearly/weekly), create/update Subscription. Does not overwrite status when existing is confirmed_subscription or non_subscription (only when subscription_candidate).
- `src/queues/aggregates.job.ts` — job type `subscriptions` calls detectSubscriptions(userId).
- Enqueued after ingestion; no sync call in API.

**Missing pieces:** None.

**Unclear logic:** None.

**Implementation gaps:** None.

---

## 12. Manual transaction entry

**Fully defined:** Yes (backend)  
**Implementing files/modules:**
- `POST /api/transactions` in `src/routes/transactions.routes.ts` — body validated with createTransactionSchema (Zod); category from ALLOWED_CATEGORIES; idempotency key supported; creates Transaction; invalidates dashboard and insights cache.
- `src/schemas/transaction.schema.ts` — createTransactionSchema with categorySchema (whitelist).

**Missing pieces:**
- iOS: no “add transaction” screen or form that calls POST /api/transactions.

**Unclear logic:** None on backend.

**Implementation gaps:** Client UI for manual entry is missing.

---

## 13. Currency conversion

**Fully defined:** Yes  
**Implementing files/modules:**
- `src/services/currency.service.ts` — getRates(baseCurrency) with Redis cache key `airy:rates:{base}:{date}`; Frankfurter API; MOCK_EXCHANGE_RATES; convert(amount, fromCurrency, toCurrency) uses getRates(fromCurrency). Rates cached per EXCHANGE_RATE_CACHE_TTL_SECONDS.

**Missing pieces:** None.

**Unclear logic:** None.

**Implementation gaps:** None.

---

## 14. Analytics engine

**Fully defined:** Yes  
**Implementing files/modules:**
- `src/services/analytics.service.ts` — getMonthlyAggregate (reads MonthlyAggregate first, else computes from Transaction); getYearlyAggregate (reads from Transaction only; does not read or write YearlyAggregate table); getDashboardData (Redis cache 5 min, invalidation via invalidateDashboardCache); refreshMonthlyAggregate (writes MonthlyAggregate); computeMonthlyFromTransactions helper.

**Missing pieces:**
- YearlyAggregate table exists in Prisma schema but is never written. getYearlyAggregate always computes from Transaction; no refreshYearlyAggregate or job that populates YearlyAggregate.

**Unclear logic:** None.

**Implementation gaps:**
- YearlyAggregate table is unused; yearly read path is live query only, no precomputed yearly cache.

---

## 15. AI insights engine

**Fully defined:** Yes  
**Implementing files/modules:**
- `src/services/ai-insight.service.ts` — getMonthlySummary (month-over-month delta, category details; AI one-sentence summary when not MOCK_AI); getBehavioralInsights (deterministic trend + top category, then AI 1–3 insights, strict JSON schema); Redis cache per user/month; invalidateInsightsCache(userId). Uses getMonthlyAggregate and getDashboardData.

**Missing pieces:** None.

**Unclear logic:** None.

**Implementation gaps:** None.

---

## 16. AI Money Mirror system

**Fully defined:** Partially  
**Implementing files/modules:**
- ARCHITECTURE and docs refer to “Money Mirror” as a product concept (behavioral insights, spending reflection).
- Implemented under the same “AI insights” surface: getBehavioralInsights in `src/services/ai-insight.service.ts` — trend and category insights plus AI-generated behavioral insights. No separate “Money Mirror” API or dedicated flow.

**Missing pieces:**
- No dedicated Money Mirror endpoint or feature name in API. No explicit “Money Mirror” prompt or schema; behavioral insights are the de facto implementation.
- Docs mention “anomaly” (e.g. “Unusual: entertainment 3× your average”); no anomaly-detection logic in code (no comparison to rolling average, no 2× threshold as in ARCHITECTURE).

**Unclear logic:**
- “Money Mirror” is a naming/product concept; implementation is the same as behavioral insights. Anomaly detection is documented but not implemented.

**Implementation gaps:**
- Anomaly detection (compare to rolling average, flag outliers) is missing. No dedicated Money Mirror branding or endpoint.

---

## 17. Monthly summary generation

**Fully defined:** Yes  
**Implementing files/modules:**
- `src/services/ai-insight.service.ts` — getMonthlySummary(userId, yearMonth): current vs previous month aggregate, delta%, category-level details; optional AI one-sentence summary (JSON); cached implicitly via getMonthlyAggregate.
- `GET /api/insights/monthly-summary?month=` in `src/routes/insights.routes.ts` — Pro-gated via checkEntitlement('advanced_insights').

**Missing pieces:** None.

**Unclear logic:** None.

**Implementation gaps:** None.

---

## 18. Yearly review generation

**Fully defined:** Partially  
**Implementing files/modules:**
- `src/services/analytics.service.ts` — getYearlyAggregate(userId, year): computes from Transaction for the year (totalSpent, totalIncome, topCategories, subscriptionTotal). No AI narrative.
- `GET /api/analytics/yearly?year=` in `src/routes/analytics.routes.ts` — returns raw yearly aggregate; no entitlement check (yearly_review is in billing but not enforced on this route).
- Billing: yearly_review entitlement exists; no dedicated “yearly review” narrative or AI summary.

**Missing pieces:**
- No “yearly review” narrative or AI-generated summary (e.g. “Your year in review” text). Only raw numbers.
- YearlyAggregate table is never populated; getYearlyAggregate does not use it.
- Route GET /api/analytics/yearly does not enforce yearly_review entitlement.

**Unclear logic:**
- yearly_review entitlement is defined but not used to gate any endpoint.

**Implementation gaps:**
- Enforce yearly_review on GET /api/analytics/yearly (or a dedicated yearly-review endpoint). Optionally add AI yearly summary and populate/use YearlyAggregate.

---

## 19. Free vs Pro feature gating

**Fully defined:** Yes  
**Implementing files/modules:**
- `src/services/billing.service.ts` — getEntitlements (PRO_USER_IDS, ENABLE_PRO_FOR_ALL; no StoreKit/Stripe); checkEntitlement(feature); consumeAiAnalysis (Redis counter, monthly limit); getAiUsageRemaining.
- Parse-screenshot: 402 when limit exceeded, body includes ai_analyses_remaining; success response includes ai_analyses_remaining when not unlimited.
- Insights: checkEntitlement('advanced_insights') before monthly-summary and behavioral.
- Export JSON: checkEntitlement('export_extended').
- Entitlements returned at GET /api/entitlements.

**Missing pieces:**
- subscriptions_dashboard and yearly_review are not enforced on any route (subscriptions and yearly aggregate are open to all).
- requireEntitlement middleware is never applied; each route does its own check.

**Unclear logic:** None.

**Implementation gaps:**
- Gate GET /api/subscriptions with subscriptions_dashboard and GET /api/analytics/yearly (or yearly-review) with yearly_review if intended. Optionally use requireEntitlement for consistency.

---

## 20. Subscription billing logic

**Fully defined:** No  
**Implementing files/modules:**
- `src/services/billing.service.ts` — isPro derived only from ENABLE_PRO_FOR_ALL or PRO_USER_IDS. Comment: “In production, resolve from subscription provider (StoreKit, Stripe, etc.).”
- No webhook or server-to-server logic for App Store or Stripe.

**Missing pieces:**
- No StoreKit 2 (iOS) integration.
- No Stripe (or other) subscription backend: no webhooks, no customer/subscription IDs in User or separate table, no receipt validation or subscription status sync.

**Unclear logic:** N/A.

**Implementation gaps:**
- Full billing implementation is missing: no purchase flow, no receipt validation, no webhook handlers, no mapping from external subscription state to isPro.

---

## 21. Database schema

**Fully defined:** Yes  
**Implementing files/modules:**
- `prisma/schema.prisma` — User, Transaction (with type, sourceImageHash, confidence, isDuplicate, subscriptionId, etc.), PendingTransaction, MerchantRule, Subscription (@@unique(userId, merchant)), MonthlyAggregate, YearlyAggregate, AiUsageLog. Indexes on userId + transactionDate, sourceImageHash, merchant, category.

**Missing pieces:** None for schema definition.

**Unclear logic:** None.

**Implementation gaps:**
- YearlyAggregate is never written (see §14).
- AiUsageLog is never used; AI usage is tracked in Redis only (airy:ai_usage:userId:month).

---

## 22. API routes

**Fully defined:** Yes  
**Implementing files/modules:**
- `src/routes/index.ts` — registers all route modules under /api.
- `src/routes/auth.routes.ts` — POST /api/auth/register-or-login.
- `src/routes/transactions.routes.ts` — POST parse-screenshot (sync + async), GET pending, POST pending/:id/confirm, POST /transactions, PATCH /transactions/:id, DELETE /transactions/:id, GET /transactions (cursor pagination: limit, cursor).
- `src/routes/subscriptions.routes.ts` — GET /api/subscriptions.
- `src/routes/analytics.routes.ts` — GET dashboard, GET monthly?month=, GET yearly?year=.
- `src/routes/insights.routes.ts` — GET monthly-summary, GET behavioral (Pro).
- `src/routes/export.routes.ts` — GET csv, GET json (Pro; with limit/cursor).
- `src/routes/entitlements.routes.ts` — GET /api/entitlements.
- `src/routes/merchant-memory.routes.ts` — GET/POST/DELETE merchant-rules.
- `src/index.ts` — GET /health, GET /health/ready (DB + Redis).

**Missing pieces:** None for documented API surface.

**Unclear logic:** None.

**Implementation gaps:** None. API.md may lag (e.g. parse-screenshot response now includes reason, ai_analyses_remaining; GET /transactions returns nextCursor, hasMore).

---

## 23. Background jobs

**Fully defined:** Yes  
**Implementing files/modules:**
- `src/queues/index.ts` — BullMQ connection; screenshotQueue (screenshot-processing), aggregatesQueue (aggregates-refresh); createScreenshotWorker, createAggregatesWorker.
- `src/queues/screenshot.job.ts` — processScreenshotJob runs ingestScreenshot.
- `src/queues/aggregates.job.ts` — processAggregatesJob: type 'refresh' → refreshMonthlyAggregate(userId, yearMonth); type 'subscriptions' → detectSubscriptions(userId).
- `src/worker.ts` — starts screenshot and aggregates workers only (no HTTP). Entrypoint: npm run worker.

**Missing pieces:** None.

**Unclear logic:** None.

**Implementation gaps:** None. No job populates YearlyAggregate (see §14).

---

## 24. Caching strategy

**Fully defined:** Yes  
**Implementing files/modules:**
- Redis: exchange rates (`airy:rates:{base}:{date}`), idempotency (`airy:idempotency:{key}`, `airy:idempotency:tx:{key}`), dashboard (`airy:dashboard:{userId}` 5 min), insights (`airy:insights:{userId}:{yyyy-MM}` 1 h), AI usage counter (`airy:ai_usage:{userId}:{month}`), rate limits (`airy:ratelimit:ip:*`, `airy:ratelimit:parse:*`).
- Invalidation: invalidateDashboardCache and invalidateInsightsCache called from ingestion and from transaction routes (create, update, delete, confirm pending).
- MonthlyAggregate table used as cache for getMonthlyAggregate; refreshed by aggregates job after ingestion.

**Missing pieces:** None.

**Unclear logic:** None.

**Implementation gaps:** None.

---

## 25. Error handling

**Fully defined:** Yes  
**Implementing files/modules:**
- `src/index.ts` — setErrorHandler: validation → 400 with details; else 500, logger.error with requestId, generic message.
- Routes: 401 Unauthorized (auth), 402 with code AI_LIMIT or ENTITLEMENT_REQUIRED, 404 Not found, 429 from rate-limit middleware (Retry-After).
- Zod parse throws; Fastify validation can return 400. No explicit Zod error formatter in index (relies on err.validation or generic 500).

**Missing pieces:**
- No centralized Zod error formatter (e.g. 400 with field-level errors when schema.parse fails in route handlers). Some routes use .parse() and may throw; error handler does not map ZodError to 400.

**Unclear logic:** None.

**Implementation gaps:**
- Add global or per-route handling for ZodError to return 400 and structured validation errors.

---

## 26. Retry logic

**Fully defined:** Yes (queues only)  
**Implementing files/modules:**
- `src/queues/index.ts` — screenshot-processing: attempts 3, backoff exponential delay 1000; aggregates-refresh: attempts 2.
- No retry in HTTP client or in services (e.g. fetch for rates, Anthropic) except as provided by BullMQ for job failures.

**Missing pieces:**
- No retry for external calls (Frankfurter, Anthropic) in currency or AI insight services.

**Unclear logic:** None.

**Implementation gaps:**
- Optional: retry with backoff for getRates and AI calls to improve resilience.

---

## 27. Logging

**Fully defined:** Yes  
**Implementing files/modules:**
- `src/lib/logger.ts` — pino, LOG_LEVEL, pino-pretty in non-production.
- index: requestId set in onRequest, passed to error handler (logger.error with requestId).
- transaction-ingestion: logger.warn on ingest item failure (with requestId when provided).
- rate-limit: logger.warn on Redis error (with requestId).
- observability/metrics: recordParseResult and recordAiUsage log with structured fields (metric, etc.).
- Queues: worker failed events logged in worker.ts and screenshot.job/aggregates.job.

**Missing pieces:** None for core flows.

**Unclear logic:** None.

**Implementation gaps:** recordAiUsage is never called (no AI usage logging to metrics beyond Redis counter). ARCHITECTURE mentions “minimize retention of raw OCR text in logs”; no explicit redaction of OCR in logs (ingestion does not log raw OCR).

---

## 28. Observability

**Fully defined:** Partially  
**Implementing files/modules:**
- `src/observability/metrics.ts` — recordParseResult (success, lowConfidence, duplicateSkipped, reviewRequired, latencyMs, userId, requestId) and recordAiUsage (userId, feature, tokens?). Both log via pino; comment says “wire to Prometheus/DataDog” but no exporter.
- Parse-screenshot route calls recordParseResult after ingest.
- requestId on request and in error logs.
- ARCHITECTURE folder lists request-logger; only metrics.ts exists in observability/.

**Missing pieces:**
- No Prometheus/OpenTelemetry metrics export. No health metrics (e.g. queue depth, latency percentiles).
- No request-logger middleware (file referenced in ARCHITECTURE does not exist).
- recordAiUsage is never invoked.

**Unclear logic:** None.

**Implementation gaps:**
- Add request-level logging middleware if desired. Call recordAiUsage where AI is used (e.g. insights, monthly summary). Optionally add metrics export for production.

---

## 29. Cost control

**Fully defined:** Yes  
**Implementing files/modules:**
- `src/services/billing.service.ts` — FREE_MONTHLY_AI_ANALYSES, consumeAiAnalysis (Redis incr), getAiUsageRemaining; unlimited for Pro.
- `src/middleware/rate-limit.ts` — per-IP (100/min), per-user parse (30/min); Redis sliding-window style; 429 + Retry-After.
- Deterministic-first pipeline reduces AI use; category uses rules/keywords; AI only in insights and monthly summary (Pro-gated). No AI in extraction path (and no AI extraction implemented).
- Exchange rates and dashboard/insights cached to reduce compute and external calls.

**Missing pieces:** None for defined scope.

**Unclear logic:** None.

**Implementation gaps:** None.

---

## 30. Security considerations

**Fully defined:** Partially  
**Implementing files/modules:**
- Auth: JWT (config.JWT_SECRET, 30d); authMiddleware uses JWT or, when ALLOW_DEV_USER_HEADER, x-user-id. In production ALLOW_DEV_USER_HEADER is false.
- index: helmet (contentSecurityPolicy false), cors (origin true), bodyLimit 1 MB.
- Rate limiting: per-IP and per-user parse.
- Idempotency: prevents replay of parse and manual transaction creation.
- No raw OCR or PII in error responses. Logs include requestId and userId but ingestion does not log OCR body.

**Missing pieces:**
- No input sanitization beyond Zod (e.g. no explicit XSS or injection hardening for free-text fields). No documented prompt-injection hardening for future AI extraction.
- JWT_SECRET optional in schema (min 16); auth routes may fail at runtime if JWT used without secret. CORS origin: true allows any origin.

**Unclear logic:** None.

**Implementation gaps:**
- Require JWT_SECRET when running with auth. Consider restricting CORS in production. Add prompt-injection and output validation when AI extraction is implemented.

---

## Summary table

| # | Subsystem                     | Defined | Missing / gaps |
|---|-------------------------------|--------|-----------------|
| 1 | iOS application architecture  | No     | Entire iOS app missing |
| 2 | Screen structure              | No     | No views/screens |
| 3 | Navigation system             | No     | No navigation layer |
| 4 | View models                   | No     | No view models |
| 5 | Services layer (backend)      | Yes    | requireEntitlement unused; no AI in category |
| 6 | Screenshot import flow        | Backend only | No iOS capture/OCR UI |
| 7 | OCR pipeline                 | Partial | No on-device OCR; no server image OCR |
| 8 | Transaction extraction engine| Partial | AI extraction schema unused; no AI extraction step |
| 9 | Duplicate detection system   | Yes    | — |
| 10| Merchant memory system        | Yes    | — |
| 11| Subscription detection engine| Yes    | — |
| 12| Manual transaction entry      | Backend only | No iOS form |
| 13| Currency conversion           | Yes    | — |
| 14| Analytics engine              | Yes    | YearlyAggregate never written |
| 15| AI insights engine            | Yes    | — |
| 16| AI Money Mirror system        | Partial | No anomaly logic; no dedicated endpoint |
| 17| Monthly summary generation    | Yes    | — |
| 18| Yearly review generation      | Partial | No narrative; yearly_review not gated; YearlyAggregate unused |
| 19| Free vs Pro feature gating    | Yes    | subscriptions_dashboard, yearly_review not enforced on routes |
| 20| Subscription billing logic    | No     | No StoreKit/Stripe; isPro from env only |
| 21| Database schema               | Yes    | YearlyAggregate, AiUsageLog unused |
| 22| API routes                    | Yes    | — |
| 23| Background jobs               | Yes    | No yearly aggregate job |
| 24| Caching strategy              | Yes    | — |
| 25| Error handling                | Yes    | ZodError not mapped to 400 |
| 26| Retry logic                   | Queues only | No retry for external APIs |
| 27| Logging                       | Yes    | recordAiUsage never called |
| 28| Observability                 | Partial | No metrics export; no request-logger |
| 29| Cost control                  | Yes    | — |
| 30| Security considerations       | Partial | JWT_SECRET optional; CORS open; no prompt-injection handling |

---

**Conclusion:** The backend is largely complete for the implemented scope (screenshot ingestion, transactions, subscriptions, analytics, insights, export, entitlements, jobs, caching, rate limits, idempotency). The iOS application does not exist. Gaps for production include: full iOS app; optional AI extraction and anomaly/Money Mirror clarity; yearly aggregate population and gating; real billing integration; observability and error-handling refinements; and security hardening (CORS, JWT, AI inputs/outputs).
