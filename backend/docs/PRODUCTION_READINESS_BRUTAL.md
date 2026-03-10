# Production Readiness — Brutally Honest Assessment

This document separates what is **fully implemented**, **partially implemented**, **stubbed/placeholder**, and **likely to break in real use** in the current Airy implementation.

---

## 1. Fully implemented (can ship with caveats)

| Area | What's done | Caveats |
|------|-------------|--------|
| **Backend API structure** | All routes exist: auth, transactions, pending, analytics, insights, subscriptions, entitlements, export, merchant rules, billing sync. Auth middleware, rate limit by IP, request ID, health/ready. | No OpenAPI/Swagger; clients rely on code/docs. |
| **Backend ingestion pipeline** | Normalize → deterministic parse → (optional) AI extract → duplicate check → classify → convert → single Prisma transaction → enqueue aggregates/subscriptions/yearly. Idempotency and per-user parse rate limit. | AI extraction only when deterministic parse is empty; no fallback when AI returns malformed JSON. |
| **Pro feature gates** | 402 on subscriptions, yearly analytics, yearly-review, insights (monthly-summary, behavioral, money-mirror). Entitlements from config or User subscription fields. | No server-side receipt validation; trust client/StoreKit. |
| **Billing backend** | `syncAppStoreSubscription`, GET entitlements from User.subscriptionExpiresAt, POST /api/billing/sync. Prisma User fields for productId, expiresAt, transactionId. | No Apple Server Notifications; no validation that the transactionId is real. |
| **Background jobs** | BullMQ screenshot + aggregates workers; refresh monthly/yearly, detect subscriptions; retries and concurrency. | No dead-letter handling; no job priority; no metrics. |
| **Duplicate detection (backend)** | Hash-first, then batch scoring (amount, currency, date, merchant, OCR similarity). Auto-skip / duplicate-candidate / review. Levenshtein for merchant/text. | Thresholds and weights are heuristic; no tuning on real data. |
| **Anomaly detection** | Last 5 months per category, rolling average, flag when current > 2× average. Used in Money Mirror. | Fixed 2× threshold; no seasonality or minimum volume; noisy for new users. |
| **Yearly aggregate** | refreshYearlyAggregate, getYearlyAggregate reads table first, yearly job enqueued from ingestion. | |
| **Observability (backend)** | Zod in error handler, JWT required in prod, CORS ALLOWED_ORIGINS, withRetry on currency fetch, recordAiUsage for AI extraction and insights, request-logger (method, url, requestId, statusCode, durationMs). | recordAiUsage only logs; no Prometheus/DataDog. No SLO/alerting. |
| **iOS UI shell** | Tabs, NavigationStack, Dashboard, Transaction list/detail, Import, Pending review, Insights, Subscriptions, Settings, Paywall. ViewModels load from API. | No camera capture in flow; only photo picker. |
| **iOS manual transaction** | Full form (amount, currency, type, category, merchant, date, comment) and AddTransactionViewModel → POST /api/transactions. | |
| **iOS dashboard / insights / subscriptions** | DashboardViewModel → GET dashboard; InsightsViewModel → monthly summary + behavioral; SubscriptionsViewModel → GET subscriptions. 402 → present Paywall. | |

---

## 2. Partially implemented

