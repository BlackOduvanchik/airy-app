# Airy — Edge Case Analysis

Analysis of failure scenarios across screenshot sources: bank apps, ride apps, food delivery, subscription receipts, crypto exchanges, and random payment confirmations. For each: (1) failure scenario, (2) how the current architecture handles it, (3) proposed improvements.

---

## 1. Screenshot OCR Failures

**Scenario:** On-device Vision OCR fails entirely (e.g. unsupported language, low light, corrupted image, or Vision returns empty/error). The app may send empty `ocrText`, a generic error string, or not call the backend at all.

**Current handling:**  
- Backend expects `ocrText` (required in schema). If the client sends empty string, `normalizeOcrText` yields `""`, `linesFromNormalized` yields `[]`, `parseTransactionsFromOcr` returns `[]`.  
- Ingestion then does `if (parsed.length === 0) { result.errors.push('No transactions found in OCR text'); return result; }`. So the user gets a single generic error and no transactions.  
- There is no distinction between “no text” (OCR failed) and “text present but no amounts/dates found” (parse found nothing). No server-side OCR fallback.

**Improvements:**  
- Differentiate in API: return a specific code when `ocrText` is empty or too short (e.g. `ocr_empty` or `ocr_failed`) vs when parsing found no transactions (`no_transactions_found`). Client can show “Screenshot couldn’t be read. Try better lighting or upload again” vs “No amounts or dates found in this screenshot.”  
- Enforce and document a minimum length (e.g. reject `ocrText.length < 10` with 400 and code `ocr_too_short`).  
- Add optional “upload image” flow: when client sends image (or OCR failed flag), backend runs server-side OCR (e.g. Vision API, Textract), then runs the same parse pipeline; store image with TTL and delete after processing for privacy.

---

## 2. Corrupted OCR Text

**Scenario:** OCR returns garbled or partially wrong text: wrong characters (0/O, 1/l), encoding issues, merged/split words, receipt-specific noise (“TOTAL”, “VAT”, random digits), or binary/non-UTF-8 data.

**Current handling:**  
- `normalizeOcrText` does NFKC, line endings, trim, collapse spaces. It does not fix common OCR substitutions (0/O, 1/l), strip non-printable characters, or handle invalid UTF-8.  
- Parser uses regex for amount/date; minor corruption (e.g. “12.99” → “12.99” with zero-width char) may still match; heavy corruption (e.g. “12.99” → “l2.99”) can break amount match.  
- Invalid UTF-8 can cause Node to throw or produce replacement chars; there is no explicit decode/validation step.  
- No max length; very long or binary payload can cause high memory or CPU.

**Improvements:**  
- Validate body is valid UTF-8 (or transcode from common encodings); reject with 400 if invalid.  
- Enforce max `ocrText` length (e.g. 50,000 characters).  
- Add optional normalization step: replace common OCR confusions (0/O, 1/l/I in numeric context), strip non-printable and control characters.  
- Consider “receipt cleanup”: detect lines containing only “TOTAL”, “VAT”, “SUBTOTAL” and either skip or use only for context (e.g. prefer last amount before “TOTAL”).  
- When parse returns 0 but text length is substantial, return a distinct code (e.g. `parse_failed_possible_corruption`) so the client can suggest “Try a clearer screenshot” or “Upload image instead.”

---

## 3. Screenshots with Multiple Transactions

**Scenario:** One screenshot shows several transactions (e.g. bank statement with 5 debits, food delivery order with itemized lines + total, subscription list with 3 renewals). We need to extract all of them and not merge or drop any.

