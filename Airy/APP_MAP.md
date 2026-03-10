# Airy — Full App Map

Complete product navigation map: every screen, entry point, transition, modal, sheet, tab, nested flow, and user action. Use to verify app structure before final design.

---

## Part 1: Structured Screen Map

Each screen is listed with: name, how the user gets there, possible actions, where each action leads, state changes, and presentation type (push / modal / sheet / tab switch / full-screen cover).

---

### Root container

| Screen | How user gets there | Actions | Where action leads | State changes | Type |
|--------|---------------------|---------|--------------------|---------------|------|
| **ContentView** | App launch | (none; conditional content only) | — | — | Root |
| **OnboardingView** | Shown when `authStore.token == nil` (first launch or after sign out) | Sign in with Apple; Demo login (DEBUG only) | On success: auth state set → ContentView re-renders → MainTabView | `authStore.setAuth(token, userId)` | Full-screen replacement |
| **MainTabView** | Shown when `authStore.token != nil` | Tap tab 0–4 | Switches selected tab (Dashboard, Transactions, Import, Insights, More) | `selectedTab` | Tab bar (5 tabs) |

---

### Tab 0: Dashboard

| Screen | How user gets there | Actions | Where action leads | State changes | Type |
|--------|---------------------|---------|--------------------|---------------|------|
| **DashboardView** | Tap "Dashboard" tab (tag 0) | (none; read-only list) | — | ViewModel: `load()` fetches dashboard; `isLoading`, `thisMonth`, `deltaPercent`, `errorMessage` | Tab content (push root) |

*Note: Dashboard has no toolbar actions, no NavigationLinks, and no paywall trigger in the current ViewModel.*

---

### Tab 1: Transactions

| Screen | How user gets there | Actions | Where action leads | State changes | Type |
|--------|---------------------|---------|--------------------|---------------|------|
| **TransactionListView** | Tap "Transactions" tab (tag 1) | Tap row (NavigationLink); Tap "+" in toolbar | Row → TransactionDetailView (push); "+" → AddTransactionView (sheet) | ViewModel: `load()` fetches list | Tab content; push / sheet |
| **TransactionDetailView** | Tap a transaction row in TransactionListView | Tap "Delete" (toolbar) | Delete API call → on success `dismiss()` (pop) | Transaction deleted on backend; view pops | Push (navigation destination) |
| **AddTransactionView** | Tap "+" on TransactionListView | Tap "Cancel"; Tap "Save" | Cancel → dismiss sheet; Save → submit → on success `dismiss()` | New transaction created; sheet dismisses | Sheet (modal) |

---

### Tab 2: Import

| Screen | How user gets there | Actions | Where action leads | State changes | Type |
|--------|---------------------|---------|--------------------|---------------|------|
| **ImportView** | Tap "Import" tab (tag 2) | Tap "Choose photo" (PhotosPicker); Tap "Review N pending" (if pendingCount > 0) | Picker opens system UI → on selection `processImage`; Link → PendingReviewView (push) | ViewModel: `processImage` → resultMessage, pendingCount; on 402 (AI limit) → showPaywall = true → PaywallView sheet | Tab content; push; sheet (paywall) |
| **PendingReviewView** | Tap "Review N pending" in ImportView | Tap "Edit" on a row; Tap "Reject"; Tap "Confirm" (no edit) | Edit → PendingEditSheet (sheet); Reject → API delete → list reload; Confirm → API confirm → list reload | pending list reloaded; item removed | Push (navigation destination); sheet (edit) |
| **PendingEditSheet** | Tap "Edit" on a pending row in PendingReviewView | Tap "Cancel"; Tap "Confirm" (toolbar) | Cancel → dismiss sheet; Confirm → confirm API with overrides → dismiss sheet → PendingReviewView reloads | Pending converted to transaction; pending removed; sheet dismisses | Sheet (modal) |
| **PaywallView** (from Import) | Shown when ImportViewModel sets `showPaywall = true` (after 402 on parse-screenshot) | Tap "Close"; Tap "Subscribe"; Tap "Restore purchases" | Close → dismiss sheet; Subscribe → purchase flow → on success dismiss; Restore → restore flow → on success dismiss or error message | Entitlements may update; sheet dismisses on success | Sheet (modal) |

---

### Tab 3: Insights

| Screen | How user gets there | Actions | Where action leads | State changes | Type |
|--------|---------------------|---------|--------------------|---------------|------|
| **InsightsView** | Tap "Insights" tab (tag 3) | (none; load runs on appear) | — | ViewModel: `load()` → on 402 sets `showPaywall = true` → PaywallView sheet | Tab content; sheet (paywall) |
| **PaywallView** (from Insights) | Shown when InsightsViewModel sets `showPaywall = true` (402 on getMonthlySummary or getBehavioralInsights) | Same as PaywallView from Import | Same | Same | Sheet (modal) |

