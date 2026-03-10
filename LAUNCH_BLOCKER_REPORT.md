# Final Launch Blocker Report

Strict, tiered list of what must be fixed before each gate. If an item is not done, do not proceed to the next gate.

---

## Must fix before local testing

*Definition: App runs (Debug), backend runs, you can sign in (Demo or Apple) and reach the main tabs.*

| # | Blocker | Why it blocks | Fix |
|---|---------|----------------|-----|
| 1 | **Backend will not start** | Missing or invalid env: `DATABASE_URL`, or Prisma/DB not reachable. | Set `DATABASE_URL` in `backend/.env` to a running PostgreSQL instance. Run `npx prisma db push` (or migrate) so schema exists. |
| 2 | **Auth fails after backend start** | Any sign-in (Demo or Apple) calls `app.jwt.sign()`; `getJwtSecret()` throws if `JWT_SECRET` is unset. | Set `JWT_SECRET` in `backend/.env` (min 16 chars). Required for both register-or-login and /auth/apple. |
| 3 | **Redis required for backend** | Rate limit and BullMQ use Redis; connection failure can break startup or requests. | Install/start Redis. Set `REDIS_URL` in `backend/.env` (default `redis://localhost:6379`). Ensure Redis is running before `npm run dev`. |
| 4 | **iOS app does not build or run** | No Team or invalid signing; or missing/invalid Bundle ID. | In Xcode: Airy target → Signing & Capabilities → select a valid Team; set Bundle Identifier (e.g. `com.solosoft.airy`). |
| 5 | **Sign in with Apple fails locally** | Backend returns 401 "APPLE_BUNDLE_ID is required" when using the real Apple button. | To test real Sign in with Apple (not Demo): set `APPLE_BUNDLE_ID` in `backend/.env` to the exact Bundle ID used by the app in Xcode. Apple Developer: enable Sign in with Apple for that App ID. |

**Not required for local testing:** App Store Connect, IAP product, App Store Connect API key, production API URL, Release build. Demo login works without `APPLE_BUNDLE_ID`.

---

## Must fix before sandbox IAP testing

*Definition: You can complete a subscription purchase in the app using a Sandbox account and have it sync to the backend.*

| # | Blocker | Why it blocks | Fix |
|---|---------|----------------|-----|
| 1 | **All “before local testing” items** | You must be able to run app and backend and sign in. | Complete the “before local testing” section. |
| 2 | **App not in App Store Connect** | TestFlight and IAP require an app record; bundle ID must match. | Create the app in App Store Connect with the same Bundle ID as Xcode. |
| 3 | **In-App Purchase capability missing** | StoreKit will not load products or allow purchase without the capability. | In Apple Developer: App ID → enable In-App Purchase. In Xcode: ensure `Airy.entitlements` includes In-App Purchase and is set in target’s Signing & Capabilities. |
| 4 | **No subscription product in App Store Connect** | `Product.products(for: ["airy_pro_monthly"])` returns empty; paywall shows no product; purchase is impossible. | In App Store Connect → app → In-App Purchases: create an auto-renewable subscription with Product ID exactly `airy_pro_monthly` (or change `StoreKitService.productId` in code to match the product you create). Submit and approve the product (or use “Ready to Submit” for sandbox). |
| 5 | **Sandbox tester not available** | Purchase sheet needs an Apple ID; production ID will charge real money. | App Store Connect → Users and Access → Sandbox → create a Sandbox tester. On device/simulator, when prompted for Apple ID during purchase, use that Sandbox account. |
| 6 | **Backend rejects sync in production mode** | If you run backend with `NODE_ENV=production` and send a real transactionId, sync throws when App Store Connect API is not configured. | For sandbox IAP you can either: (A) keep `NODE_ENV=development` so backend trusts client for sync, or (B) set full App Store Connect env (key ID, issuer ID, private key) and `APPLE_BUNDLE_ID` so server can verify the transaction. |

**Strict:** Without the IAP product and capability, sandbox IAP testing cannot be done. Product ID mismatch = no products loaded = no purchase.

---

## Must fix before TestFlight

*Definition: You can upload a build to TestFlight and install it; the build uses your production (or staging) API and does not crash or expose dev-only behavior.*

| # | Blocker | Why it blocks | Fix |
|---|---------|----------------|-----|
| 1 | **All “before sandbox IAP testing” items** | TestFlight build should be the same app that will do IAP and auth. | Complete the previous section. |
| 2 | **Release build crashes on launch** | `Endpoints.baseURL` in Release uses Info.plist / build setting; if `AIRY_API_BASE_URL` is empty or invalid, Release hits `fatalError`. | Xcode → Airy target → Build Settings → set `AIRY_API_BASE_URL` (Release) to your production (or TestFlight staging) API URL, e.g. `https://api.yourdomain.com`. No trailing slash. |
| 3 | **Backend not deployed or unreachable** | TestFlight build cannot talk to localhost. | Deploy backend to a host with HTTPS. Point `AIRY_API_BASE_URL` (Release) to that URL. Confirm `GET <url>/health` returns 200. |
| 4 | **Production backend missing required env** | With `NODE_ENV=production`, server throws on startup without `JWT_SECRET`; Apple auth fails without `APPLE_BUNDLE_ID`. | On production server: set `NODE_ENV=production`, `JWT_SECRET` (min 16 chars), `DATABASE_URL`, `REDIS_URL`, `APPLE_BUNDLE_ID` (same as app’s Bundle ID). |
| 5 | **Demo login in Release build** | Demo login is compiled out with `#if DEBUG`; if for any reason a Release build is built with DEBUG defined, a back door exists. | Ensure the scheme used for Archive uses Release configuration. Do not add a custom Swift flag that defines DEBUG in Release. |
| 6 | **Archive or upload fails** | Signing, provisioning, or App Store Connect state. | Fix signing (Team, provisioning profile, capabilities). Resolve any “Unable to process” or “Invalid Bundle” in App Store Connect. |