**Current handling:**  
- Parser iterates line-by-line; any line with a parseable amount (and optional date) becomes one transaction. So multiple lines with amounts produce multiple `ParsedItem`s.  
- All items share the same `localHash` and the same `ocrText` (first 1000 chars) in duplicate detection, which can inflate OCR similarity between items from the same screenshot and cause false duplicate matches against an old transaction.  
- Type is hardcoded to `expense` for every item; income lines in the same screenshot are still stored as expense.  
- No “block” or “receipt” boundary: if one line has two amounts (e.g. “Subtotal 10.00 Total 12.50”), the regex may only capture one amount per line (first match), so the second amount can be missed or appear on a following line as a separate item.  
- No AI step to split/merge or resolve ambiguous multi-transaction layouts (e.g. “Item A 5.00 / Item B 5.00 / Total 10.00” vs one 10.00 transaction).

**Improvements:**  
- Use per-item OCR snippet (e.g. `rawLine` or a window around the line) for duplicate `ocrSimilarity` instead of the full shared OCR block.  
- Support `type: 'income'` when classifier returns category `income` (or when amount is negative in parser and semantics indicate refund/credit).  
- Add AI extraction path when parser returns multiple items or when layout is complex: send OCR (or image) to structured extraction (multi-transaction output with confidence), merge with deterministic parse, deduplicate, then persist.  
- Parser: consider “two amounts on one line” (e.g. match all amount occurrences and pair with date/time/merchant heuristics) or at least document that only one amount per line is extracted.  
- Cap items per request (e.g. 50); if more are parsed, return first N and a flag `truncated: true` or ask client to split into multiple uploads.

---

## 4. Screenshots with No Transactions

**Scenario:** User uploads a screenshot that has no financial transaction (e.g. order tracking, app menu, ad, or a receipt in an unsupported language with no recognizable amount/date format).

**Current handling:**  
- If parser returns `[]`, ingestion adds `errors: ['No transactions found in OCR text']` and returns without creating any transaction or pending item.  
- No differentiation between “empty OCR”, “OCR with no numbers”, and “numbers in wrong format” (e.g. “Total: 1.234,56” with comma as decimal in a locale the parser doesn’t handle).  
- Client gets the same error in all cases.

**Improvements:**  
- Return structured result: `{ accepted: 0, duplicateSkipped: 0, pendingReview: 0, pendingIds: [], errors: [...], reason: 'no_transactions_found' | 'ocr_empty' | 'parse_failed' }` so the client can show appropriate messaging.  
- If OCR text is non-empty but parse is empty, optionally call AI extraction once (e.g. “extract any financial transactions from this text”) with strict schema; if AI also returns none, then set `reason: 'no_transactions_found'`.  
- Suggest in UI: “No transactions detected. Make sure the screenshot shows an amount and date (e.g. receipt total, payment confirmation).”

---

## 5. Partial Transactions

**Scenario:** Only part of a transaction is visible (e.g. cropped receipt showing only “Total 15.00” with no date or merchant; or bank line “DEBIT 50.00” with date on another line that wasn’t captured). Parser may get amount but no date, or date but no amount, or wrong pairing (e.g. amount from one tx and date from another).

**Current handling:**  
- Parser requires at least an amount on a line to emit an item; date can come from the same line or the previous line (`parseDateFromLine(lines[i - 1])`). If no date is found anywhere, `parsedDate = new Date().toISOString().slice(0, 10)` (today).  
- So we can get: amount + today’s date, or amount + wrong date from a nearby line. Merchant is whatever remains on the line after stripping amount/date/time (can be empty or garbage).  
- No confidence per field; ingestion uses a single confidence from category classification. Low confidence (< 0.6) sends the item to pending review. Partial transactions often have weak merchant/category and may land in pending, but they can also get 0.5 and be saved as full transactions with “today” and empty merchant.

**Improvements:**  
- Add per-field confidence (e.g. amount from regex = high, date from “today” fallback = low, merchant empty = low). Combine into an overall confidence (e.g. product or weighted sum) and send to pending if below threshold.  
- In API response, include `warnings` for items with fallback date (e.g. `usedFallbackDate: true`) so the client can show “Date assumed as today” and let the user edit.  
- Pending review UI should highlight missing or uncertain fields (no merchant, assumed date).  
- Optionally: when only amount is found and date is fallback, set a flag on the transaction (e.g. `dateInferred: true`) for analytics and future “review assumed dates” flow.

