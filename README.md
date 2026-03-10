# Airy

iOS expense tracker app (SwiftUI) + Node.js backend. Clone this repo to run in Xcode on Mac and test the backend locally.

## Structure

- **`Airy/`** — Xcode project (SwiftUI app)
- **`backend/`** — Node.js + Fastify API (TypeScript, Prisma)

## Quick start (Mac)

### 1. Clone

```bash
git clone https://github.com/YOUR_USERNAME/YOUR_REPO_NAME.git
cd YOUR_REPO_NAME
```

(Replace with your GitHub repo URL after you create it.)

### 2. Run the iOS app in Xcode

1. Open **`Airy/Airy.xcodeproj`** in Xcode.
2. Select a simulator (e.g. iPhone 16) or a connected device.
3. Press **Run** (⌘R).

See **`Airy/RUN_IN_XCODE.md`** for more details (scheme, signing, API URL).

### 3. Run the backend (optional, for full flow)

The app can work with a remote API. For local testing:

```bash
cd backend
cp .env.example .env
# Edit .env: set DATABASE_URL, JWT_SECRET, etc.
npm install
npx prisma generate
npx prisma migrate dev
npm run dev
```

Then in Xcode, set the app's API base URL to `http://localhost:3000` (or your backend URL) via build settings / `AIRY_API_BASE_URL`. See `Airy/Airy/Core/API/Endpoints.swift` and backend `README.md`.

## Docs

- **`Airy/RUN_IN_XCODE.md`** — Run iOS app in Xcode
- **`Airy/APP_MAP.md`** — App navigation map
- **`Airy/INTERACTION_MAP.md`** — Tap/UX interaction map
- **`backend/README.md`** — Backend setup and API
- **`backend/API.md`** — API reference

## Upload this project to GitHub

If you have this repo only locally and want to push to GitHub:

1. Create a **new repository** on [GitHub](https://github.com/new) (empty, no README).
2. In the project root (where this README is), run:

```bash
git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO_NAME.git
git branch -M main
git push -u origin main
```

Use your actual GitHub username and repo name. If you use SSH:

```bash
git remote add origin git@github.com:YOUR_USERNAME/YOUR_REPO_NAME.git
git push -u origin main
```

After that, you can clone the repo on your Mac via Cursor or Terminal and open **`Airy/Airy.xcodeproj`** in Xcode to test.
