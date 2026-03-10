# Run the Airy iOS App in Xcode

Follow these steps to open, configure, and run the Airy iOS app.

## 1. Open the project

1. Open **Xcode**.
2. **File → Open** and select `Airy.xcodeproj` (in this folder).
3. Wait for Xcode to index the project.

## 2. Signing & Capabilities

1. In the project navigator, select the **Airy** project (blue icon).
2. Select the **Airy** target.
3. Open the **Signing & Capabilities** tab.
4. Under **Signing**, choose your **Team** (your Apple ID / development team).
5. Set **Bundle Identifier** if needed (e.g. `com.solosoft.airy` or your own, e.g. `com.yourcompany.airy`).
6. Ensure **Sign in with Apple** and **In-App Purchase** capabilities are present (they are declared in `Airy/Airy.entitlements`; Xcode may show them automatically when the target uses that entitlements file).

## 3. Run destination

1. In the toolbar, open the **destination** dropdown (next to the Run button).
2. Choose a **simulator** (e.g. iPhone 16, iOS 17+) or a **connected device**.

## 4. Build and run

1. Press **⌘R** (or click the Run button).
2. The app will build and launch on the selected destination.

## 5. Prerequisites

### Backend

The app talks to the Airy backend for auth, transactions, and entitlements.

- Start the backend from the repo root:  
  `cd backend && npm run dev`
- By default the app uses **base URL** `http://localhost:3000` (see `Airy/Core/API/Endpoints.swift`).
- For a device or another host, change `baseURL` in `Endpoints.swift` or configure the URL via a scheme / User Defaults if you add that support.

### Sign in with Apple

- **Simulator:** Sign in to an Apple ID in **Settings → [Your Name]** (or **Sign in to your iPhone**). Sign in with Apple in the app will use this account.
- **Device:** Use a device signed into an Apple ID. Ensure the App ID in the Apple Developer portal has **Sign in with Apple** enabled and matches the app’s bundle ID.

### In-App Purchase (IAP)

- Configure the subscription product in **App Store Connect** and add it to the app’s In-App Purchases.
- For testing, use a **Sandbox** Apple ID (App Store Connect → Users and Access → Sandbox).
- The app uses StoreKit 2; ensure the run destination has a sandbox account when testing purchases.

## 6. Optional: non-localhost API

If the backend runs on another machine or port:

- Edit `Airy/Core/API/Endpoints.swift` and set `baseURL` to your server (e.g. `http://192.168.1.10:3000`).
- For HTTPS and production, use a proper `https://` URL and ensure App Transport Security allows it if needed.

## Summary

| Step | Action |
|------|--------|
| 1 | Open `Airy.xcodeproj` in Xcode |
| 2 | Select Airy target → Signing & Capabilities: set Team and Bundle ID |
| 3 | Confirm Sign in with Apple and In-App Purchase from entitlements |
| 4 | Choose simulator or device |
| 5 | Run (⌘R) |
| 6 | Backend: `cd backend && npm run dev` |
| 7 | Sign in with Apple: Apple ID in Settings (simulator) or on device |
| 8 | IAP: configure in App Store Connect and use Sandbox account |
