# Airy — Full User Journey Simulation

**Persona:** Alex, 28, uses a bank app and several subscriptions; occasionally grabs receipts and delivery confirmations. Tries Airy to “see where my money goes” without manual data entry.

**Scope:** First launch → 3 months. Includes onboarding, screenshot imports, transaction review, merchant learning, subscription detection, monthly summaries, AI insights, and duplicate detection. Friction points are called out as they occur.

---

## Week 1: First Launch & Onboarding

### Day 1 — First open

- Alex opens Airy. **Onboarding** (per product spec): likely a short welcome and permission prompts (camera, photo library, optional notifications).
- **Base currency** is set (e.g. USD) and optionally **Sign in with Apple** or “Continue as guest” (device-based id). No deep onboarding wizard is specified; the app may go straight to Home.
- **Home** is empty: “Total spent this month: $0”, no categories, no recent activity. The floating **+** button is prominent; bottom nav shows Insights (left), + (center), Settings (right).

**Friction 1 — Empty state:** Alex sees no value yet. There’s no clear “Add your first transaction” or “Snap a receipt to get started” CTA. If onboarding doesn’t explicitly say “take a screenshot of any payment or receipt,” they may not know the main action.

**Friction 2 — Value before data:** Without at least one import or manual entry, Insights and Analytics are empty. Risk of “nothing to see here” and drop-off.

---

### Day 1 — First screenshot

- Alex taps **+** → **Add screenshot** → chooses a Netflix payment confirmation from Photos (amount $15.99, date visible).
- App runs **on-device OCR** (Apple Vision), then sends OCR text + metadata to the backend. **Cloud mascot** shows: “Reading amounts” → “Checking dates” → “Matching categories” → “Looking for duplicates” → “Almost done.”
- Backend: parser extracts 1 transaction (15.99, USD, date, merchant “Netflix”); category classification → **subscriptions** (keyword match); no merchant rule yet; no duplicate; confidence high → **accepted**. No pending review.
- **Result:** “1 transaction added.” Home updates: “Spent this month: $15.99,” one category (subscriptions), one recent item.

**Friction 3 — Latency:** Sync path can take ~300–800 ms for one item (or more under load). If the mascot disappears too fast or too slow, the user may think it’s stuck or not notice feedback. No explicit “1 duplicate skipped” or “1 needs review” in this case.

---

### Day 2 — Second screenshot (Grab Food receipt)

- Alex adds a **Grab Food** receipt: total ฿289, date on screen. OCR returns Thai + numbers.
- Parser may extract amount and date; **currency** might default to USD if ฿/THB isn’t in the parser list → wrong conversion or stored as USD (**currency ambiguity**).
- Category: “grab.*food” → **food_delivery**. Accepted. Home shows two categories: subscriptions, food_delivery.
- **Merchant** might be stored as “Grab Food” or raw line text; no rule yet.

**Friction 4 — Currency/locale:** If the app doesn’t send locale or the backend doesn’t handle THB, the transaction is wrong. User may not notice until they check “why is my food so expensive in USD?”

---

### Day 3 — Receipt with poor OCR (partial / low confidence)

- Alex uploads a **cropped coffee receipt**: only “Total 5.50” visible, no date, no merchant name.
- Parser: amount 5.50, **date fallback = today**, merchant empty. Category: no keyword match → **other**; confidence **&lt; 0.6** → sent to **Pending review**.
- **Result:** “1 transaction added, 1 needs your review.” Alex has to find **where** to review. If the app has a “Pending” or “Review” section, they open it and see one item: amount $5.50, date today, category “other,” merchant blank. They can confirm or edit.

**Friction 5 — Pending review discoverability:** If “needs review” is only a small badge or buried in Settings, Alex may never fix it. Then they have an incorrect “other” transaction with today’s date. Clear entry point (e.g. Home banner “1 transaction needs review”) is critical.

**Friction 6 — Partial data:** The UI doesn’t explain that “date assumed today” or “merchant unknown.” Without that, Alex doesn’t know what to correct. No “usedFallbackDate” or similar hint in the current API.

---

### Day 4 — Merchant learning (first correction)

- A **ride receipt** (Bolt, $12.50) was categorized as **other** (e.g. merchant text was “Bolt Ride” and didn’t match transport rule, or confidence was low and it went to pending). Alex opens the transaction (or pending item), changes category to **Transport** and saves.
- Backend: on PATCH transaction (or on “confirm” with category), the app should call **merchant memory** (POST /merchant-rules or equivalent) so that “Bolt” → transport is stored. If the app doesn’t send that, the rule is **not** saved and the next Bolt receipt is wrong again.

