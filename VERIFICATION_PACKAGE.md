# Airy — Full Verification Package

Exact proof of implementation: repository tree, files touched, API contracts, iOS file mapping, manual test steps, remaining stubs, and production gaps.

---

## 1. Exact current repository tree

```
d:\SoloSoft\ios\
├── Airy/
│   ├── Airy.xcodeproj/
│   │   └── project.pbxproj
│   ├── Airy/
│   │   ├── Airy.entitlements
│   │   ├── App/
│   │   │   ├── AiryApp.swift
│   │   │   └── ContentView.swift
│   │   ├── Core/
│   │   │   ├── API/
│   │   │   │   ├── APIClient.swift
│   │   │   │   └── Endpoints.swift
│   │   │   └── Auth/
│   │   │       ├── AppleSignInService.swift
│   │   │       └── AuthStore.swift
│   │   ├── Features/
│   │   │   ├── Dashboard/
│   │   │   │   ├── DashboardView.swift
│   │   │   │   └── DashboardViewModel.swift
│   │   │   ├── Import/
│   │   │   │   ├── ImportView.swift
│   │   │   │   ├── ImportViewModel.swift
│   │   │   │   ├── PendingReviewView.swift
│   │   │   │   └── PendingReviewViewModel.swift
│   │   │   ├── Insights/
│   │   │   │   ├── InsightsView.swift
│   │   │   │   └── InsightsViewModel.swift
│   │   │   ├── Onboarding/
│   │   │   │   └── OnboardingView.swift
│   │   │   ├── Paywall/
│   │   │   │   ├── PaywallView.swift
│   │   │   │   ├── PaywallViewModel.swift
│   │   │   │   └── StoreKitService.swift
│   │   │   ├── Settings/
│   │   │   │   └── SettingsView.swift
│   │   │   ├── Subscriptions/
│   │   │   │   ├── SubscriptionsView.swift
│   │   │   │   └── SubscriptionsViewModel.swift
│   │   │   └── Transactions/
│   │   │       ├── AddTransactionView.swift
│   │   │       ├── AddTransactionViewModel.swift
│   │   │       ├── TransactionDetailView.swift
│   │   │       ├── TransactionListView.swift
│   │   │       └── TransactionListViewModel.swift
│   │   ├── README.md
│   │   ├── Services/
│   │   │   └── OCRService.swift
│   │   └── Shared/
│   │       └── Components/
│   │           └── MainTabView.swift
│   ├── Assets.xcassets/
│   │   ├── AccentColor.colorset/Contents.json
│   │   └── Contents.json
│   ├── Info.plist
│   └── RUN_IN_XCODE.md
└── backend/
    ├── .env.example
    ├── API.md
    ├── ARCHITECTURE.md
    ├── docs/                    (audit and design docs)
    ├── package.json
    ├── prisma/
    │   ├── schema.prisma
    │   └── seed.ts
    ├── src/
    │   ├── config.ts
    │   ├── index.ts
    │   ├── lib/ (logger, prisma, redis, retry)
    │   ├── middleware/ (auth, entitlements, rate-limit)
    │   ├── observability/
    │   ├── queues/
    │   ├── routes/
    │   │   ├── auth.routes.ts
    │   │   ├── billing.routes.ts
    │   │   ├── transactions.routes.ts
    │   │   └── ... (analytics, entitlements, export, insights, merchant-memory, subscriptions, index)
    │   ├── schemas/
    │   │   ├── apple-auth.schema.ts
    │   │   ├── transaction.schema.ts
    │   │   └── ... (ocr-payload, ai-extraction)
    │   └── services/
    │       ├── apple-auth.service.ts
    │       ├── app-store-verify.service.ts
    │       ├── auth.service.ts
    │       ├── billing.service.ts
    │       └── ... (currency, transaction-ingestion, etc.)
    ├── tests/
    ├── tsconfig.json
    └── vitest.config.ts
```

---

## 2. Every file created or modified for the latest 7 items