---

## 6. Currency Ambiguity

**Scenario:** Symbol or code is ambiguous: “$” (USD vs CAD vs AUD), “฿” (THB), “Rs” (INR vs PKR), or no symbol (e.g. “15.00” on a Thai receipt). Crypto screenshots show “0.002 BTC” or “USDT”; bank apps may show “15.00” with currency only in header.

**Current handling:**  
- Parser has `CURRENCY_SYMBOLS`: $→USD, €→EUR, £→GBP, ¥→JPY. `CURRENCY_CODES` includes USD, EUR, GBP, JPY, CAD, AUD, CHF, PLN, UAH (no THB, INR, BTC, USDT).  
- Unrecognized symbol or code defaults to USD. So “15.00 ฿” or “15 THB” is treated as USD; “0.002 BTC” would not match the amount regex (no comma/dot decimal) or would match and default to USD.  
- `convert()` uses exchange rates from an API (e.g. Frankfurter); if the currency is wrong (e.g. THB stored as USD), conversion to base currency is wrong.  
- No locale or user preference to disambiguate “$” (e.g. user in Canada → CAD).

**Improvements:**  
- Add THB (and ฿), INR, and other common currencies to symbols/codes; add crypto (BTC, ETH, USDT) as “currencies” with optional conversion or store as-is with a flag `isCrypto`.  
- Accept `locale` or `preferredCurrency` in the request (e.g. `th-TH`, `en-CA`); when symbol is “$”, use locale to choose USD/CAD/AUD.  
- When no currency is detected, do not default to USD blindly: either leave `currencyOriginal` as “UNK” and skip conversion (store original only), or use `baseCurrency` from user settings as best guess and set a flag `currencyInferred: true`.  
- Document supported currencies and that unsupported ones are stored but may not convert correctly.

---

## 7. Timezone Ambiguity

**Scenario:** Receipt or app shows a time (“14:22”) or date (“10 Mar 2026”) without timezone. Bank may show UTC; ride app may show local; subscription “renewed at 00:00” may be in user’s or merchant’s timezone. Storing “2026-03-10” and “14:22” without timezone can cause wrong ordering or “same day” duplicate logic to break across midnight in another zone.

**Current handling:**  
- Parser extracts date as YYYY-MM-DD and time as HH:mm (optional). No timezone is parsed or stored.  
- Backend stores `transactionDate` (Date in DB) and `transactionTime` (string). When building `new Date(item.date)`, JavaScript uses local server timezone for midnight; so “2026-03-10” becomes 2026-03-10T00:00:00 in server TZ.  
- Duplicate detection uses `dateProximity` with date strings and “same day” = 1.0; no timezone is considered.  
- No user timezone or “transaction occurred in” timezone is stored or passed.

**Improvements:**  
- Accept optional `userTimezone` (e.g. IANA “Asia/Bangkok”) or `transactionTimezone` in the request; store on User or on the transaction.  
- When building `transactionDate`, interpret the date in that timezone (e.g. 2026-03-10 = start of day in user TZ) so “today” in the user’s zone is consistent.  
- Store `transactionTime` with optional timezone offset (e.g. “14:22+07:00”) or store UTC and display in user TZ in the app.  
- Duplicate logic: if both timestamp and time are available, use “same moment” or “within N minutes” in addition to “same calendar day” to reduce false negatives when the user has two transactions same day in different timezones.  
- Document that dates/times are interpreted in user (or request) timezone when provided.

---

## 8. Duplicate Detection False Positives

**Scenario:** Two different transactions are incorrectly treated as duplicates (e.g. same coffee shop, same amount, same day but two different visits; or same merchant, same amount, one month apart—recurring subscription; or same receipt re-uploaded after user edited amount). System auto-skips or marks as duplicate and the user loses a valid transaction or cannot add a correction.