**Friction 7 — Merchant rule not automatic:** Current design expects “user corrects → save rule.” If the app doesn’t call the merchant-rules API on edit, learning never happens. Even if it does, the user isn’t told “Bolt will be Transport next time,” so they don’t see the benefit of correcting.

---

### Day 5 — Duplicate detection (same screenshot twice)

- Alex re-uploads the **same Netflix screenshot** (same image from Photos).
- App sends same OCR + same **localHash** (if implemented). Backend: duplicate check finds same **sourceImageHash** (or high similarity) → **auto-skip**. Result: `accepted: 0, duplicateSkipped: 1`.
- If the app shows “1 duplicate skipped” or “This receipt was already added,” Alex understands. If the app only shows “0 transactions added” with no explanation, they may think the upload failed.

**Friction 8 — Duplicate feedback:** Backend returns `duplicateSkipped` and can return `duplicateOfId`, but the client must surface it. Without it, the user may retry or lose trust (“it didn’t add my receipt”).

---

### Day 7 — First week summary

- Alex has added ~5–7 screenshots: Netflix, Grab Food, Bolt, coffee, maybe a second subscription (Spotify). Home shows “Spent this month: ~$50,” category breakdown, recent list.
- **Subscription detection** has run in the background (after each ingestion). Netflix and Spotify may be marked as **subscription_candidate**; transactions get **isRecurringCandidate**. If the app has a **Subscriptions** screen (Pro), Alex might see “2 possible subscriptions.” Free users may not see this at all → **friction 9** (subscription value hidden behind Pro or unclear).
- **Insights** tab: with little data, insights are generic (“Most spending in subscriptions”) or empty. **AI insights** (e.g. Money Mirror) are Pro; free users see basic or nothing → **friction 10** (Insights feel thin for free users).

---

## Month 1: Habit & Learning

### Weeks 2–4 — Regular imports

- Alex uploads 2–4 screenshots per week: more delivery, a few rides, a grocery receipt, another subscription (e.g. Apple One). **Merchant rules** accumulate: Bolt → transport, Grab Food → food_delivery, “Coffee Shop XYZ” → food (after one correction).
- Some receipts have **multiple lines** (e.g. bank statement with 3 debits). Parser creates 3 transactions; all share the same screenshot hash. If Alex had already added one of those debits from another screenshot, **duplicate detection** might mark one as duplicate (same amount/date/merchant) and skip it. Good. If the same statement is uploaded twice, all 3 are skipped; feedback “3 duplicates skipped” matters.
- **Low-confidence** items still appear in Pending (e.g. odd merchant name, non-English). Alex reviews when they see the banner; sometimes they don’t and those items stay pending or get confirmed with wrong category, then they correct later → **merchant rule** updates.

**Friction 11 — Multiple transactions per screenshot:** If 5 items are parsed and the sync path is slow (1–3 s), the mascot runs long. No “we’re processing 5 transactions” progress; user may think the app is hanging. Async (202) for large batches would help but isn’t in the current flow.

**Friction 12 — Subscription status overwrite:** When the user explicitly marks “Netflix is not a subscription” (or dismisses it), the backend’s **detectSubscriptions** runs again on next ingestion and can overwrite status back to **subscription_candidate**. User’s choice isn’t persisted → frustration.

---

### End of Month 1 — First monthly summary

- **Monthly summary** (e.g. “You spent 14% more than last month” + category deltas) is generated when Alex opens Insights or a “Monthly summary” card. Backend: **getMonthlySummary** loads current + previous month aggregates. Previous month has few or no transactions (new user), so “vs last month” is “100% more” or “N/A.” First month summary can feel meaningless.
- **AI summary** (Pro): one short sentence from the model. **Cache** is per user+month; first view triggers the AI call (~300–800 ms). If the app doesn’t show a loading state, it feels slow.
- **Behavioral insights** (Pro): e.g. “Most spending in subscriptions,” “Top category: food_delivery.” Again, with only one month of data, patterns are weak.

**Friction 13 — First month summary weak:** “You spent X% more than last month” when last month was $0 is confusing or useless. The app could say “Your first month: you spent $X across Y categories” instead of a comparison.

**Friction 14 — Summary latency:** First time opening Monthly summary or Insights in a new month = 2× getMonthlyAggregate + 1 AI call. 400 ms–1 s. If there’s no skeleton or “Generating…” state, the screen feels empty or stuck.

