# Airy — Interaction Map

For every screen, every tappable element: label, destination/result, state changes (local/server), can it fail, and what the user sees on failure.

**Legend**
- **Local state:** UI state, navigation, in-memory only.
- **Server state:** API call that changes backend data.
- **Both:** Local UI update + server change.

---

## 1. Root & auth

### ContentView
| Element | Type | Destination / result | State | Can fail? | On failure |
|--------|------|----------------------|-------|-----------|------------|
| (none) | — | Conditional: shows OnboardingFlowView, OnboardingView, or MainTabView | — | — | — |

---

### OnboardingFlowView (6-page flow, new users)

#### Page 1 — Welcome
| Element | Type | Destination / result | State | Can fail? | On failure |
|--------|------|----------------------|-------|-----------|------------|
| **Get Started** | Button | Advances to page 2 (Screenshots) | Local: `currentPage = 1` | No | — |
| **I already have an account** | Button / link | Calls `onFinish()` → sets `hasSeenOnboarding = true` → ContentView shows OnboardingView (Sign in) | Local: AppStorage | No | — |

#### Page 2 — Screenshots
| Element | Type | Destination / result | State | Can fail? | On failure |
|--------|------|----------------------|-------|-----------|------------|
| **Continue** | Button | Advances to page 3 | Local | No | — |
| **Skip** | Button | `onFinish()` → OnboardingView | Local | No | — |

#### Page 3 — Spending
| Element | Type | Destination / result | State | Can fail? | On failure |
|--------|------|----------------------|-------|-----------|------------|
| **Continue** | Button | Advances to page 4 | Local | No | — |
| **Skip** | Button | `onFinish()` → OnboardingView | Local | No | — |

#### Page 4 — Subscriptions
| Element | Type | Destination / result | State | Can fail? | On failure |
|--------|------|----------------------|-------|-----------|------------|
| **Continue** | Button | Advances to page 5 | Local | No | — |
| **Skip** | Button | `onFinish()` → OnboardingView | Local | No | — |

#### Page 5 — Money Mirror
| Element | Type | Destination / result | State | Can fail? | On failure |
|--------|------|----------------------|-------|-----------|------------|
| **Continue** | Button | Advances to page 6 (Pro offer) | Local | No | — |
| **Skip for now** | Button | `onFinish()` → OnboardingView | Local | No | — |

#### Page 6 — Airy Pro offer
| Element | Type | Destination / result | State | Can fail? | On failure |
|--------|------|----------------------|-------|-----------|------------|
| **Monthly / Yearly** | Buttons (plan toggle) | Selects plan; no navigation | Local: `selectedPlan` | No | — |
| **Start Free 7-Day Trial** | Button | StoreKit purchase → sync backend → `onFinish()` → OnboardingView | Both | Yes | Red `errorMessage` below CTA (e.g. "Product not available", StoreKit/network error) |
| **Maybe later** | Button | `onFinish()` → OnboardingView | Local | No | — |
| **Restore Purchase** | Button | StoreKit restore → on success `onFinish()` | Both | Yes | Red `errorMessage` (e.g. "No purchases found", or generic error) |

---

### OnboardingView (Sign in, returning users)

| Element | Type | Destination / result | State | Can fail? | On failure |
|--------|------|----------------------|-------|-----------|------------|
| **Sign in with Apple** | Button (system) | Apple sheet → API `POST /api/auth/apple` → `authStore.setAuth()` → MainTabView | Server + local auth | Yes | Red `errorMessage` below button (e.g. "Sign in failed", API/network message). Cancel = no message. |
| **Demo login** | Button (DEBUG only) | `registerOrLogin` → `authStore.setAuth()` → MainTabView | Server + local | Yes | Red `errorMessage` |

---

## 2. Main tab bar (MainTabView)

| Element | Type | Destination / result | State | Can fail? | On failure |
|--------|------|----------------------|-------|-----------|------------|
| **Dashboard** (tab) | Tab | Shows DashboardView | Local: `selectedTab = 0` | No | — |
| **Transactions** (tab) | Tab | Shows TransactionListView | Local: `selectedTab = 1` | No | — |
| **Import** (tab) | Tab | Shows ImportView | Local: `selectedTab = 2` | No | — |
| **Insights** (tab) | Tab | Shows InsightsView | Local: `selectedTab = 3` | No | — |
| **More** (tab) | Tab | Shows MoreTabView | Local: `selectedTab = 4` | No | — |

