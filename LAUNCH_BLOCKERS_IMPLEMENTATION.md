# Launch Blockers — Implementation Summary

Exact files modified, code changes, and how to verify each fix. Source of truth: VERIFICATION_PACKAGE.md and this implementation.

---

## 1. Environment-based API baseURL (debug / staging / production)

**Files modified:**
- `Airy/Airy/Core/API/Endpoints.swift`
- `Airy/Info.plist`
- `Airy/Airy.xcodeproj/project.pbxproj`

**Changes:**
- **Endpoints.swift:** Replaced `static let baseURL = URL(string: "http://localhost:3000")!` with a computed `baseURL` that: (1) uses `ProcessInfo.processInfo.environment["AIRY_API_BASE_URL"]` if set; (2) else uses `Bundle.main.object(forInfoDictionaryKey: "AIRY_API_BASE_URL")` from Info.plist; (3) in DEBUG, falls back to `http://localhost:3000`; (4) in Release, `fatalError` if neither env nor plist is set.
- **Info.plist:** Added key `AIRY_API_BASE_URL` with value `$(AIRY_API_BASE_URL)` so the build setting is substituted.
- **project.pbxproj:** In Debug target build settings, added `AIRY_API_BASE_URL = "http://localhost:3000"`. In Release target build settings, added `AIRY_API_BASE_URL = "https://api.airy.app"`. Replace the Release value with your production URL before TestFlight.

**How to verify:**
1. Debug: Run the app (Debug scheme). Change nothing; baseURL should be `http://localhost:3000`. Start backend locally; sign in and confirm API calls work.
2. Override in run: Edit scheme → Run → Arguments → Environment Variables, add `AIRY_API_BASE_URL` = `https://staging.example.com`. Run; confirm requests go to that host.
3. Release: Set Release `AIRY_API_BASE_URL` in Build Settings to your production URL. Archive and run on device with Release; confirm no crash and requests hit production.

---

## 2. Dev-only fallbacks disabled in release

**Files modified:**
- `backend/src/config.ts`

**Changes:**
- `ALLOW_DEV_USER_HEADER`: In production (`NODE_ENV === 'production'`) it is forced to `false` regardless of env. In non-production it defaults to `true` unless explicitly set.
- Added a startup check: if `NODE_ENV === 'production'` and `JWT_SECRET` is missing, `loadConfig()` throws so the server does not start.

**How to verify:**
1. Production: Set `NODE_ENV=production` and omit `JWT_SECRET`. Start the server; it must exit with “JWT_SECRET is required in production”.
2. Production: Set `NODE_ENV=production`, `JWT_SECRET=atleast16charshere`, and `ALLOW_DEV_USER_HEADER=true`. Start the server; send a request with `x-user-id: some-id` and no JWT. Response must be 401 (dev header is ignored).
3. Development: With `NODE_ENV=development`, send `x-user-id: <valid-user-id>` and no JWT; request must succeed (dev header allowed).

---

## 3. App Store subscription verification hardened for production

**Files modified:**
- `backend/src/services/app-store-verify.service.ts`
- `backend/src/services/billing.service.ts`

**Changes:**
- **app-store-verify.service.ts:** Exported `isAppStoreConfigured()` so billing can check it.
- **billing.service.ts:** When `transactionId` is present: (1) If `NODE_ENV === 'production'` and App Store Connect is not configured, throw an error (sync rejected). (2) If `getTransactionInfo(transactionId)` returns `null` (e.g. Apple API 404) and we are in production, throw (do not trust client). (3) In non-production, when verification is not configured or returns null, continue to trust client for dev.

**How to verify:**
1. Production, verification not configured: Set `NODE_ENV=production`; do not set App Store Connect env vars. POST `/api/billing/sync` with body `{ "transactionId": "any" }` and valid JWT. Expect 500 and message that App Store Connect API must be configured.
2. Production, verification configured but invalid transaction: Set all App Store Connect vars. POST sync with a fake `transactionId`. Expect 500 and message that transaction could not be verified.
3. Non-production: With `NODE_ENV=development`, POST sync with `transactionId` and no App Store config; expect 200 and user updated from client body.

---

## 4. StoreKit restore and subscription state handling

**Files modified:**
- `Airy/Airy/Features/Paywall/StoreKitService.swift`
- `Airy/Airy/Features/Paywall/PaywallViewModel.swift`

