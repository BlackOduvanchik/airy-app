# TestFlight Launch Checklist

Use this checklist before submitting a build to TestFlight. Every item must be completed; there are no placeholders.

---

## 1. Backend environment (production)

- [ ] **Host:** Backend is deployed and reachable at an HTTPS URL (e.g. `https://api.yourdomain.com`). SSL certificate is valid.
- [ ] **Environment variables** (set on the production server):
  - `NODE_ENV=production`
  - `DATABASE_URL` — PostgreSQL connection string.
  - `REDIS_URL` — Redis connection string (or your queue/cache URL).
  - `JWT_SECRET` — At least 16 characters; keep secret. Required in production (server will not start without it).
  - `APPLE_BUNDLE_ID` — Exactly your iOS app’s bundle identifier (e.g. `com.solosoft.airy`). Must match the app’s Bundle ID in Xcode and in the Apple Developer portal.
  - `APPLE_APP_STORE_CONNECT_KEY_ID` — App Store Connect API key ID.
  - `APPLE_APP_STORE_CONNECT_ISSUER_ID` — App Store Connect issuer ID.
  - `APPLE_APP_STORE_CONNECT_PRIVATE_KEY` — Full contents of the .p8 file (including `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----`), or use `APPLE_APP_STORE_CONNECT_PRIVATE_KEY_PATH` to a path to the .p8 file on the server.
  - `ALLOWED_ORIGINS` — Comma-separated list of allowed CORS origins (e.g. `https://yourapp.com`). Optional if the iOS app is the only client.
- [ ] **Do not set** in production: `ALLOW_DEV_USER_HEADER=true` (it is forced to `false` when `NODE_ENV=production`).
- [ ] **Verify:** `curl -s -o /dev/null -w "%{http_code}" https://<your-api-url>/health` returns `200`.

---

## 2. Apple Developer / App Store Connect

- [ ] **App:** App is created in App Store Connect; Bundle ID matches `APPLE_BUNDLE_ID` and the Xcode project.
- [ ] **Sign in with Apple:** Capability “Sign in with Apple” is enabled for the App ID in the Apple Developer portal (Identifiers → your App ID → Sign in with Apple).
- [ ] **In-App Purchase:** Capability “In-App Purchase” is enabled for the App ID.
- [ ] **Subscription product:** An auto-renewable subscription product is created in App Store Connect (App → In-App Purchases). Product ID exactly matches the value in code: `airy_pro_monthly` (see `Airy/Features/Paywall/StoreKitService.swift`). If you use a different product ID, change `StoreKitService.productId` and create the product in App Store Connect to match.
- [ ] **App Store Connect API key:** Key is created (Users and Access → Integrations → App Store Connect API). Key has “App Manager” or required role. .p8 file is downloaded (only once); Key ID and Issuer ID are copied. These are the values used for `APPLE_APP_STORE_CONNECT_KEY_ID` and `APPLE_APP_STORE_CONNECT_ISSUER_ID` on the backend.
- [ ] **Sandbox testers:** At least one Sandbox tester is created (Users and Access → Sandbox → Testers) for testing purchases in TestFlight.

---

## 3. Xcode project (iOS)

- [ ] **Open:** Open `Airy/Airy.xcodeproj` in Xcode.
- [ ] **Team & signing:** Select the Airy target → Signing & Capabilities. Choose your Team. Ensure “Automatically manage signing” is on, or set a valid provisioning profile. Build for a real device or “Any iOS Device” for archive.
- [ ] **Bundle ID:** Matches the App in App Store Connect and `APPLE_BUNDLE_ID` on the backend (e.g. `com.solosoft.airy`).
- [ ] **Release API URL:** Select the Airy target → Build Settings → search “AIRY_API_BASE_URL”. Set the Release value to your production API URL (e.g. `https://api.yourdomain.com`). No trailing slash. This is used when building in Release configuration (Archive).
- [ ] **Capabilities:** “Sign in with Apple” and “In-App Purchase” are present (from `Airy/Airy.entitlements`). If not, add them via Signing & Capabilities.
- [ ] **Scheme:** Use the default scheme. Set Run configuration to Debug for local runs, and use Archive for TestFlight (Release).
- [ ] **Archive:** Product → Archive. Wait for archive to complete. Do not upload yet until the rest of the checklist is done.