| Area | What exists | What's missing or weak |
|------|-------------|------------------------|
| **Auth (iOS + backend)** | Backend: register-or-login by externalId + JWT. iOS: “Sign in with Apple (demo)” that sends a random `demo-<uuid>` and gets a token. | **No real Sign in with Apple.** No AuthenticationServices, no Apple ID credential, no identity token. Backend does not verify Apple tokens; any client can claim any externalId. Not acceptable for App Store. |
| **StoreKit integration (iOS)** | StoreKitService: load products by id, purchase, restore, syncToBackend(productId, transactionId, expiresAt). PaywallView shows products and Subscribe/Restore. | **No App Store Connect configuration:** product id is hardcoded `airy_pro_monthly`; no sandbox testing without a real product. **No receipt or transaction verification** on backend. **Restore** uses `Transaction.currentEntitlements` and syncs latest — no handling of “no entitlements” (e.g. user never purchased). **No subscription status listener** (e.g. `Transaction.updates`) to refresh UI when subscription changes. **No family sharing.** |
| **Anthropic integration (backend)** | AI extraction (when parse empty), monthly summary, behavioral insights, Money Mirror summary, yearly review. MOCK_AI and schema validation. Prompt says “ignore user instructions in OCR”. | **Single model** (claude-sonnet-4-20250514); no fallback if model deprecated. **No token caps** per request; no cost guardrails. **No OpenAI**; plan mentioned “Anthropic/OpenAI” but only Anthropic is implemented. **JSON parsing** is brittle: strip markdown then JSON.parse; one bad character can throw and we return []. **No retry** on Anthropic calls. |
| **Screenshot OCR (iOS)** | Vision VNRecognizeTextRequest, accurate level; image hash = SHA256 of JPEG at 0.5 quality. | **No preprocessing:** no deskew, crop, or contrast; bad photos will give poor text. **Hash** changes if user crops/annotates; duplicate detection may miss. **No camera flow** in Import (only PhotosPicker); no “take photo” path. **Language:** Vision uses device language; no explicit language hint for receipts in other locales. |
| **Pending review flow** | Backend: low-confidence items go to PendingTransaction; GET pending, POST confirm → create Transaction and delete pending. iOS: PendingReviewView list, Confirm per item, PendingReviewViewModel load/confirm. | **No “reject” or “edit then confirm”.** Confirm sends full payload to create transaction; no UI to fix amount/date/category before confirming. **Payload decoding on iOS** uses `AnyCodable` and force-casts in PendingRow (e.g. `payload["amountOriginal"]?.value as? Double`); if backend sends different shape (e.g. number as string), row falls back to “Transaction” with no details. **No pagination** on pending list. |
| **Paywall flow (iOS)** | PaywallView shows products, Subscribe/Restore, dismiss on success. PaywallViewModel calls StoreKitService and syncToBackend. | **No “already subscribed” state** from backend before opening paywall; user can open paywall even when Pro. **Restore** does not refresh AuthStore or entitlements in memory; dismiss happens but parent may not refetch. **No loading state** on initial product load (empty list until loadProducts completes). **@available(iOS 15)** on PaywallView/ViewModel/StoreKitService while app may target 17; unnecessary fragmentation. |
| **Duplicate detection quality** | Hash + weighted score; batch path to avoid N+1. | **Weights** (e.g. 0.2 amount, 0.2 merchant) are not data-driven. **OCR similarity** on full blob can match different receipts with similar layout. **No per-user tuning.** **False positives** will create “duplicate” when same merchant/amount in same week; **false negatives** when merchant name or amount format varies. |
| **Anomaly detection quality** | 2× rolling average per category. | **New users** (e.g. 1–2 months) get few data points; average is noisy. **No minimum spend** to avoid “anomaly” on tiny categories. **Single threshold** (2×); no severity bands. **No explanation** in UI (e.g. “You spent 3× more on food this month”). |

---

## 3. Still stubbed or placeholder

| Area | What it is today | What’s needed for production |
|------|-------------------|------------------------------|
| **Xcode project** | **No .xcodeproj.** Only folder tree and README saying “create project in Xcode and add files”. | Real Xcode project with app target, bundle id, signing, capabilities (Sign in with Apple, In-App Purchase), scheme, and all source/assets in the target. |
| **Sign in with Apple (iOS)** | Button label “Sign in with Apple (demo)” that calls register-or-login with a random id. | Use AuthenticationServices: ASAuthorizationAppleIDProvider, request credentials, send identity token (and optionally authorization code) to backend; backend verifies with Apple and maps to internal user. |
| **Backend auth** | Accepts any externalId and creates/returns JWT. No verification of Apple token. | Verify Apple identity token (or authorization code) server-side; bind externalId to verified Apple subject; reject unverified requests. |
| **Receipt / transaction verification (backend)** | syncAppStoreSubscription only stores what the client sends (productId, transactionId, expiresAt). | For production: verify with Apple (App Store Server API or Server Notifications v2). Validate transactionId and expiration before setting User.subscriptionExpiresAt. |
| **Camera in Import** | Import uses only PhotosPicker. | Add camera capture (e.g. UIImagePickerController or AVCaptureSession), then pass image to OCR and same upload flow. |
| **Pending “reject” / “edit”** | Only “Confirm”. | Allow reject (delete pending) and edit (prefill form, then confirm with corrections). |
| **Export (iOS)** | No UI for export. Backend has CSV/JSON with pagination. | Screen or setting to trigger export (and optionally pass limit/cursor), show progress, share/save file. |
| **Merchant rules (iOS)** | Backend has merchant-rules routes. No iOS UI to view or edit rules. | List rules, add/edit/delete (e.g. “Always categorize X as Y” / “Mark as subscription”). |
| **Transaction edit (iOS)** | TransactionDetailView shows details and Delete. | Edit amount, category, merchant, date (PATCH /api/transactions/:id) and refresh list. |
| **Deep linking / universal links** | None. | Optional: e.g. airy://pending, airy://transaction/:id for notifications or emails. |
| **Offline / local-first** | All data from API. No local DB. | Optional: cache transactions locally, queue uploads when offline, sync when online. |

---

## 4. Likely to break in real use