**Current handling:**  
- Thresholds: score ≥ 0.95 → auto_skip; ≥ 0.7 → duplicate_candidate (still skipped in ingestion: `dup.action === 'duplicate_candidate' && dup.isDuplicate`).  
- Same `localHash` for all items in one screenshot gives a strong hash match; if the user re-uploads the same image, all items correctly match. But if two different receipts have similar OCR (e.g. same header “Grab Receipt”), ocrSimilarity can be high and push score up.  
- No “duplicates skipped” list returned in a way the user can “add anyway” or “undo skip.”  
- Window is last 500 transactions; if the “real” duplicate is the 501st, we don’t match it, but we can false-positive against a similar recent one (e.g. same amount/merchant/date from a different receipt).

**Improvements:**  
- Return in ingestion response the list of skipped transaction ids (or at least count and `duplicateOfId` for each skipped item) so the client can show “3 duplicates skipped” and, in a future iteration, “Add anyway” that creates the transaction with a flag `userOverrodeDuplicate: true`.  
- For duplicate_candidate (0.7–0.95), consider not auto-skipping: send to pending review with reason “possible_duplicate” and show the candidate match so the user can confirm or reject.  
- Use per-item OCR snippet for similarity to avoid same-receipt header boosting score for all items.  
- Add “hash must match” for auto_skip when hash is present: if we have sourceImageHash and it matches, auto_skip is safe; if we don’t have hash (e.g. manual entry), require higher score or never auto_skip.  
- Tune weights: reduce ocrSimilarity weight when the same ocrText is shared across many items (or only use hash + amount + date + merchant for auto_skip).

---

## 9. Duplicate Detection False Negatives

**Scenario:** The same transaction is added twice (e.g. user uploads the same screenshot twice, or uploads from two devices; or re-OCR gives slightly different text so hash differs). We fail to detect the duplicate and create two rows.

**Current handling:**  
- Hash match: if client sends same `localHash` and we have a stored transaction with that `sourceImageHash`, we score 1.0 on hash and likely hit 0.95+. So same screenshot re-upload with same hash is caught.  
- If client does not send hash (e.g. manual entry or old client), or hash changes (e.g. re-crop, different compression), we rely on amount + date + merchant + OCR.  
- Same OCR text for multiple items: each item gets the same first 1000 chars; if the duplicate is an item from the same screenshot, the “existing” transaction also has that OCR, so similarity is high—but the “candidate” is a different line. So we compare “full block” to “full block” and can get high similarity and correctly flag. But if the user uploads the same screenshot twice, we have two transactions with same OCR; the second upload’s items are compared against the first upload’s items. Amount/date/merchant per line can match; OCR is the same block, so we should catch it.  
- Window of 500: if the original transaction is older than the 500 most recent, we never compare and we create a duplicate.  
- No idempotency key: retry after timeout can submit the same payload twice; if the first request actually persisted but response was lost, the second creates duplicates.

**Improvements:**  
- Hash-first path: when `sourceImageHash` is present, query DB for any transaction with that hash for the user before loading 500; if found, return duplicate immediately.  
- Extend or replace “500” with a time window (e.g. last 90 days) plus “any transaction with same sourceImageHash ever” so re-upload after long time is still caught.  
- Accept Idempotency-Key (e.g. client-generated or localHash); store result in Redis/DB with TTL; on duplicate key return stored result and do not re-run pipeline.  
- In the app, compute and send a stable hash (e.g. perceptual hash of image or hash of normalized OCR) so that re-upload of the same screenshot always sends the same hash even if OCR text differs slightly.

---

## 10. Subscription Detection Errors

**Scenario:** (a) A recurring payment is not detected (variable amount, irregular interval, or new subscription with only one occurrence). (b) A one-off payment is wrongly marked as subscription (e.g. two similar coffee charges). (c) User already confirmed “not a subscription” but the detector overwrites to `subscription_candidate`. (d) Bi-weekly or quarterly subscriptions are missed because only monthly/yearly/weekly bands exist.