| # | Item | Created | Modified |
|---|------|---------|----------|
| 1 | Xcode project + entitlements | `Airy/Airy.xcodeproj/project.pbxproj`, `Airy/Airy/Airy.entitlements` | — |
| 2 | RUN_IN_XCODE | `Airy/RUN_IN_XCODE.md` | — |
| 3 | Sign in with Apple (iOS) | `Airy/Airy/Core/Auth/AppleSignInService.swift` | `Airy/Airy/Features/Onboarding/OnboardingView.swift`, `Airy/Airy/Core/API/APIClient.swift`, `Airy/Airy/Core/API/Endpoints.swift`, `Airy/Airy.xcodeproj/project.pbxproj` (added AppleSignInService) |
| 4 | Backend Apple token verify | `backend/src/services/apple-auth.service.ts`, `backend/src/schemas/apple-auth.schema.ts` | `backend/src/config.ts`, `backend/src/services/auth.service.ts`, `backend/src/routes/auth.routes.ts`, `backend/package.json` (jose) |
| 5 | App Store subscription verify | `backend/src/services/app-store-verify.service.ts` | `backend/src/config.ts`, `backend/src/services/billing.service.ts`, `backend/package.json` (jose if not already) |
| 6 | Pending edit/reject | — | `backend/src/routes/transactions.routes.ts`, `backend/src/schemas/transaction.schema.ts`, `Airy/Airy/Core/API/APIClient.swift`, `Airy/Airy/Features/Import/PendingReviewViewModel.swift`, `Airy/Airy/Features/Import/PendingReviewView.swift` |
| 7 | Paywall entitlement check | — | `Airy/Airy/Features/Paywall/PaywallViewModel.swift`, `Airy/Airy/Features/Import/ImportViewModel.swift`, `Airy/Airy/Features/Insights/InsightsViewModel.swift`, `Airy/Airy/Features/Subscriptions/SubscriptionsViewModel.swift` |

**Created (11):**  
`project.pbxproj`, `Airy.entitlements`, `RUN_IN_XCODE.md`, `AppleSignInService.swift`, `apple-auth.service.ts`, `apple-auth.schema.ts`, `app-store-verify.service.ts`.

**Modified (18):**  
`OnboardingView.swift`, `APIClient.swift`, `Endpoints.swift`, `project.pbxproj`, `config.ts`, `auth.service.ts`, `auth.routes.ts`, `package.json`, `billing.service.ts`, `transactions.routes.ts`, `transaction.schema.ts`, `PendingReviewViewModel.swift`, `PendingReviewView.swift`, `PaywallViewModel.swift`, `ImportViewModel.swift`, `InsightsViewModel.swift`, `SubscriptionsViewModel.swift`.

---

## 3. Exact API contracts

All routes are mounted under prefix `/api` (see `backend/src/routes/index.ts`).

### POST /api/auth/apple

- **Auth:** None (public).
- **Request body (JSON):**
  - `identityToken` (string, required): Apple JWT from `ASAuthorizationAppleIDCredential.identityToken` (UTF-8 string).
  - `email` (string, optional): If empty or omitted, server may use `email` from token payload when present.
- **Validation:** `appleAuthBodySchema`: `identityToken` min length 1; `email` optional, transformed to `undefined` if empty.
- **Success (200):**  
  `{ "token": "<JWT>", "user": { "id": "<cuid>", "email": "<string | null>" } }`
- **Errors:**
  - **400:** Invalid body → `{ "error": "Invalid body", "details": <Zod flatten> }`
  - **401:** Invalid or unverifiable Apple token → `{ "error": "<message>" }` (e.g. "APPLE_BUNDLE_ID is required for Apple Sign-In", "Invalid Apple token").
- **Behavior:** Verifies token with Apple JWKS (`https://appleid.apple.com/auth/keys`), `iss` = `https://appleid.apple.com`, `aud` = `APPLE_BUNDLE_ID`. Then `findOrCreateUserByAppleSubject(sub, email)` with `externalId = "apple_<sub>"`, signs JWT (30d), returns token and user.

---

### POST /api/billing/sync