---

### Tab 4: More

| Screen | How user gets there | Actions | Where action leads | State changes | Type |
|--------|---------------------|---------|--------------------|---------------|------|
| **MoreTabView** | Tap "More" tab (tag 4) | Tap "Settings"; Tap "Subscriptions" | Settings → SettingsView (push); Subscriptions → SubscriptionsView (push) | — | Tab content; push |
| **SettingsView** | Tap "Settings" in MoreTabView | Tap "Sign out" | `authStore.logout()` → token/userId = nil → ContentView shows OnboardingView | Auth cleared; root switches to Onboarding | Push (navigation destination) |
| **SubscriptionsView** | Tap "Subscriptions" in MoreTabView | (none; load runs on appear) | — | ViewModel: `load()` → on 402 sets `showPaywall = true` → PaywallView sheet | Push; sheet (paywall) |
| **PaywallView** (from Subscriptions) | Shown when SubscriptionsViewModel sets `showPaywall = true` (402 on getSubscriptions) | Same as above | Same | Same | Sheet (modal) |

---

### Paywall (shared)

| Screen | How user gets there | Actions | Where action leads | State changes | Type |
|--------|---------------------|---------|--------------------|---------------|------|
| **PaywallView** | (1) Import: 402 after parse-screenshot; (2) Insights: 402 on load; (3) Subscriptions: 402 on load. Also: PaywallViewModel.loadProducts() can set didSucceed if already Pro → dismiss without showing purchase UI. | "Close" → dismiss; "Subscribe" → StoreKit purchase → sync backend → didSucceed → dismiss; "Restore purchases" → restore → didSucceed or errorMessage; Receiving `.airyEntitlementsDidChange` notification → didSucceed → dismiss | Sheet dismisses; user may be Pro | ViewModel: products, didSucceed, errorMessage; on success parent may refetch | Sheet (modal) |

---

### Onboarding (repeated for reference)

| Screen | How user gets there | Actions | Where action leads | State changes | Type |
|--------|---------------------|---------|--------------------|---------------|------|
| **OnboardingView** | App launch with no token; or after Settings → Sign out | "Sign in with Apple" → system sheet → success → API loginWithApple → setAuth; "Demo login" (DEBUG) → registerOrLogin → setAuth | MainTabView (via ContentView conditional) | authStore.token, authStore.userId | Full-screen replacement |

---

## Part 2: User Flow Map

Flows are described as step-by-step user actions and system responses.

---

### Flow: First launch → Sign in → Dashboard

1. User opens app → **ContentView** shows **OnboardingView** (no token).
2. User taps **Sign in with Apple** → system auth sheet.
3. User completes Apple auth → app calls `POST /api/auth/apple` → receives token and user.
4. App sets `authStore.setAuth(token, userId)` → **ContentView** re-renders → **MainTabView** with tab 0 (**Dashboard**).
5. **DashboardView** appears; `.task` runs `viewModel.load()` → dashboard data shown.

---

### Flow: Add transaction manually

1. User is on **MainTabView** → taps **Transactions** tab → **TransactionListView**.
2. User taps **"+"** in toolbar → **AddTransactionView** presented as **sheet**.
3. User fills amount, currency, type, merchant, category, date → taps **Save**.
4. App calls `POST /api/transactions` → on success `didSucceed = true` → **onChange** dismisses sheet.
5. User is back on **TransactionListView** (list not auto-refreshed unless view reloads).

---

### Flow: View and delete a transaction

1. User is on **TransactionListView** → taps a **transaction row** → **TransactionDetailView** pushed.
2. User taps **Delete** in toolbar → app calls `DELETE /api/transactions/:id` → on success `dismiss()`.
3. User is back on **TransactionListView** (stack pop).

---

### Flow: Import screenshot → result

1. User taps **Import** tab → **ImportView**.
2. User taps **Choose photo** → system PhotosPicker → user selects image.
3. **onChange(selectedItem)** → `viewModel.processImage(item)` → OCR + `POST /api/transactions/parse-screenshot`.
4. **Success:** `resultMessage` and optionally `pendingCount` updated; if `pendingCount > 0`, **"Review N pending"** NavigationLink appears.
5. **402 (AI limit):** ViewModel fetches entitlements; if not Pro, sets `showPaywall = true` → **PaywallView** sheet. User can subscribe/restore or close.

---

### Flow: Import → Pending review → Confirm

