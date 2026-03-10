# Airy — UX Review & Priorities

Senior product designer / iOS UX designer review of the interaction map. Outcomes: prioritized UX issues, screen-by-screen cleanup plan, and design priority order for redesigns.

---

## Part A — Findings from the interaction map

### 1. Dead ends

- **MonthDetailView → Ellipsis (menu):** Button is visible and looks tappable but has **no action**. User taps and nothing happens → dead end and broken affordance.
- **Settings → Base Currency, Color Theme, Merchant Memory Rules, Export Data, Data Usage:** Rows show chevrons (afford “tap to go somewhere”) but do nothing. User ends on the same screen with no feedback → **dead ends**.
- **DashboardView:** No way to act on the data (no “Add transaction” shortcut, no tap‑through from summary or recent activity). Screen is a **content dead end** unless we treat the whole tab as “glance only.”
- **InsightsView:** No primary tappable controls; content is read-only with no “drill into category” or “see more.” Feels like a **dead end** for engagement.
- **SubscriptionsView:** List is read-only; no “Add subscription” or “Manage” on items. **Dead end** for users who want to act.

### 2. Fake tappable elements

- **Settings:**  
  - **Base Currency** — chevron, looks like navigation; no action.  
  - **Color Theme** — same.  
  - **Merchant Memory Rules** — same.  
  - **Export Data** — same.  
  - **Data Usage** — same.  
  All read as “tap for more” but are **fake tappable**.
- **MonthDetailView → Ellipsis:** Looks like a context menu; **fake** (no-op).
- **Settings toggles (iCloud Sync, Monthly Summary, Spending Alerts, Face ID):** Look like real settings but **state is not persisted** (lost on restart). They’re fake in terms of “saving a preference.”

### 3. Screens that feel too passive

- **DashboardView:** Only consumption. No CTA, no “Add expense,” no tap from “Recent activity” or “Upcoming bills” into a clear next step. **Too passive** for a home screen.
- **InsightsView:** Rich content, zero actions. No “Improve this” or “See breakdown” or “Export.” **Too passive.**
- **SubscriptionsView:** List of subscriptions with no “Add,” “Edit,” or “Cancel” per item. **Too passive.**
- **TransactionListView:** Primary action “+” is in the toolbar; for a finance app, “Add transaction” could be more prominent (e.g. FAB or persistent CTA) so the screen doesn’t feel **slightly passive** relative to importance of adding.

### 4. Confusing transitions

- **Onboarding “Skip” vs “I already have an account”:**  
  - Pages 2–5: “Skip” goes to **Sign in** (OnboardingView).  
  - Page 1: “I already have an account” does the same.  
  Same destination, different labels and placement → **confusing**; “Skip” doesn’t clearly mean “skip to sign in.”
- **Edit transaction flow:** Transaction list → tap row → Detail → tap **Edit** → AddTransactionView sheet. After **Save**, sheet dismisses and detail **pops** (onSuccess). User lands on list, which is correct, but the “Edit” entry point is easy to miss (toolbar), and there’s no edit affordance on the list row itself → **transition is logical but discoverability is weak**.
- **Pending review:** “Review N pending” appears only after an import; if user leaves and comes back, the link is still there but the mental model “I just imported, now I review” is broken if they open it from a cold state → **context for the transition is unclear** on return.
- **Paywall from 402:** User hits limit on Import/Insights/Subscriptions and a paywall appears. “Close” returns to the same screen, which may still be empty or error-like. **Transition back** after closing paywall is confusing if the originating screen doesn’t explain “upgrade to continue” or offer a clear alternative.

### 5. Flows that are too deep

- **Transaction → Month → Transaction detail:**  
  List → tap month header → MonthDetailView → tap transaction → TransactionDetailView.  
  **Depth: Tab → List → Month → Detail = 4 levels.** For “see spending by day in a month” this is acceptable, but month could be a filter on the list to reduce depth.
- **Import → Pending → Edit (sheet) → Confirm:**  
  Import → “Review N pending” → PendingReviewView → Edit → PendingEditSheet → Confirm.  
  **Depth: 4 levels + sheet.** Edit sheet is fine; depth is mostly from “Import → Pending” as a separate screen. Consider inline pending or bottom sheet from Import to reduce depth.
- **More → Settings / Subscriptions:**  
  Tab → List → Settings or Subscriptions. **Depth: 3 levels.** Standard; OK.

### 6. Error states in code but not visible in UI