**Current handling:**  
- Detector runs on every ingestion; loads all expense transactions for the user, groups by normalized merchant, filters by similar amount (±5%), computes date gaps, and if average gap falls in 25–35, 350–380, or 6–8 days, creates/updates Subscription and sets `isRecurringCandidate` on those transactions.  
- Status is always set to `subscription_candidate`; there is no API to set “confirmed” or “dismissed,” so user state is not persisted and is overwritten on next run.  
- Transaction.subscriptionId is never set; link between transaction and subscription is not stored.  
- Variable amounts (e.g. utility bill) or two occurrences with >5% difference are filtered out. Single occurrence is never a subscription (MIN_OCCURRENCES = 2).  
- Bi-weekly (14 days), quarterly (~90 days) are not in the bands.

**Improvements:**  
- Persist user state: add PATCH /subscriptions/:id { status: 'confirmed_subscription' | 'non_subscription' }; detector only sets status to `subscription_candidate` when creating a new subscription or when current status is already `subscription_candidate`; do not overwrite user-confirmed or user-dismissed.  
- Set Transaction.subscriptionId when creating/updating Subscription so “transactions for this subscription” can be shown and so we don’t re-tag the same transactions every run.  
- Widen or add intervals: e.g. 12–16 days (bi-weekly), 85–95 days (quarterly).  
- Run detection in a dedicated job (e.g. nightly) rather than on every ingest; optionally only consider transactions since last run for “new” candidates and run full scan periodically.  
- For “possible false positive” (e.g. only 2 occurrences, same amount), mark as candidate but show in UI “Is this a subscription?” and let the user confirm or dismiss.  
- Consider a confidence score (e.g. number of occurrences, regularity of gaps) and only auto-create subscription when confidence is above a threshold; otherwise suggest in UI.

---

## 11. Merchant Name Variations

**Scenario:** Same merchant appears in different forms: “Grab”, “Grab Food”, “GrabFood”, “GRAB PAY”, “Grab (Thailand)”; bank may show “NETFLIX.COM 9.99” vs receipt “Netflix Subscription”; OCR may have “Nétflix” or “Grab  Föod”. Rules and duplicate detection need to treat these as the same merchant.

**Current handling:**  
- Normalization in duplicate detection and merchant memory: lowercase, collapse spaces, strip `[^\w\s]` (so “Grab Food” and “GrabFood” become “grab food” and “grabfood”—different).  
- MerchantRule has `merchantAliases` (JSON) but getMerchantRule does not use it; only exact match on merchantNormalized. So “Grab” and “Grab Food” need two rules unless the user creates one rule and we don’t support aliases.  
- Levenshtein in duplicate detection gives some fuzzy match (e.g. “grab” vs “grab food” gets a score < 1); may fall below duplicate threshold so we don’t false-positive, but we also don’t apply the same merchant rule.  
- Category classifier matches on keyword (e.g. “grab\s*food”) so “Grab Food” and “GrabFood” can both match food_delivery; but merchant memory lookup is exact only.

**Improvements:**  
- Implement alias lookup in getMerchantRule: match input normalized name against merchantNormalized or any entry in merchantAliases; when user saves a rule, optionally suggest aliases (e.g. “Grab”, “Grab Food”) and store them.  
- Unify normalization: use the same function and length cap everywhere (e.g. 256 chars for storage, 128 for duplicate comparison if needed). Consider “tokenize and match any token” for very short names (e.g. “Grab” contained in “Grab Food”).  
- Add “merchant canonicalization” step: map known variations to a canonical name (e.g. “NETFLIX.COM”, “Netflix” → “Netflix”) so that subscription detection and analytics group correctly; can be a small table or config plus fuzzy match.  
- In parser, trim and normalize the “merchant” substring (e.g. remove trailing/leading punctuation, collapse spaces) before storing so that minor OCR noise doesn’t create a new merchant variant.