---

## Month 2: Routine & Subscriptions

### Weeks 5–8 — Steady usage

- Alex is in a routine: ~10–15 screenshots per month (receipts, delivery, occasional bank screenshot). **Merchant memory** has 15–25 rules; most new receipts auto-categorize correctly. Fewer items in **Pending**.
- **Subscription detection** has tagged 3–4 recurring payments. Subscriptions screen (if Pro) shows “Netflix $15.99, Spotify $9.99, Apple One $X, …” and “Next billing” estimates. Alex can confirm or dismiss. If they dismiss “Apple One” as not a subscription, and the backend **overwrites** it next run → **friction 12** again.
- **Duplicate detection:** Alex sometimes re-uploads a receipt they already added (forgot, or from another device). Duplicate is skipped; if the app shows “Already added,” that’s clear. If not, **friction 8**.
- **Free user:** Alex is on free tier. After **10 AI analyses** (screenshot parses that count toward limit), the next screenshot returns **402 AI_LIMIT**. The app must show “Monthly limit reached” and either upsell Pro or “Add manually.” **Friction 15 — AI limit surprise:** If the limit isn’t shown until hit (“You’ve used 10 of 10”), the user is blocked without warning.

---

### End of Month 2 — Second monthly summary

- **getMonthlySummary** compares Month 2 vs Month 1. “You spent 8% more than last month. Biggest changes: food_delivery +20%, transport −10%.” That’s meaningful. **AI summary** (Pro) polishes it; **cache** means repeat views are instant.
- **Insights** (behavioral): “Weekend spending higher than weekdays,” “Late-night delivery increased” (if data supports it). **Cache TTL 1h:** If Alex adds transactions and reopens Insights within the hour, they might still see **stale** insights until cache invalidates. **Friction 16 — Stale insights:** No explicit “Insights updated” or invalidation-on-new-data in the current flow; user may see old numbers.

---

## Month 3: Power Use & Edge Cases

### Weeks 9–12 — More sources

- Alex tries a **bank statement** screenshot (5 debits in one image). Parser extracts 5 transactions. Sync path runs 5× duplicate check, 5× category, etc. **Latency** can be 1–3 s. Mascot runs for a long time; no “5 of 5” progress. **Friction 11** again.
- One of the 5 is a **refund** (negative amount). Parser uses **Math.abs**; it’s stored as **expense** with positive amount. Alex sees “refund” as money spent. **Friction 17 — Refund as expense:** No refund/income detection; user has to fix manually or the spending total is wrong.
- **Income:** Alex uploads a salary slip. Parser extracts amount; category might be “income” from keyword, but ingestion **hardcodes type = expense**. So “Salary $5,000” appears as **expense** and inflates “Total spent.” **Friction 18 — Income as expense:** Same as refund; totals are wrong until the product supports type and income detection.

---

### End of Month 3 — Third monthly summary & yearly view

- **Monthly summary:** “You spent 5% less than last month. Food delivery −15%, subscriptions unchanged.” Useful.
- **Yearly review** (Pro): If the app exposes “Year in review,” backend **getYearlyAggregate** runs (full year scan). For ~90 days of data it’s fine; for 500 tx/user over a full year it would be heavier. Currently no dedicated “yearly review” flow in the backend beyond getYearlyAggregate.
- **AI insights** (Money Mirror, anomaly): e.g. “You spend 40% more on weekends,” “Unusual: entertainment 3× your average.” Depends on Pro and enough data. **Anomaly** logic isn’t fully implemented; user might see generic insights. **Friction 19 — Insight depth:** Free users get minimal insights; Pro users may still see template-like cards if anomaly/behavior logic is shallow.

---

### Duplicate detection over 3 months

- **Same receipt re-uploaded:** Hash or amount/date/merchant match → skipped. Good.
- **Same merchant, same amount, different day (e.g. two coffee shops same price):** Duplicate check uses amount + date + merchant. Different day → lower score; usually **not** marked duplicate. Correct.
- **Same merchant, same amount, same day (e.g. two Uber rides):** Score can be high; might be **false positive** and skip the second ride. **Friction 20 — False positive duplicate:** User added two real transactions; one is skipped. They may not notice and their spending is undercounted, or they notice and don’t know why one “didn’t add.” “Add anyway” or “This isn’t a duplicate” would help.

---

## Friction Summary