1. After import with pending items, user taps **"Review N pending"** → **PendingReviewView** pushed.
2. User taps **Confirm** on a row → `viewModel.confirm(id)` → `POST /api/transactions/pending/:id/confirm` → list reloads; item removed.
3. User remains on **PendingReviewView** (or can tap back to Import).

---

### Flow: Import → Pending review → Edit → Confirm

1. User is on **PendingReviewView** → taps **Edit** on a row → **PendingEditSheet** presented as **sheet**.
2. User edits amount, currency, merchant, date, category, type → taps **Confirm** in sheet.
3. App calls `POST /api/transactions/pending/:id/confirm` with body overrides → pending converted to transaction; sheet dismisses; **PendingReviewView** list reloads.

---

### Flow: Import → Pending review → Reject

1. User is on **PendingReviewView** → taps **Reject** on a row.
2. App calls `DELETE /api/transactions/pending/:id` → list reloads; item removed.

---

### Flow: Insights or Subscriptions → 402 → Paywall

1. User taps **Insights** or **Subscriptions** tab (or opens Subscriptions from More).
2. ViewModel `load()` runs → `GET /api/insights/monthly-summary` (or behavioral) or `GET /api/subscriptions` returns **402**.
3. ViewModel fetches entitlements; if not Pro, sets `showPaywall = true` → **PaywallView** sheet.
4. User can Subscribe, Restore, or Close.

---

### Flow: Paywall → Subscribe → Success

1. **PaywallView** is visible (from any entry point).
2. User taps **Subscribe** → StoreKit purchase sheet → user completes purchase.
3. App syncs via `POST /api/billing/sync` → ViewModel sets `didSucceed = true` → **onChange** dismisses sheet.
4. User returns to the screen that presented the paywall (Import, Insights, or Subscriptions).

---

### Flow: Paywall → Restore → No purchases found

1. User taps **Restore purchases** → StoreKit sync; no Pro entitlement found.
2. ViewModel catches `StoreKitError.noPurchasesFound` → sets `errorMessage` (e.g. "No purchases found for this Apple ID.").
3. Sheet stays open; user can close or try again.

---

### Flow: Sign out

1. User is in **More** tab → taps **Settings** → **SettingsView** pushed.
2. User taps **Sign out** → `authStore.logout()` → token and userId cleared.
3. **ContentView** re-renders → **OnboardingView** shown (full-screen replacement).

---

### Flow: Transaction.updates (background)

1. User is logged in; **ContentView** has started `StoreKitService.shared.startTransactionUpdatesListener()` in a detached task.
2. When StoreKit emits a transaction update (e.g. renewal, purchase on another device), listener syncs to backend and posts **.airyEntitlementsDidChange**.
3. If **PaywallView** is visible, it observes the notification and sets `didSucceed = true` → sheet dismisses.

---

## Part 3: Simplified Tree View

```
App launch
└── ContentView
    ├── [authStore.token == nil] → OnboardingView (full-screen)
    │   ├── Action: Sign in with Apple → API → setAuth → (replace with MainTabView)
    │   └── Action: Demo login (DEBUG) → API → setAuth → (replace with MainTabView)
    │
    └── [authStore.token != nil] → MainTabView (tab bar)
        │
        ├── Tab 0: Dashboard
        │   └── DashboardView
        │       └── (no navigation; read-only)
        │
        ├── Tab 1: Transactions
        │   └── TransactionListView
        │       ├── Push: row tap → TransactionDetailView
        │       │   └── Action: Delete → API → dismiss (pop)
        │       └── Sheet: "+" tap → AddTransactionView
        │           ├── Action: Cancel → dismiss
        │           └── Action: Save → API → dismiss
        │
        ├── Tab 2: Import
        │   └── ImportView
        │       ├── Action: Choose photo → system picker → processImage → (result or 402 → Paywall sheet)
        │       ├── Push: "Review N pending" → PendingReviewView
        │       │   ├── Action: Confirm (row) → API → reload list
        │       │   ├── Action: Reject (row) → API → reload list
        │       │   └── Sheet: Edit (row) → PendingEditSheet
        │       │       ├── Action: Cancel → dismiss
        │       │       └── Action: Confirm → API → dismiss → reload list
        │       └── Sheet: [402] → PaywallView
        │
        ├── Tab 3: Insights
        │   └── InsightsView
        │       └── Sheet: [402 on load] → PaywallView
        │
        └── Tab 4: More
            └── MoreTabView (List)
                ├── Push: "Settings" → SettingsView
                │   └── Action: Sign out → logout → (replace with OnboardingView)
                └── Push: "Subscriptions" → SubscriptionsView
                    └── Sheet: [402 on load] → PaywallView

PaywallView (sheet; from Import / Insights / Subscriptions)
├── Action: Close → dismiss
├── Action: Subscribe → StoreKit → sync → dismiss
├── Action: Restore → StoreKit → sync or "No purchases found"
└── On: .airyEntitlementsDidChange → dismiss
```