- **PendingReviewView:** Confirm and Reject set `errorMessage`; **never shown**. User can tap Confirm/Reject and see no change and no explanation → **critical**.
- **PendingEditSheet:** Confirm can fail (API); **no error UI in sheet**. User thinks it worked; sheet dismisses but list doesn’t update (or parent shows nothing) → **critical**.
- **DashboardView:** Load failure sets `errorMessage`; **not shown**. User sees empty or stale state with no reason → **high**.
- **TransactionListView:** Load failure sets `errorMessage`; **not shown**. Same as above → **high**.
- **SubscriptionsView:** Load failure sets `errorMessage`; **not shown** → **high**.
- **InsightsView:** Load failure sets `errorMessage`; **not shown** → **high**.
- **MonthDetailView:** Load failure sets `errorMessage`; **not shown** → **high**.
- **ImportView:** Generic API failure (non-402) sets `errorMessage`; **not displayed**. Only `resultMessage` and 402→paywall are visible → **medium**.

### 7. Main action not emphasized enough

- **DashboardView:** Main action (“Add expense” or “Log transaction”) is **absent**. Toolbar has no primary CTA; user must switch tab and tap “+.” Home should make the core action obvious.
- **TransactionListView:** “+” is in the toolbar (secondary). For a finance app, **Add transaction** could be a FAB or prominent bottom CTA so the main action is unmistakable.
- **ImportView:** “Choose photo” is the only action and is prominent; **OK**. Secondary “Review N pending” could be slightly more prominent when N > 0 (e.g. badge or card).
- **PendingReviewView:** Three equal buttons (Edit, Reject, Confirm) per row. **Confirm** is the primary outcome; it should be visually primary (e.g. filled, others outline).
- **AddTransactionView:** “Add Transaction” / “Save” is at bottom and styled as primary; **good**. Amount and type are clear; no change needed for emphasis.
- **PaywallView:** “Subscribe” is prominent; “Close” and “Restore” are secondary; **OK**.
- **Onboarding page 6:** “Start Free 7-Day Trial” is the main CTA; “Maybe later” and “Restore” are secondary; **OK**.

---

## Part B — Prioritized UX issues list

**P0 — Critical (trust and task completion)**

1. **Show errors in PendingReviewView** when Confirm or Reject fails (banner or inline above list).
2. **Show errors in PendingEditSheet** when Confirm fails (inline above form or alert); keep sheet open on failure.
3. **Remove or implement Settings chevron rows:** Either wire Base Currency, Merchant Memory Rules, Export Data, Data Usage (and optionally Color Theme) to real screens/actions, or remove chevrons and style as display-only.

**P1 — High (clarity and expectations)**

4. **Surface load errors** on Dashboard, TransactionList, Subscriptions, Insights, MonthDetail (banner or inline empty state with retry).
5. **Fix or remove MonthDetailView ellipsis:** Add a real menu (e.g. “Share month,” “Export”) or remove the control.
6. **Persist or remove Settings toggles:** Persist iCloud Sync, Monthly Summary, Spending Alerts, Face ID (e.g. UserDefaults) or remove until backend/settings exist so they’re not “fake.”
7. **Clarify onboarding “Skip”:** Use consistent copy (e.g. “Skip to sign in” on pages 2–5) or one “I already have an account” on page 1 only and replace “Skip” with “Next” where it only advances.

**P2 — Medium (engagement and depth)**

8. **Add a primary action on Dashboard:** e.g. “Add expense” or “Log transaction” (navigate to AddTransactionView or Import) so home isn’t a dead end.
9. **Emphasize primary action on TransactionListView:** Consider FAB or persistent “Add transaction” CTA so the main action is obvious.
10. **Make Confirm primary on PendingReviewView rows:** Visually primary (filled) vs Edit/Reject (secondary/outline).
11. **Improve return-from-paywall context:** On Import/Insights/Subscriptions, when closing paywall after 402, show a short message (“Upgrade for more” / “Limit reached”) or empty state with CTA instead of silent failure.

**P3 — Lower (polish and consistency)**

12. **Reduce transaction depth (optional):** e.g. “Month” as a filter or segment on TransactionListView instead of a full-screen MonthDetail for users who only want a quick glance.
13. **Add at least one action on InsightsView:** e.g. “See full report,” “Export,” or tap-through on a chart so the screen isn’t fully passive.
14. **Add at least one action on SubscriptionsView:** e.g. “Add subscription” or “Manage” on items so the list isn’t a dead end.

---

## Part C — Screen-by-screen cleanup plan