- **Auth:** Required. `Authorization: Bearer <JWT>`. `userId` from JWT (or, when `ALLOW_DEV_USER_HEADER` is true, `x-user-id` header).
- **Request body (JSON):**
  - `productId` (string, optional)
  - `transactionId` (string, optional)
  - `expiresAt` (string, optional): ISO-8601 or parseable by `new Date(expiresAt)`.
- **Success (200):** Entitlements object (same shape as GET /api/entitlements):
  ```json
  {
    "monthly_ai_limit": number,
    "unlimited_ai_analysis": boolean,
    "advanced_insights": boolean,
    "subscriptions_dashboard": boolean,
    "yearly_review": boolean,
    "export_extended": boolean,
    "cloud_sync": boolean
  }
  ```
- **Behavior:**  
  If `transactionId` is provided and App Store Connect env is set: calls `getTransactionInfo(transactionId)`; if result is non-null and `isValid`, updates User from Apple (`productId`, `expiresAt`); otherwise (verification off or failed) when verification is not configured, trusts client and updates from body. Then returns `getEntitlements(userId)`.

---

### POST /api/transactions/pending/:id/confirm

- **Auth:** Required. Bearer JWT. Pending must belong to `userId`.
- **Params:** `id` (string) = pending transaction ID.
- **Request body (JSON, optional):** Partial transaction overrides. All fields optional; validated by `confirmPendingBodySchema` (= `createTransactionSchema.partial()`):
  - `type`: `"expense"` | `"income"`
  - `amountOriginal`: number (positive)
  - `currencyOriginal`: string (length 3)
  - `amountBase`: number (non-negative)
  - `baseCurrency`: string (length 3)
  - `merchant`: string (max 256)
  - `title`: string (max 512)
  - `transactionDate`: string `YYYY-MM-DD`
  - `transactionTime`: string (max 10)
  - `category`: one of `ALLOWED_CATEGORIES`
  - `subcategory`: string (max 64)
  - `isSubscription`: boolean
  - `comment`, `sourceType`: optional.
- **Success (200):** `{ "confirmed": true }`
- **Errors:** **404** if pending not found or not owned by user → `{ "error": "Not found" }`.
- **Behavior:** Loads pending, merges payload with body (override wins). If any of `amountOriginal`, `currencyOriginal`, `baseCurrency` are in overrides, recomputes `amountBase` via `convert(amountOriginal, currencyOriginal, baseCurrency)`. Creates `Transaction` with `sourceType: 'screenshot'`, deletes pending, invalidates caches.

---

### DELETE /api/transactions/pending/:id

- **Auth:** Required. Bearer JWT. Pending must belong to `userId`.
- **Params:** `id` (string) = pending transaction ID.
- **Success (200):** `{ "deleted": true }`
- **Errors:** **404** if pending not found or not owned → `{ "error": "Not found" }`.
- **Behavior:** `prisma.pendingTransaction.delete({ where: { id } })` after ownership check.

---

## 4. Exact iOS files by flow

### Sign in with Apple

- **Airy/Airy/Features/Onboarding/OnboardingView.swift** — `SignInWithAppleButton`, `handleAppleSignInResult`, extracts `identityToken` and `email` from `ASAuthorizationAppleIDCredential`, calls `APIClient.shared.loginWithApple(identityToken:email:)`, then `authStore.setAuth(token:userId:)`. Also `#if DEBUG` “Demo login” calling `registerOrLogin(externalId:email:)`.
- **Airy/Airy/Core/API/APIClient.swift** — `loginWithApple(identityToken:email:)` → POST `/api/auth/apple` with body `{ identityToken, email }`, decodes `AuthResponse`.
- **Airy/Airy/Core/API/Endpoints.swift** — `authApple = "/api/auth/apple"`.
- **Airy/Airy/Core/Auth/AppleSignInService.swift** — Defines `AppleSignInResult`, `AppleSignInService` (async `signIn()`); not used by current OnboardingView (which uses `SignInWithAppleButton` + inline credential handling).
- **Airy/Airy/Core/Auth/AuthStore.swift** — `setAuth(token:userId:)`, persistence; used after successful Apple or demo login.

### Paywall