---

## Summary tables

### All screens (by type)

| Screen | Presentation | Parent / trigger |
|--------|--------------|------------------|
| OnboardingView | Full-screen replacement | ContentView (no token) |
| MainTabView | Root after auth | ContentView (has token) |
| DashboardView | Tab 0 | MainTabView |
| TransactionListView | Tab 1 | MainTabView |
| TransactionDetailView | Push | TransactionListView (row tap) |
| AddTransactionView | Sheet | TransactionListView ("+") |
| ImportView | Tab 2 | MainTabView |
| PendingReviewView | Push | ImportView ("Review N pending") |
| PendingEditSheet | Sheet | PendingReviewView ("Edit") |
| InsightsView | Tab 3 | MainTabView |
| MoreTabView | Tab 4 | MainTabView |
| SettingsView | Push | MoreTabView ("Settings") |
| SubscriptionsView | Push | MoreTabView ("Subscriptions") |
| PaywallView | Sheet | ImportView (402), InsightsView (402), SubscriptionsView (402) |

### Paywall entry points

| Entry point | Trigger |
|-------------|---------|
| Import | 402 from `POST /api/transactions/parse-screenshot` (AI limit); only if entitlements say not Pro. |
| Insights | 402 from `GET /api/insights/monthly-summary` or behavioral insights on load; only if not Pro. |
| Subscriptions | 402 from `GET /api/subscriptions` on load; only if not Pro. |

### Onboarding steps

| Step | Description |
|------|-------------|
| 1 | Single screen: app name, tagline, Sign in with Apple button, (DEBUG) Demo login. |
| 2 | On success: setAuth → app shows MainTabView (no separate “steps” or carousel). |

### Settings subsections

| Section | Content |
|---------|---------|
| Account | User ID (read-only text), Sign out button. |
| About | “Airy — AI-first expense tracker” (static text). |

*No nested settings screens (e.g. no Notifications, Privacy, Support links in this build).*

### Transaction-related flows

| Flow | Entry | Steps | Exit |
|------|--------|-------|------|
| List → Detail | Transactions tab, tap row | TransactionDetailView | Back or Delete → pop |
| List → Add | Transactions tab, "+" | AddTransactionView sheet, Save | Dismiss sheet |
| Detail → Delete | TransactionDetailView, Delete | API delete | Pop |
| Pending list | Import → "Review N pending" | PendingReviewView | Back |
| Pending Confirm | Pending row, Confirm | API confirm | List reload |
| Pending Reject | Pending row, Reject | API delete | List reload |
| Pending Edit | Pending row, Edit | PendingEditSheet, Confirm | Dismiss, list reload |

### Screenshot import flows

| Flow | Entry | Steps | Exit |
|------|--------|-------|------|
| Import one photo | Import tab, Choose photo | PhotosPicker → processImage (OCR + API) | resultMessage; optional pendingCount; optional 402 → Paywall |
| To pending review | Import, "Review N pending" | Push PendingReviewView | Back to Import |

### Pending review flows

| Flow | Entry | Steps | Exit |
|------|--------|-------|------|
| Confirm inline | PendingReviewView, Confirm on row | POST confirm | Item removed, stay |
| Reject | PendingReviewView, Reject on row | DELETE pending | Item removed, stay |
| Edit then confirm | PendingReviewView, Edit on row | Sheet PendingEditSheet → edit fields → Confirm | POST confirm with overrides, sheet dismiss, item removed |

### Subscription-related flows

| Flow | Entry | Steps | Exit |
|------|--------|-------|------|
| View subscriptions | More → Subscriptions | SubscriptionsView, load() | 402 → Paywall sheet or list |
| Paywall (from Subscriptions) | 402 on getSubscriptions | PaywallView sheet | Subscribe / Restore / Close |

### Analytics and insights flows

| Flow | Entry | Steps | Exit |
|------|--------|-------|------|
| Dashboard | Tab 0 | DashboardView, load() → this month, delta, by category | Read-only |
| Insights | Tab 3 | InsightsView, load() → monthly summary + behavioral insights | 402 → Paywall sheet or content |
| (No dedicated “Analytics” tab; dashboard and insights are the analytics surfaces.) |

---

*This map reflects the codebase as of the current implementation. Use it to verify structure before applying final design.*