**Changes:**
- **StoreKitService:** `StoreKitError` now conforms to `LocalizedError` with `errorDescription`. Added case `noPurchasesFound` with text “No purchases found for this Apple ID.” `restore()` now throws `StoreKitError.noPurchasesFound` when `currentEntitlements` has no Pro product instead of returning silently.
- **PaywallViewModel:** In `restore()`, catch `StoreKitError.noPurchasesFound` and set `errorMessage` to that description so the user sees the message; do not set `didSucceed`.

**How to verify:**
1. Install the app on a device with a Sandbox account that has never purchased. Open paywall, tap “Restore purchases”. Red text must show “No purchases found for this Apple ID.” Paywall must not dismiss.
2. After a successful purchase, tap Restore again; paywall should dismiss and no error.

---

## 5. Transaction.updates listener and entitlement refresh

**Files modified:**
- `Airy/Airy/Features/Paywall/StoreKitService.swift`
- `Airy/Airy/App/ContentView.swift`
- `Airy/Airy/Features/Paywall/PaywallView.swift`

**Changes:**
- **StoreKitService:** Added `static let shared = StoreKitService()`. Added `Notification.Name.airyEntitlementsDidChange`. New method `startTransactionUpdatesListener()`: runs `for await result in Transaction.updates`, for verified transactions of our product ID syncs to backend, finishes the transaction, and posts `airyEntitlementsDidChange` on the main actor.
- **ContentView:** New `.task(id: authStore.token)` that when token is non-nil starts `Task.detached { await StoreKitService.shared.startTransactionUpdatesListener() }` so the listener runs for the app lifetime when logged in.
- **PaywallView:** Added `import Combine` and `.onReceive(NotificationCenter.default.publisher(for: .airyEntitlementsDidChange)) { _ in viewModel.didSucceed = true }` so paywall dismisses when entitlements change (e.g. from another device or renewal).

**How to verify:**
1. With two devices (or simulator + device) using the same Sandbox account, purchase on one device. On the other, open the paywall and leave it open; when the first device completes purchase, the second should receive a transaction update (if StoreKit syncs), sync to backend, and post the notification so the paywall dismisses.
2. After a renewal or a restore on another device, reopen the app; entitlements should already be updated from the listener.

---

## 6. Robust typed pending payload decoding

**Files modified:**
- `Airy/Airy/Core/API/APIClient.swift`
- `Airy/Airy/Features/Import/PendingReviewView.swift`

**Changes:**
- **APIClient:** Added `struct PendingTransactionPayload: Codable` with optional `type`, `amountOriginal`, `currencyOriginal`, `amountBase`, `baseCurrency`, `merchant`, `title`, `transactionDate`, `transactionTime`, `category`, `subcategory`. On `PendingTransaction`, added computed `decodedPayload: PendingTransactionPayload?` that converts `payload` dictionary to `Data` via `JSONSerialization` and decodes to `PendingTransactionPayload`; returns nil if payload is missing or decode fails.
- **PendingReviewView:** `overridesFromPayload` now takes `PendingTransactionPayload?` and builds `ConfirmPendingOverrides` from its properties. `PendingRow` uses `transaction.decodedPayload` for display (merchant, amount, currency) and shows “Transaction” when nil. Edit sheet is still filled from overrides derived from `decodedPayload`.

**How to verify:**
1. Create a pending transaction in the backend (e.g. via import that produces low-confidence). Open Pending review; row must show merchant and amount when payload is well-formed.
2. Manually change a pending payload in the DB to a malformed or partial JSON; reload pending list. Row must show “Transaction” and Edit must still open without crashing; confirm with overrides must still work.

---

## 7. TestFlight launch checklist (no placeholders)

**File created:**
- `TESTFLIGHT_LAUNCH_CHECKLIST.md`

**Content:** A single checklist with seven sections: (1) Backend environment (production) with required env vars and verification curl; (2) Apple Developer / App Store Connect (App, Sign in with Apple, IAP, product ID `airy_pro_monthly`, API key, Sandbox testers); (3) Xcode project (Team, Bundle ID, Release `AIRY_API_BASE_URL`, capabilities, Archive); (4) Pre-upload verification; (5) Upload to App Store Connect; (6) Post-upload verification (Sign in with Apple, API URL, Restore message, Purchase, Transaction.updates, Pending review, Paywall from 402); (7) Sign-off. Quick reference table for where to set API URL, product ID, and Bundle ID. No placeholder values; every step is concrete.

**How to verify:** Walk through the checklist in order before uploading a build to TestFlight; confirm each box is applicable and completable with your real backend URL, bundle ID, and App Store Connect setup.