| Screen | Cleanup actions |
|--------|------------------|
| **ContentView** | No change. |
| **OnboardingFlowView** | Align “Skip” copy (e.g. “Skip to sign in” on 2–5); ensure page 6 CTA and error state stay clear. |
| **OnboardingView** | Keep error message below Sign in; ensure Demo login error is visible. |
| **MainTabView** | Optional: add FAB (e.g. “Add”) that opens AddTransactionView or Import; otherwise no change. |
| **DashboardView** | (1) Show `errorMessage` on load failure (banner + retry). (2) Add primary CTA: “Add expense” or “Log transaction” opening AddTransactionView or tab switch + sheet. |
| **TransactionListView** | (1) Show `errorMessage` on load failure (banner + retry). (2) Optional: FAB or prominent “Add transaction” CTA. |
| **MonthDetailView** | (1) Show load `errorMessage` (banner + retry). (2) Ellipsis: either add real menu (Share/Export) or remove. |
| **TransactionDetailView** | Keep Edit/Delete and error display; no structural change. |
| **AddTransactionView** | Keep error above Save; optional: improve date/time sheet “Done” visibility. |
| **ImportView** | (1) Show generic `errorMessage` when processImage fails (non-402). (2) Optional: make “Review N pending” more prominent when N > 0. |
| **PendingReviewView** | (1) Show `viewModel.errorMessage` (banner or section above list) when Confirm/Reject fails. (2) Make Confirm button visually primary per row. |
| **PendingEditSheet** | (1) On Confirm failure, show error in sheet (inline or alert) and keep sheet open. (2) Optional: retry button. |
| **InsightsView** | (1) Show load `errorMessage` (banner + retry). (2) Add at least one action (e.g. “See more,” “Export,” or tappable chart). |
| **MoreTabView** | No change. |
| **SettingsView** | (1) Base Currency, Color Theme, Merchant Memory Rules, Export Data, Data Usage: either wire to real screens/actions or remove chevrons and make clearly display-only. (2) Persist toggles (UserDefaults) or remove until real. (3) Keep Delete All Data and Sign out as-is. |
| **SubscriptionsView** | (1) Show load `errorMessage` (banner + retry). (2) Optional: “Add subscription” or row actions so screen isn’t dead end. |
| **PaywallView** | Keep error message below buttons; optional: softer copy for “no purchases found.” |

---

## Part D — Design priority list (which screens to redesign first)

Order is “first to redesign” to “later”; assumes visual/UX polish and alignment with the rest of the app.

1. **DashboardView**  
   - **Why first:** First screen after login; sets tone and should drive “add expense” or “see what matters.” Currently passive and no error UI.  
   - **Focus:** Primary CTA, error/empty states, hierarchy (total → summary → recent → upcoming).

2. **TransactionListView**  
   - **Why second:** Core loop (view + add transactions).  
   - **Focus:** Clear primary action (FAB or CTA), error/empty states, month as filter vs full-screen month (optional), consistency with Dashboard.

3. **AddTransactionView**  
   - **Why third:** Main creation flow; already sheet-based.  
   - **Focus:** Error placement, date/time UX, optional merchant field, consistency with design system.

4. **PendingReviewView + PendingEditSheet**  
   - **Why fourth:** Blocking flow after import; errors must be visible.  
   - **Focus:** Error UI (banner in list, inline in sheet), Confirm as primary, button hierarchy, empty state.

5. **PaywallView**  
   - **Why fifth:** Revenue and upgrade path.  
   - **Focus:** Clear benefit list, primary CTA, error and “restore” states, consistency with onboarding page 6.

6. **SettingsView**  
   - **Why sixth:** Many fake tappables and non-persisted toggles.  
   - **Focus:** Real destinations or display-only styling, persisted toggles or removal, Sign out and Delete prominence.

7. **InsightsView**  
   - **Why seventh:** High value but currently passive.  
   - **Focus:** At least one clear action, load/error state, optional drill-down or export.

8. **SubscriptionsView**  
   - **Why eighth:** Important but read-only.  
   - **Focus:** Load/error state, optional “Add” or row actions, consistency with Transactions.

9. **MonthDetailView**  
   - **Why ninth:** Useful but nested.  
   - **Focus:** Error state, ellipsis (real menu or remove), consistency with list and detail.

10. **ImportView**  
    - **Why last:** Already functional; one main action.  
    - **Focus:** Error message for generic failure, prominence of “Review N pending,” optional empty state.

11. **OnboardingFlowView (all pages)**  
    - **When:** After core app screens feel solid.  
    - **Focus:** Copy consistency (“Skip” vs “Skip to sign in”), page 6 CTA and error state, progress and hierarchy.

12. **OnboardingView**  
    - **When:** With or after onboarding flow.  
    - **Focus:** Error state, Sign in with Apple prominence, optional “I already have an account” from flow.

---

## Summary

- **Fix first:** Error visibility (PendingReview, PendingEditSheet, then all load errors); remove or implement fake tappables in Settings; fix or remove MonthDetail ellipsis; persist or remove Settings toggles.
- **Then:** Emphasize main actions (Dashboard CTA, Transaction list “Add,” Pending Confirm primary); clarify onboarding “Skip”; improve paywall return context.
- **Redesign order:** Dashboard → Transaction list → Add transaction → Pending review/edit → Paywall → Settings → Insights → Subscriptions → Month detail → Import → Onboarding.

This gives a single place (this doc) for product, design, and engineering to align on UX issues, cleanup, and redesign order.