**Note:** No FAB in current implementation; tab bar only.

---

## 3. Tab 0 — Dashboard

### DashboardView
| Element | Type | Destination / result | State | Can fail? | On failure |
|--------|------|----------------------|-------|-----------|------------|
| (no tappable elements) | — | Read-only; `.task` loads data | Server read | Load can fail | `errorMessage` in ViewModel not shown in UI (gap) |

---

## 4. Tab 1 — Transactions

### TransactionListView
| Element | Type | Destination / result | State | Can fail? | On failure |
|--------|------|----------------------|-------|-----------|------------|
| **+** (toolbar) | Button | Presents AddTransactionView (sheet) | Local | No | — |
| **Filter pills** (All, Food, Transport, …) | Buttons | Sets `selectedFilter`; filters list in memory | Local | No | — |
| **Month section header** (e.g. "June 2025") | NavigationLink | Pushes MonthDetailView(monthKey, monthLabel) | Local | No | — |
| **Transaction card** (row) | NavigationLink | Pushes TransactionDetailView(transaction) | Local | No | — |

### MonthDetailView
| Element | Type | Destination / result | State | Can fail? | On failure |
|--------|------|----------------------|-------|-----------|------------|
| **Back (chevron)** | Button | `dismiss()` → pop to TransactionListView | Local | No | — |
| **Ellipsis (menu)** | Button | No-op (empty action) | — | No | — |
| **Bill/transaction row** | NavigationLink | Pushes TransactionDetailView(transaction) | Local | No | — |

Load failure: ViewModel sets `errorMessage`; not shown in UI (gap).

### TransactionDetailView
| Element | Type | Destination / result | State | Can fail? | On failure |
|--------|------|----------------------|-------|-----------|------------|
| **Edit** | Button | Presents AddTransactionView(transaction, onSuccess: dismiss) as sheet | Local | No | — |
| **Delete** | Button (destructive) | `DELETE /api/transactions/:id` → on success `dismiss()` | Server | Yes | Red text in List section (`errorMessage`) |
| **Sheet: AddTransactionView** | Sheet | Edit flow; on success sheet dismisses and `onSuccess()` pops detail | Both (PATCH) | Yes | Red error in AddTransactionView above Save button |

### AddTransactionView (new or edit)
| Element | Type | Destination / result | State | Can fail? | On failure |
|--------|------|----------------------|-------|-----------|------------|
| **Close (X)** | Button | `dismiss()` — sheet closes | Local | No | — |
| **Currency (e.g. USD ($))** | Menu | Sets `selectedCurrency`; disabled in edit mode | Local | No | — |
| **Expense / Income** | Toggle buttons | Sets `transactionType` | Local | No | — |
| **Category pills** (Food, Travel, Home, Other) | Buttons | Sets `selectedSheetCategory` / `selectedCategory` | Local | No | — |
| **Date row** | Button | Presents date picker sheet | Local | No | — |
| **Time row** | Button | Presents time picker sheet | Local | No | — |
| **Done** (date/time sheet) | Button | Dismisses picker sheet | Local | No | — |
| **Add Transaction / Save** | Button | POST create or PATCH update → on success dismiss + optional onSuccess() | Server | Yes | Red `errorMessage` above button (e.g. "Enter a valid amount", API error) |

---

## 5. Tab 2 — Import

### ImportView
| Element | Type | Destination / result | State | Can fail? | On failure |
|--------|------|----------------------|-------|-----------|------------|
| **Choose photo** | PhotosPicker (button) | System picker → `processImage()` → OCR + `POST /api/transactions/parse-screenshot` | Server | Yes | `resultMessage` can show failure; on 402 → PaywallView sheet. No inline error text for generic API failure (ViewModel has `errorMessage` but not displayed). |
| **Review N pending** | NavigationLink | Pushes PendingReviewView | Local | No | — |
| **Paywall** (sheet, when 402) | Sheet | PaywallView | — | — | See Paywall below |