- **Airy/Airy/Features/Paywall/PaywallView.swift** — Presents Pro copy, product list, Subscribe/Restore; `.task { await viewModel.loadProducts() }`, `onChange(of: viewModel.didSucceed)` dismisses.
- **Airy/Airy/Features/Paywall/PaywallViewModel.swift** — `loadProducts()`: first `APIClient.shared.getEntitlements()`; if `unlimitedAiAnalysis == true` sets `didSucceed = true` and returns; else loads StoreKit products. `purchase()`, `restore()` call `StoreKitService` and `syncToBackend`, set `didSucceed` on success.
- **Airy/Airy/Features/Paywall/StoreKitService.swift** — `productId = "airy_pro_monthly"`, `loadProducts()`, `purchase()`, `restore()`, `syncToBackend(productId:transactionId:expiresAt:)` → `APIClient.shared.syncBilling(...)`.
- **Airy/Airy/Features/Import/ImportViewModel.swift** — On 402, calls `getEntitlements()`; sets `showPaywall = true` only if `unlimitedAiAnalysis != true`.
- **Airy/Airy/Features/Insights/InsightsViewModel.swift** — Same 402 → getEntitlements → showPaywall only if not Pro.
- **Airy/Airy/Features/Subscriptions/SubscriptionsViewModel.swift** — Same.
- **Airy/Airy/Core/API/APIClient.swift** — `getEntitlements()`, `syncBilling(productId:transactionId:expiresAt:)`; `EntitlementsResponse` with `unlimitedAiAnalysis`, etc.

### Pending review (edit / reject)

- **Airy/Airy/Features/Import/PendingReviewView.swift** — List of pending; per row: Edit (sets `editOverrides` from payload, presents sheet), Reject (`viewModel.reject(id)`), Confirm (`viewModel.confirm(id)`). Sheet `PendingEditSheet`: form (amount, currency, merchant, date, category, type); on Confirm builds `ConfirmPendingOverrides` and calls `viewModel.confirm(id, overrides)`.
- **Airy/Airy/Features/Import/PendingReviewViewModel.swift** — `load()`, `confirm(id, overrides:)` → `APIClient.confirmPending(id, overrides)`, `reject(id)` → `APIClient.rejectPending(id)`.
- **Airy/Airy/Core/API/APIClient.swift** — `rejectPending(id)` → DELETE `/api/transactions/pending/{id}`; `confirmPending(id, overrides:)` → POST `/api/transactions/pending/{id}/confirm` with optional body; `ConfirmPendingOverrides` struct (only non-nil fields encoded).

### Screenshot import

- **Airy/Airy/Features/Import/ImportView.swift** — `PhotosPicker` → `onChange(selectedItem)` → `viewModel.processImage(item)`; shows result, `pendingCount`, NavigationLink to `PendingReviewView`; sheet `PaywallView` when `showPaywall`.
- **Airy/Airy/Features/Import/ImportViewModel.swift** — `processImage(_:)`: load image, `OCRService.recognizeText`, hash, `APIClient.shared.parseScreenshot(ocrText:localHash:baseCurrency:idempotencyKey:)`; on 402 fetches entitlements and sets `showPaywall` only if not Pro.
- **Airy/Airy/Services/OCRService.swift** — Vision `VNRecognizeTextRequest`, image hash.
- **Airy/Airy/Core/API/APIClient.swift** — `parseScreenshot(...)` → POST `/api/transactions/parse-screenshot`.

---

## 5. Exact end-to-end manual test steps

### Sign in with Apple

1. Backend: Set `APPLE_BUNDLE_ID` to the app’s bundle ID (e.g. `com.solosoft.airy`). Start backend (`cd backend && npm run dev`).
2. iOS: Open `Airy.xcodeproj`, select a simulator or device with an Apple ID signed in (Settings → [Your Name]).
3. Run app. On onboarding, tap **Sign in with Apple** (not “Demo login”).
4. Complete Apple sheet (Face ID / password if prompted).
5. **Pass:** App stores token and navigates to main app (tabs). **Fail:** 401 if token invalid or `APPLE_BUNDLE_ID` wrong/missing; 400 if body invalid.

### Importing a screenshot