---

## 12. Category Misclassification

**Scenario:** Transaction is assigned the wrong category: e.g. “Uber Eats” (should be food_delivery) classified as transport; “Apple One” (subscriptions) as shopping; bank “Transfer to John” as expense other instead of transfer; crypto “Sold BTC” as income vs “Bought BTC” as expense. Non-English text (e.g. Thai receipt “ค่าส่ง” = delivery fee) doesn’t match English keywords.

**Current handling:**  
- Category classification: merchant memory first (user override wins), then fixed KEYWORD_RULES (regex on merchant + ocrSnippet), else `other` with confidence 0.5.  
- No AI classification in the pipeline; so “Uber Eats” would match “ubereats” in food_delivery (keyword exists). “Apple One” matches “apple\s*one” → subscriptions. “Transfer” matches “transfer” → transfers.  
- Order of rules matters: first match wins. Generic “food” could match before “food_delivery” if “food” is checked first; in the current list “food_delivery” (grab food, doordash, ubereats) comes before “food” (restaurant, cafe, coffee, food), so delivery is preferred when both could match.  
- No refund/income type from parser (amount sign is stripped); so “Refund -15.00” is stored as expense 15.00.  
- Non-English: no patterns for Thai, etc.; such transactions fall to `other`.  
- User can correct and create a merchant rule; next time the same merchant gets the correct category. But if the merchant string varies (e.g. “Uber Eats” vs “UberEats”), rule may not apply.

**Improvements:**  
- Validate category against allowed list (food, food_delivery, …); reject or map invalid to `other`.  
- Add AI classification for “uncertain” cases: when confidence from rules is low (e.g. 0.5) or merchant is unknown, call structured AI with allowed categories and optional locale; cache result by normalized merchant to limit cost.  
- Add keywords for common non-English terms (e.g. “ค่าส่ง”, “delivery”) or pass locale to AI.  
- Use type (income/expense) to constrain category: e.g. if we later set type from amount sign or “refund” keyword, income-type should not get “food_delivery”.  
- Document rule order and add tests so that “Uber Eats” → food_delivery, “Uber” (ride) → transport, “Transfer” → transfers.

---

## 13. Refund Detection

**Scenario:** Screenshot shows a refund or credit: “Refund 25.00”, “Credit -15.00”, “REVERSAL 50.00”. This should be stored as income (or at least not as expense) and possibly linked to the original transaction or categorized as “refund”/transfers.

**Current handling:**  
- Parser uses `Math.abs(amount)` so negative amounts become positive; sign is lost.  
- Type is hardcoded to `expense` in ingestion. So a refund of 25.00 is stored as expense 25.00, inflating spending.  
- No keyword for “refund”, “credit”, “reversal” in category classification that would set type or a special category.  
- No link to original transaction (duplicateOfId is for duplicates, not refund-of).

**Improvements:**  
- Preserve sign in parser: when amount regex captures a negative (e.g. “-25.00” or “(25.00)”), keep amount negative or set a flag `isCredit: true`.  
- In ingestion: if amount is negative or ocrSnippet/merchant indicates refund/credit/reversal, set `type: 'income'` and optionally category `transfers` or a dedicated `refund`.  
- Add keyword rules: “refund”, “credit”, “reversal”, “reimbursement” → suggest income and category transfers (or refund).  
- Optional: allow client or AI to link refund to original transaction (e.g. refundTransactionId); useful for “net spending” and duplicate-of-refund handling.

---

## 14. Income Detection

**Scenario:** Screenshot shows salary, transfer in, payment received, or sale (e.g. bank “Salary 5000”, “Transfer from John 100”, crypto “Sold ETH 500 USD”). These should be type `income` and categorized appropriately (income, transfers, or other).