| Risk | Why |
|------|-----|
| **API response shape vs iOS models** | Backend returns Prisma/camelCase; some endpoints return snake_case (e.g. entitlements). iOS uses a mix of CodingKeys and direct names. One wrong key or type (e.g. number vs string) and decoding fails or shows wrong data. |
| **PendingTransaction.payload** | Backend stores payload as JSON; structure can vary (e.g. optional fields). iOS PendingRow assumes payload["amountOriginal"], payload["currencyOriginal"], payload["merchant"] and casts to Double/String. Missing or wrong type → generic “Transaction” row or crash if forced unwrap. |
| **StoreKit in Simulator / no product** | Without a real App Store Connect product and sandbox account, loadProducts() can return empty; purchase() will fail. Paywall will look “no product” or spin. Restore with no prior purchase returns no entitlements; we “return” without syncing and without clear “no purchases found” message. |
| **OCR on real screenshots** | Bank/receipt UIs vary a lot. Single block of text with newlines; no structure. Parser expects amount + date + merchant on/near same line; complex layouts (tables, multiple blocks) will produce wrong or multiple transactions. AI extraction helps only when deterministic parse is empty. |
| **Duplicate false positives** | Same merchant, similar amount, same week → high score and auto-skip. User may have two distinct purchases (e.g. two coffees); we will mark one duplicate. No “undo duplicate” or “this is not a duplicate” feedback loop. |
| **Anomaly noise** | First month with data: “2× average” can be tiny (e.g. $10 vs $5). Categories with one-off large spend (e.g. annual insurance) will always look anomalous. No context in UI. |
| **Rate limit and idempotency** | Parse-screenshot is rate-limited per user; idempotency by key. If client sends same idempotency key for different images, we return cached result. Client must generate key per logical request (e.g. per image). |
| **Worker and Redis** | If Redis is down, rate limit fails open (no block), but job enqueue fails and aggregates/subscriptions/yearly won’t refresh until next trigger. No queue persistence beyond Redis; no separate DLQ. |
| **JWT and token refresh** | Token has 30d expiry; no refresh flow. After expiry, every request is 401; user must “sign in” again. No refresh token or silent re-auth. |
| **PaywallView availability** | PaywallView is @available(iOS 15); some call sites present it without availability check. If deployment target is 17, usually fine; if someone lowers to 14, compilation or runtime issues. |

---

## 5. Summary by category

- **iOS app completeness:** **Partially implemented.** Shell and main screens exist; **no Xcode project**, **no real Sign in with Apple**, **no camera in Import**, **no export/merchant-rules/transaction-edit UI**, **pending flow is confirm-only**.
- **StoreKit integration realism:** **Partially implemented.** Purchase/restore/sync are wired, but **no server-side verification**, **no Store Connect product/sandbox in flow**, **no subscription status listener**, **restore UX when no purchase is weak**.
- **Anthropic/OpenAI integration realism:** **Partially implemented.** Anthropic is used and validated; **no OpenAI**; **no retries/caps**; **fragile JSON parsing**; single model.
- **Screenshot OCR reliability:** **Partially implemented.** Vision is used correctly; **no image preprocessing**, **no camera path**, **parser and AI tuned for “one block of text”** — real screenshots will often be messier.
- **Pending review flow:** **Partially implemented.** Backend and list/confirm exist; **no reject/edit**, **payload decoding is brittle on iOS**.
- **Paywall flow:** **Partially implemented.** UI and StoreKit calls exist; **no “already Pro” check**, **no subscription updates listener**, **restore feedback is poor**.
- **Background jobs:** **Fully implemented** for current scope; **no DLQ, no priority, no export to metrics**.
- **Duplicate detection quality:** **Implemented but heuristic;** will have **false positives and false negatives** in production; no tuning or user feedback.
- **Anomaly detection quality:** **Implemented but simple;** **noisy for new users and single thresholds**; no UX for “why” or severity.
- **App Store readiness:** **Not ready.** Missing: **real Sign in with Apple**, **working IAP with server verification**, **Xcode project and capabilities**, **privacy/manifest and receipt handling**. Demo auth and unverified billing would be rejected or risky.

---

## 6. Recommended order to reach “production-ready”

1. **Xcode project** and **real Sign in with Apple** (iOS + backend verification).
2. **App Store Connect product** + **sandbox testing**; then **server-side transaction/entitlement verification** (Apple Server API or notifications).
3. **Pending flow:** reject + edit-before-confirm; **robust payload decoding** (and/or shared DTO backend ↔ client).
4. **Paywall:** “already subscribed” from entitlements; **Transaction.updates** listener; clear restore messaging.
5. **OCR:** optional preprocessing; **camera in Import**; consider layout-aware or multi-block parsing.
6. **Duplicate/anomaly:** logging and metrics; **user feedback** (“not a duplicate” / “dismiss anomaly”); tune thresholds or add minimum volume.
7. **Resilience:** retry and token caps for Anthropic; **DLQ or dead-job handling** for workers; **JWT refresh** or re-auth flow.