### PendingReviewView
| Element | Type | Destination / result | State | Can fail? | On failure |
|--------|------|----------------------|-------|-----------|------------|
| **Edit** (per row) | Button | Presents PendingEditSheet(pending, overrides) | Local | No | — |
| **Reject** (per row) | Button | `DELETE /api/transactions/pending/:id` → reload list | Server | Yes | **Gap:** ViewModel sets `errorMessage`; UI does not show it. |
| **Confirm** (per row) | Button | `POST /api/transactions/pending/:id/confirm` → reload list | Server | Yes | **Gap:** ViewModel sets `errorMessage`; UI does not show it. |

### PendingEditSheet
| Element | Type | Destination / result | State | Can fail? | On failure |
|--------|------|----------------------|-------|-----------|------------|
| **Cancel** | Button | Dismisses sheet; `editPending = nil` | Local | No | — |
| **Confirm** | Button | Calls parent `confirm(id, overrides)` → API confirm with overrides → sheet dismisses, list reloads | Server | Yes | **Gap:** Confirm can fail (ViewModel `errorMessage`) but sheet has no error UI; user not informed. |

---

## 6. Tab 3 — Insights

### InsightsView
| Element | Type | Destination / result | State | Can fail? | On failure |
|--------|------|----------------------|-------|-----------|------------|
| (no primary tappable controls) | — | `.task` loads; on 402 sets `showPaywall = true` → PaywallView sheet | Server read | Load/402 | Paywall sheet; generic load errors not shown (ViewModel has `errorMessage`). |
| **Paywall** (sheet) | Sheet | PaywallView | — | — | See Paywall below |

---

## 7. Tab 4 — More

### MoreTabView
| Element | Type | Destination / result | State | Can fail? | On failure |
|--------|------|----------------------|-------|-----------|------------|
| **Settings** | NavigationLink (row) | Pushes SettingsView | Local | No | — |
| **Subscriptions** | NavigationLink (row) | Pushes SubscriptionsView | Local | No | — |

### SettingsView
| Element | Type | Destination / result | State | Can fail? | On failure |
|--------|------|----------------------|-------|-----------|------------|
| **View Plans** (Pro card) | Button | Sets `showPaywall = true` → PaywallView sheet | Local | No | — |
| **Base Currency** (row) | Display row | No action (chevron only; not wired) | — | No | — |
| **Color Theme** (row) | Display row | No action | — | No | — |
| **Merchant Memory Rules** (row) | Display row | No action (chevron only) | — | No | — |
| **Export Data** (row) | Display row | No action | — | No | — |
| **iCloud Sync** | Toggle | Sets `iCloudSyncOn` (local only; not persisted to server) | Local | No | — |
| **Monthly Summary** | Toggle | Sets `monthlySummaryOn` (local only) | Local | No | — |
| **Spending Alerts** | Toggle | Sets `spendingAlertsOn` (local only) | Local | No | — |
| **Face ID / Passcode Lock** | Toggle | Sets `faceIdLockOn` (local only) | Local | No | — |
| **Data Usage** (row) | Display row | No action | — | No | — |
| **Delete All Data** | Button | Presents confirmation dialog | Local | No | — |
| **Confirmation: Delete** | Button (dialog) | `authStore.logout()`; message says local/sign out | Local (auth clear) | No | — |
| **Confirmation: Cancel** | Button (dialog) | Dismisses dialog | Local | No | — |
| **Sign out** | Button | `authStore.logout()` → ContentView shows OnboardingView | Local | No | — |
| **Paywall** (sheet) | Sheet | PaywallView | — | — | See Paywall below |

### SubscriptionsView
| Element | Type | Destination / result | State | Can fail? | On failure |
|--------|------|----------------------|-------|-----------|------------|
| (no primary tappable list actions) | — | Load on appear; on 402 → PaywallView sheet | Server read | Load can fail | ViewModel `errorMessage` not shown (gap). |
| **Paywall** (sheet) | Sheet | PaywallView | — | — | See Paywall below |

---

## 8. Paywall (shared sheet)