**Strict:** A TestFlight build that crashes on launch or cannot reach the API is not usable. Release must have a valid `AIRY_API_BASE_URL` and a running backend.

---

## Must fix before App Store review

*Definition: Build and backend are acceptable for public release and comply with App Store and policy requirements.*

| # | Blocker | Why it blocks | Fix |
|---|---------|----------------|-----|
| 1 | **All “before TestFlight” items** | Submission is the same binary and backend as TestFlight. | Complete the TestFlight section. |
| 2 | **App Store Connect API not configured in production** | With `NODE_ENV=production`, POST `/api/billing/sync` with `transactionId` throws if App Store verification is not configured. Real users’ purchases would not update entitlements. | Set on production server: `APPLE_APP_STORE_CONNECT_KEY_ID`, `APPLE_APP_STORE_CONNECT_ISSUER_ID`, and either `APPLE_APP_STORE_CONNECT_PRIVATE_KEY` (full .p8 contents) or `APPLE_APP_STORE_CONNECT_PRIVATE_KEY_PATH`. Ensure `APPLE_BUNDLE_ID` matches the app. |
| 3 | **Privacy policy or data use not declared** | App Store requires a privacy policy URL if the app collects or uses user data (e.g. Sign in with Apple, transactions, AI). | Add a privacy policy URL in App Store Connect (App Information / App Privacy). If the app uses Sign in with Apple, ensure “Sign in with Apple” is declared and the policy covers it. |
| 4 | **Sign in with Apple not offered for third-party auth** | If you add other sign-in options (e.g. email) in the future, Apple requires Sign in with Apple to be offered as well. | Current app is Apple-only; no change needed. If you later add another social/account login, add Sign in with Apple as an option. |
| 5 | **In-App Purchase guidelines** | Restore must be available; subscription terms and pricing must be clear. | App already has “Restore purchases” and shows product price. Ensure subscription terms and duration are correct in App Store Connect and that the app does not link to external purchase for the same subscription. |
| 6 | **CORS / security** | If the app or a future web app calls the API from a browser, wrong CORS can block or expose the API. | Set `ALLOWED_ORIGINS` on production to the exact origin(s) that should be allowed, or leave unset if the only client is the iOS app (no browser). |
| 7 | **Secrets in repo or client** | `JWT_SECRET` or .p8 key in repo or in the app binary causes rejection or compromise. | Never commit `.env` or keys. Ensure production secrets are in env or a secrets manager only. App must not contain backend secrets. |
| 8 | **Broken or placeholder content** | Placeholder URLs, “Lorem” text, or non-functional features can cause rejection. | Replace any placeholder (e.g. default `AIRY_API_BASE_URL` in Build Settings) with the real production URL before submission. No “example.com” or “api.airy.app” unless that is your live API. |

**Strict:** Review can reject for missing privacy policy, IAP or Sign in with Apple misuse, or obvious placeholders. Production backend must verify subscriptions when users pay.

---

## Summary table

| Gate | Minimum you must have |
|------|------------------------|
| **Local testing** | Backend: `DATABASE_URL`, `JWT_SECRET`, `REDIS_URL`; DB and Redis running. iOS: Team + Bundle ID. For Apple sign-in: `APPLE_BUNDLE_ID` + capability. |
| **Sandbox IAP** | Above + App in App Store Connect; IAP capability; product `airy_pro_monthly` (or matching code); Sandbox tester. |
| **TestFlight** | Above + Deployed backend (HTTPS); Release `AIRY_API_BASE_URL` set; production env (`JWT_SECRET`, `APPLE_BUNDLE_ID`, etc.); Archive and upload. |
| **App Store review** | Above + App Store Connect API key on production for subscription verification; privacy policy; no placeholders; CORS and secrets correct. |

---

## Not in scope (but recommended)

- **JWT refresh:** 30d expiry only; user must sign in again after. Not a launch blocker but affects UX.
- **Transaction JWS signature verification:** Backend decodes Apple’s signed transaction but does not verify the JWS signature with Apple’s root; relies on HTTPS and Apple’s API. Acceptable for many apps; hardening is optional.
- **Camera in Import:** Only PhotosPicker; no in-app camera. Allowed by App Store; improve later if needed.
- **Export / merchant rules / transaction edit UI:** Backend exists; iOS UI minimal or missing. Not required for first release if not advertised.