1. Be logged in (Apple or Demo). Go to Import tab.
2. Tap “Choose photo”, pick an image that contains transaction-like text (amount, date, merchant).
3. **Pass:** “Accepted: N, Duplicates skipped: M, Pending: P” and optionally “Review K pending”. **Fail:** 402 if over AI limit → paywall sheet if not Pro; other errors in `errorMessage`.

### Editing and confirming a pending transaction

1. Have at least one pending (from import that produced “Pending” or from backend/DB).
2. Import tab → “Review N pending” or open Pending from elsewhere.
3. On a pending row, tap **Edit**. Sheet opens with amount, currency, merchant, date, category, type.
4. Change e.g. amount or category. Tap **Confirm** in sheet.
5. **Pass:** Sheet dismisses, that pending disappears; new transaction appears in transaction list (and dashboard/analytics). **Fail:** 404 if ID wrong or not owned; 400 if override body invalid.

### Rejecting a pending transaction

1. On Pending review list, tap **Reject** on one row.
2. **Pass:** That row disappears; no transaction created. **Fail:** 404 if not found or not owned.

### Triggering paywall from a Pro-gated endpoint

1. Use a non-Pro user (no subscription, not in `PRO_USER_IDS`, `ENABLE_PRO_FOR_ALL` false).
2. Option A: Import a screenshot and exhaust free AI analyses so next parse returns 402. **Pass:** After 402, app calls `getEntitlements()`; if not Pro, paywall sheet appears.
3. Option B: Call a Pro-only endpoint (e.g. GET `/api/insights/monthly-summary` or `/api/subscriptions`) without Pro. **Pass:** 402 → same entitlement check → paywall if not Pro.

### Completing a StoreKit purchase

1. App Store Connect: In-App Purchase for app, product ID `airy_pro_monthly` (or change `StoreKitService.productId` to match).
2. Device/simulator: Sign into Sandbox Apple ID (App Store Connect → Sandbox testers).
3. In app, open Paywall (e.g. trigger 402 or navigate to paywall if exposed). Tap **Subscribe**.
4. **Pass:** StoreKit purchase sheet → complete → `purchase()` returns transaction → `syncToBackend` called → paywall dismisses (`didSucceed = true`). **Fail:** No product if product ID not configured; restore with no prior purchase does nothing (no “no purchases found” message).

### Syncing entitlement to backend

1. After a successful purchase (or restore with existing entitlement), `StoreKitService.syncToBackend(productId:transactionId:expiresAt:)` is called.
2. It calls `APIClient.shared.syncBilling(productId:transactionId:expiresAt:)` → POST `/api/billing/sync` with JWT.
3. **With App Store Connect env set:** Backend calls Apple Get Transaction Info; if valid, updates User from Apple data and returns entitlements. **Without:** Backend trusts client body and updates User from that.
4. **Pass:** GET `/api/entitlements` (or next Pro-gated call) shows Pro (e.g. `unlimited_ai_analysis: true`). **Fail:** If Apple verification is on and transaction invalid or env wrong, sync does not update; entitlements stay free.

---

## 6. Remaining stubs, placeholders, weak spots, dev-only fallbacks