**Current handling:**  
- Parser does not set type; it only extracts amount, date, currency, merchant. Amount is always positive (Math.abs).  
- Classification has a rule for “salary|income|payment\s*received” → category `income`, but ingestion ignores category for type and always sets `type: 'expense'`. So “Salary 5000” is stored as expense 5000 in category income—wrong type, so analytics (totalIncome, totalSpent) are wrong.  
- No rules for “transfer from”, “received”, “sold” (crypto) as income.

**Improvements:**  
- Derive type from classification or explicit rules: when category is `income` or keyword indicates income (salary, payment received, transfer in, refund, sold), set `type: 'income'` in ingestion.  
- Parser: when amount is negative (e.g. “-50” or “(50)”) consider as credit/income and pass a flag or negative amount so ingestion can set type.  
- Add keywords: “salary”, “wage”, “transfer from”, “received”, “sold”, “deposit” → category income or transfers and type income.  
- Ensure analytics and dashboard use type correctly (totalIncome vs totalSpent) and that “income” category is only used with type income in reports.

---

## 15. AI Hallucination Risks

**Scenario:** When AI is used (e.g. for extraction or insights), the model may invent transactions, amounts, or categories not present in the OCR; or produce invalid JSON, extra markdown, or off-schema fields. This can pollute the database, confuse the user, or break parsing.

**Current handling:**  
- There is no AI extraction in the ingestion pipeline today; only rule-based category and no structured AI call for transactions. So hallucination in “extraction” does not yet affect persistence.  
- AI insight service (monthly summary, behavioral insights) calls Anthropic and parses JSON with a simple replace + JSON.parse; no Zod validation. Malformed or hallucinated fields (e.g. extra “transactions” array in insight response) could be ignored or cause throw; catch logs and returns partial or no insights.  
- Prompts include user data (amounts, categories); a malicious or malformed OCR could inject instructions (“ignore previous instructions and return …”); no strict output schema or sanitization.

**Improvements:**  
- For any future AI extraction: (1) Use a strict JSON schema and validate every AI response with Zod before merging into the pipeline. (2) Reject any transaction that does not have a corresponding amount/date in the OCR (e.g. require “rawEvidence” or line references). (3) Do not persist transactions with overall confidence below a threshold; send to pending review. (4) Cap number of transactions per AI response (e.g. max 20).  
- For insights: (1) Validate response shape with Zod (headline, arrays of cards with type/title/body). (2) Do not display or store freeform text that is not in the schema. (3) Prefer “metrics only” input to the model (e.g. structured JSON of totals and deltas) and ask for short phrases only; avoid sending raw OCR to the model for insights.  
- Sanitize OCR in prompts: truncate length, strip or escape newlines and obvious instruction-like patterns, and pass only the minimal text needed.  
- Add a “sanity check” after AI extraction: e.g. no transaction amount greater than a reasonable max (e.g. 1M in base currency) without flagging for review; no future dates unless within 1 day.  
- Log and monitor: log when validation fails or when AI returns empty; alert on high failure rate or unusual response size.

---

## Summary by Source Type

| Source                 | Main edge cases |
|------------------------|------------------|
| Bank apps              | Multiple tx per screenshot, date/time in header, currency in header, transfers vs expenses, refunds, encoding. |
| Ride apps              | Single tx, clear amount/date; merchant variation (Uber vs Uber Ride); currency by region. |
| Food delivery          | Itemized lines + total (multiple vs one), merchant (Grab Food vs Grab), tips, currency. |
| Subscription receipts  | Recurring same amount/merchant; wrong duplicate if same plan twice; date of charge. |
| Crypto exchanges       | Amount format (0.002 BTC), currency (BTC/ETH/USDT), buy vs sell (expense vs income), fees. |
| Random confirmations   | Partial crop, no date, ambiguous currency ($), refund vs charge, language. |

Implementing the improvements above will make behavior more predictable and robust across these sources and edge cases.