---

## 4. Pre-upload verification (optional but recommended)

- [ ] **Debug build (simulator or device):** With backend running locally and `AIRY_API_BASE_URL` for Debug set to `http://localhost:3000`, run the app. Sign in with Apple (or Demo login in Debug). Confirm main tabs load. Trigger an import, pending review, and paywall flow if possible.
- [ ] **Release build (device):** Change scheme to use Release, or build for a device with Release. Set `AIRY_API_BASE_URL` for Release to your staging or production URL. Install on device. Sign in with Apple. Confirm API calls hit the correct host (e.g. check server logs or network proxy).

---

## 5. Upload to App Store Connect

- [ ] **Archive:** Product → Archive. Select the archive → Distribute App → App Store Connect → Upload. Complete the upload.
- [ ] **Build processing:** In App Store Connect → TestFlight → iOS → build, wait until the build shows “Ready to submit” or “Processing” then “Ready to submit”. Resolve any missing compliance or export compliance if prompted.
- [ ] **TestFlight:** Add the build to a TestFlight group (Internal and/or External). For external testing, submit for Beta App Review if required.

---

## 6. Post-upload verification (TestFlight build)

- [ ] **Install:** Install the TestFlight build on a device (same Apple ID as used for TestFlight).
- [ ] **Sign in with Apple:** Open the app. Tap Sign in with Apple. Complete the flow. Confirm you reach the main app (tabs). No “Demo login” button should be visible (Release builds do not include it).
- [ ] **API base URL:** Confirm the app is talking to production (e.g. trigger an action and check production backend logs or database).
- [ ] **Restore purchases:** If you have no prior purchase, tap Restore purchases. Confirm the message “No purchases found for this Apple ID.” appears (not a crash or blank).
- [ ] **Purchase (sandbox):** Sign out of App Store on device if needed; when prompted for Apple ID in the purchase flow, use a Sandbox tester account. Complete a subscription purchase. Confirm paywall dismisses and Pro features are available. Check backend: user’s subscription/entitlements are updated (e.g. GET /api/entitlements returns Pro).
- [ ] **Transaction.updates:** With the app in the foreground, trigger a renewal or use a different device with the same Sandbox account that has a subscription. Confirm the app updates entitlements (e.g. paywall dismisses or Pro state refreshes) without restarting.
- [ ] **Pending review:** If you have pending transactions, open Pending review. Confirm list shows decoded merchant/amount. Tap Edit, change a field, Confirm. Confirm the pending is removed and a transaction appears in the list. Tap Reject on another. Confirm it is removed.
- [ ] **Paywall from 402:** As a free user, exhaust AI analyses or call a Pro-only endpoint so the app receives 402. Confirm the app fetches entitlements first; if still not Pro, paywall is shown. If already Pro (e.g. from restore), paywall does not show.

---

## 7. Sign-off

- [ ] All sections 1–6 are completed.
- [ ] No production secrets (JWT_SECRET, .p8 contents) are committed to the repo or stored in the app.
- [ ] Privacy policy and App Store review guidelines (Sign in with Apple, IAP, data use) are satisfied; links or in-app disclosure are in place if required.

---

## Quick reference

| Item | Where |
|------|--------|
| Backend API URL (Release) | Xcode → Airy target → Build Settings → AIRY_API_BASE_URL (Release) |
| Product ID for IAP | `Airy/Features/Paywall/StoreKitService.swift` → `productId`; must match App Store Connect |
| Bundle ID | Xcode → Airy target → General → Bundle Identifier; must match backend `APPLE_BUNDLE_ID` |
| Entitlements file | `Airy/Airy/Airy.entitlements` (Sign in with Apple, In-App Purchase) |