| Location | What | Notes |
|----------|------|------|
| **OnboardingView.swift** | `#if DEBUG` “Demo login” button | Uses `registerOrLogin(externalId: "demo-\(UUID()...)", email: nil)`. Shipped in DEBUG only; still a back door if DEBUG in release. |
| **Endpoints.swift** | `baseURL = URL(string: "http://localhost:3000")!` | Hardcoded; no scheme/env for production URL. |
| **config.ts** | `ALLOW_DEV_USER_HEADER` | Defaults true when `NODE_ENV !== 'production'`. Allows `x-user-id` to bypass JWT. Must be false in production. |
| **config.ts** | `JWT_SECRET` optional | Required for auth; app may start without it and fail at first sign-in. |
| **config.ts** | `APPLE_BUNDLE_ID` optional | Required for POST /api/auth/apple; 401 with “APPLE_BUNDLE_ID is required” if missing. |
| **config.ts** | `PRO_USER_IDS`, `ENABLE_PRO_FOR_ALL` | Pro-by-config; no UI; dev/testing only if used in prod. |
| **currency.service.ts** | `MOCK_EXCHANGE_RATES` | When true, fixed rates (USD, EUR, GBP); no real conversion. |
| **ai-extraction / ai-insight** | `MOCK_AI` | When true, skips Anthropic; returns stub summaries. |
| **apple-auth.service.ts** | No token revocation check | Verifies signature and claims only; does not check if user revoked Apple ID. |
| **app-store-verify.service.ts** | `decodeSignedTransactionInfo` | Decodes JWS payload only; does not verify Apple’s signature on the transaction JWS (relies on HTTPS and Apple response). |
| **app-store-verify.service.ts** | `createAppStoreJwt()` payload | Uses `bid` in SignJWT payload; Apple docs specify `bid` in payload; no explicit check that Apple accepts our JWT shape. |
| **billing.service.ts** | When verification not configured | Trusts client-supplied `productId`/`expiresAt`; no server-side guarantee. |
| **StoreKitService.swift** | `productId = "airy_pro_monthly"` | Hardcoded; must match App Store Connect. |
| **StoreKitService.restore()** | When no entitlements | Returns without error or user message; user sees no feedback. |
| **PendingReviewView / PendingEditSheet** | Payload → form | Uses `payload["amountOriginal"]?.value as? Double` etc.; backend payload shape or number-as-string can break or show “Transaction”. |
| **PaywallView** | No loading state for products | Products list empty until `loadProducts()` completes; no spinner on paywall content. |
| **Auth** | No refresh token | 30d JWT only; after expiry user must sign in again. |
| **PRODUCTION_READINESS_BRUTAL.md** | Pre-implementation audit | Describes old state (e.g. “no real Sign in with Apple”, “no reject/edit”); several items are now implemented but doc not updated. |

---

## 7. What is still not sufficient for real App Store production release

- **Apple Sign-In**
  - **APPLE_BUNDLE_ID** must be set and match the app’s bundle ID in production; otherwise Apple auth fails.
  - No “Revoke Apple ID” handling; user can revoke in system settings and backend still has the user.

- **App Store / IAP**
  - **App Store Connect:** Product must exist and be approved; `airy_pro_monthly` (or current `productId`) must match.
  - **Server verification:** For production, set `APPLE_APP_STORE_CONNECT_KEY_ID`, `APPLE_APP_STORE_CONNECT_ISSUER_ID`, and private key (or path). Without these, backend trusts client for subscription state.
  - **Transaction JWS:** Backend decodes Apple’s `signedTransactionInfo` but does not verify its signature with Apple’s root/cert chain; acceptable only if you trust the response from Apple’s API over HTTPS.
  - **Restore:** No “no purchases found” message; no `Transaction.updates` listener for subscription changes.

- **Security / config**
  - **ALLOW_DEV_USER_HEADER** must be false in production (enforced only by convention/env).
  - **JWT_SECRET** must be set and strong in production.
  - **CORS** (`ALLOWED_ORIGINS`) must be set for the real front-end origin(s).

- **iOS**
  - **Base URL:** Hardcoded `localhost`; need configurable or environment-specific API URL for production.
  - **Demo login:** If DEBUG is enabled in release build, demo login is a back door; ensure DEBUG is off for release.
  - **Camera:** Import uses PhotosPicker only; no in-app camera flow (App Store may still accept; UX limitation).

- **Backend robustness**
  - No retry/caps on Anthropic; fragile JSON parsing in AI responses.
  - No JWT refresh; 30d expiry forces re-login.
  - No OpenAPI/Swagger; contracts are code-only.

- **Compliance / policy**
  - Privacy policy and App Store review guidelines (e.g. Sign in with Apple, IAP, data handling) must be satisfied outside this codebase.
  - Export, merchant rules, transaction edit: backend exists; iOS UI is missing or minimal (see PRODUCTION_READINESS_BRUTAL.md).

This verification package reflects the codebase as of the implementation of the seven runnable-product items; it is the single source for “what exists” and “what remains” for production.