| # | Friction | When it happens | Impact |
|---|----------|------------------|--------|
| 1 | Empty state unclear | First launch | User doesn’t know to add screenshots; drop-off |
| 2 | No value before data | First launch | Insights/analytics empty; weak first impression |
| 3 | Sync latency / mascot timing | Every screenshot | Feels slow or “stuck” if feedback is wrong |
| 4 | Currency/locale (e.g. THB) | Non-USD receipts | Wrong amounts or currency; confusion |
| 5 | Pending review hard to find | Low-confidence items | Items never corrected; wrong categories |
| 6 | No “assumed date” / partial data hint | Partial receipts | User doesn’t know what to edit |
| 7 | Merchant rule not saved or not communicated | After category correction | Next time category wrong again; no “we learned” message |
| 8 | Duplicate skipped with no explanation | Re-upload same receipt | “It didn’t add”; retries; trust loss |
| 9 | Subscription value hidden (Pro) or unclear | First weeks | Free users don’t see subscription detection benefit |
| 10 | Insights thin for free users | First weeks | Weak reason to stay or upgrade |
| 11 | Multi-item screenshot slow, no progress | 3+ items in one screenshot | Long wait; feels like hang |
| 12 | Subscription status overwritten by detector | After user dismisses subscription | User choice ignored; frustration |
| 13 | First month summary meaningless | End of month 1 | “X% vs last month” when last month = $0 |
| 14 | Summary/insights first-load latency | First open in month | Empty or slow screen; no skeleton |
| 15 | AI limit hit without warning | Free, after 10 analyses | Blocked; no prior “5 left” or similar |
| 16 | Stale insights (cache) | Add tx, reopen Insights soon | Old numbers; no “updated” signal |
| 17 | Refund stored as expense | Refund receipts | Spending total wrong |
| 18 | Income stored as expense | Salary/income screenshots | “Total spent” inflated |
| 19 | Insights feel generic | Pro, limited anomaly logic | Weak “Money Mirror” value |
| 20 | False positive duplicate (same day, same merchant/amount) | Two real tx same day | One skipped; undercount; no “add anyway” |

---

## Journey Map (Simplified)

```
First launch → Empty Home → [F1, F2]
     ↓
First screenshot → Mascot → 1 tx added → [F3]
     ↓
More screenshots (mixed quality) → Pending review, first correction → [F4–F7]
     ↓
Re-upload same receipt → Duplicate skipped → [F8]
     ↓
Week 1–4: Routine imports, merchant learning, subscription detection → [F9–F12]
     ↓
End Month 1: First monthly summary → [F13, F14]
     ↓
Month 2: Steady use, AI limit (free), subscription confirm/dismiss → [F12, F15, F16]
     ↓
End Month 2: Second summary (meaningful comparison) ✓
     ↓
Month 3: Bank screenshot (multi-tx), refund/income, duplicate edge cases → [F11, F17, F18, F20]
     ↓
End Month 3: Third summary, yearly view (Pro) → [F19]
```

---

## Recommendations to Reduce Friction

1. **Onboarding:** One clear step: “Snap or upload a receipt or payment screen to get started.” Empty state CTA: “Add your first transaction” with + or “Try a screenshot.”
2. **Pending review:** Persistent entry point (banner or tab) and explain “We need your help: date assumed today” / “Merchant unknown.”
3. **Duplicate result:** Always show “X added, Y duplicates skipped” and optionally “Already added: [receipt].”
4. **Merchant learning:** On category edit, call merchant-rules API and show “We’ll remember: [merchant] → [category].”
5. **Subscription detection:** Persist user confirm/dismiss; do not overwrite with subscription_candidate on next run.
6. **First month summary:** Special copy for “Your first month” (no comparison) or “Baseline set for next month.”
7. **Loading states:** Skeleton or “Generating…” for summary and insights; progress (“3 of 5 transactions”) for multi-item uploads.
8. **AI limit (free):** Show “X of 10 analyses left this month” and soft cap before 402.
9. **Cache invalidation:** On new transaction, invalidate insight cache for that user/month so next open is fresh (or show “Updated just now”).
10. **Refund/income:** Detect and set type = income; category refund/income; don’t inflate “Total spent.”
11. **False positive duplicate:** Return duplicateOfId and allow “Add anyway” (create with flag) or “Not a duplicate” for score in 0.7–0.95 range with user override.

This simulation and friction list can be used for UX copy, backend/API improvements, and prioritization of fixes before and after launch.