**Entry points:** Import (402), Insights (402), Subscriptions (402), Settings “View Plans”, Onboarding page 6 (Start trial / Restore).

### PaywallView
| Element | Type | Destination / result | State | Can fail? | On failure |
|--------|------|----------------------|-------|-----------|------------|
| **Close** | Button | `dismiss()` — sheet closes | Local | No | — |
| **Subscribe** | Button | Load products → StoreKit purchase → sync backend → `didSucceed` → dismiss | Both | Yes | Red `errorMessage` below buttons (e.g. "Product not available", purchase/network error). Button disabled while `isPurchasing`. |
| **Restore purchases** | Button | StoreKit restore → on success `didSucceed` → dismiss | Both | Yes | Red `errorMessage` (e.g. no purchases found, or generic). Button disabled while `isRestoring`. |

**Note:** PaywallView also dismisses on `.airyEntitlementsDidChange` (entitlements updated elsewhere).

---

## 9. Paywall triggers summary

| Trigger | Screen | Condition | Result |
|---------|--------|-----------|--------|
| 402 on parse-screenshot | ImportView | AI limit exceeded, not Pro | Presents PaywallView sheet |
| 402 on Insights load | InsightsView | Not Pro | Presents PaywallView sheet |
| 402 on Subscriptions load | SubscriptionsView | Not Pro | Presents PaywallView sheet |
| View Plans | SettingsView | User tap | Presents PaywallView sheet |
| Start Free 7-Day Trial (onboarding) | OnboardingFlowView page 6 | User tap | Purchase flow (same logic as paywall); on success finish onboarding |
| Restore Purchase (onboarding) | OnboardingFlowView page 6 | User tap | Restore flow; on success finish onboarding |

---

## 10. Edit actions summary

| Screen | Element | Action | Destination / result |
|--------|--------|--------|------------------------|
| TransactionDetailView | Edit | Opens AddTransactionView(transaction) sheet | Edit transaction; on success sheet dismisses and detail pops |
| AddTransactionView | Save (when transaction != nil) | PATCH transaction | Server update; success → dismiss + onSuccess() |
| PendingReviewView | Edit (row) | Opens PendingEditSheet | Edit before confirm; Confirm → API confirm with overrides |

---

## 11. Confirm / Reject actions summary

| Screen | Element | Action | Server | On failure |
|--------|--------|--------|--------|------------|
| PendingReviewView | Confirm (row) | POST confirm pending | Yes | errorMessage set; **not shown in UI** |
| PendingReviewView | Reject (row) | DELETE pending | Yes | errorMessage set; **not shown in UI** |
| PendingEditSheet | Confirm | POST confirm with overrides | Yes | Parent ViewModel errorMessage; **sheet has no error UI** |
| SettingsView | Delete (in dialog) | Logout only (no server delete) | No | — |

---

## 12. Restore purchase actions

| Screen | Element | Result | On failure |
|--------|--------|--------|------------|
| PaywallView | Restore purchases | StoreKit restore → backend sync → dismiss if success | Red error text (e.g. no purchases found) |
| OnboardingFlowView (page 6) | Restore Purchase | StoreKit restore → on success `onFinish()` | Red error text below CTA |

---

## 13. Gaps and recommendations

1. **PendingReviewView:** Show `viewModel.errorMessage` when confirm or reject fails (e.g. banner or section above list).
2. **PendingEditSheet:** On confirm failure, show error in sheet (e.g. alert or inline text) and keep sheet open.
3. **DashboardView / TransactionListView / SubscriptionsView / InsightsView / MonthDetailView:** Where ViewModels set `errorMessage` on load failure, surface it in the UI (banner or inline).
4. **Settings rows (Base Currency, Merchant Memory Rules, Export Data, Data Usage):** Currently display-only; either wire to real screens/actions or remove chevrons to avoid implying tap.
5. **Settings toggles (iCloud Sync, Monthly Summary, Spending Alerts, Face ID):** Only local state; consider persisting (e.g. UserDefaults) or syncing to server if required.

---

*Generated from codebase; covers all buttons, links, tabs, toggles, menus, sheets, and paywall/restore/edit/confirm-reject flows.*
