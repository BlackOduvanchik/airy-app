# Airy — Performance Analysis

Analysis of screenshot processing, AI extraction, duplicate detection, analytics, and insights. Bottlenecks and improvements to keep the app feeling extremely fast.

---

## 1. Screenshot Processing Latency

### Current flow (sync path)

1. **Normalize OCR** — in-memory (NFKC, line trim). **~1–5 ms** for typical 2–10 KB text.
2. **Parse** — in-memory regex over lines. **~5–20 ms** for 20–100 lines.
3. **Per parsed item (sequential):**
   - `classifyCategory` → **getMerchantRule** (1 DB round-trip) + keyword match (CPU).
   - **getMerchantRule** again (redundant 2nd DB call).
   - **convert** → getRates (1 Redis GET or 1 HTTP to rates API) + math.
   - **checkDuplicate** → **findMany 500** (1 DB) + O(500) Levenshtein in memory.
   - **create** or **pending** (1 DB).
4. **After loop:** **refreshMonthlyAggregate** → getMonthlyAggregate (1 full-month findMany) + upsert; **detectSubscriptions** → findMany **all** user transactions.

### Latency breakdown (example: 3 transactions, same currency, cache hit)

| Step | Operations | Est. latency |
|------|------------|--------------|
| Normalize + parse | CPU only | ~10 ms |
| Item 1 | 2 DB (rule, dup) + 1 Redis (rates) + 1 DB (create) | ~15 + 2 + 15 + 10 = **~42 ms** |
| Item 2 | same | **~42 ms** |
| Item 3 | same | **~42 ms** |
| refreshMonthlyAggregate | 1 findMany (month) + 1 upsert | ~30–100 ms (depends on month size) |
| detectSubscriptions | 1 findMany (all user tx) | ~50–500+ ms (grows with user) |
| **Total** | | **~250–750 ms** (3 items, small user) |

With 5 items and a user who has 5k transactions: duplicate check stays 1×500, but **detectSubscriptions** loads 5k rows and does in-memory grouping → **~500 ms–2 s** just for that step. **refreshMonthlyAggregate** loads the whole month (e.g. 200 rows) → **~50–150 ms**.

### Bottlenecks

1. **Sequential per-item work:** N items ⇒ N × (2–3 DB + 1 Redis). No batching; network RTT dominates.
2. **Redundant getMerchantRule:** Called inside classifyCategory and again in ingestion; doubles DB calls for rules.
3. **Duplicate check:** One findMany(500) per item; same “recent 500” could be fetched once per screenshot and reused.
4. **Currency:** One getRates (Redis/HTTP) per item; same baseCurrency could be fetched once per request.
5. **Post-loop:** refreshMonthlyAggregate + detectSubscriptions run in the request path; detectSubscriptions is O(all user transactions) and blocks the response.
6. **No request timeout:** A large screenshot (many items) or a heavy user can hold the request for several seconds.

### Estimated latency (today)

| Scenario | Est. p50 | Est. p95 |
|----------|----------|----------|
| 1 item, new user, cache hit | ~150 ms | ~300 ms |
| 3 items, cache hit, small user | ~400 ms | ~800 ms |
| 5 items, user with 2k tx | ~1.5 s | ~3 s |
| 5 items, user with 10k tx | ~3 s | ~6 s+ |

---

## 2. AI Extraction Latency

### Current state

There is **no AI extraction in the pipeline** today; extraction is deterministic only. When added (e.g. for 0 parsed or low confidence):

- **One Anthropic call** per screenshot (or per “batch” of items): typically **~300–800 ms** network + model time for ~800 in / 400 out tokens.
- If invoked **per item** instead of per screenshot: N items ⇒ N × 400 ms ⇒ **2 s for 5 items**.

### Bottlenecks (when implemented)

1. **Blocking the request:** Running AI in the sync path adds 300–800 ms (or more) to every screenshot that needs it.
2. **No streaming / async:** User waits for full response; no “partial results” or background processing.
3. **No client-side timeout:** Long AI latency can feel like a hang if the app doesn’t show progress.

---

## 3. Duplicate Detection Latency

### Current implementation

- **One** `prisma.transaction.findMany({ where: userId, orderBy: transactionDate desc, take: 500 })` per candidate item.
- Then in-memory: for each of 500 rows, compute 5–6 similarity scores (amount, currency, merchant Levenshtein, date proximity, optional OCR Levenshtein).
- **Levenshtein** on two strings of length up to 128 (merchant) and 500 (OCR) is O(n×m); 500 × 128 ≈ 64k ops per candidate per row ⇒ **500 × 64k** for one candidate vs 500 rows ⇒ **~32M ops** in the worst case (all long strings). In practice, many merchants are short; still **~5–50 ms CPU** per candidate depending on data.
- **DB:** Single round-trip, ~10–30 ms for 500 rows (indexed by userId, transactionDate).
- **Total per item:** ~15–80 ms (DB + CPU). For 5 items: **5 × (15–80) = 75–400 ms** and **5 identical DB round-trips** (same 500 rows fetched 5 times).

### Bottlenecks

1. **Repeated findMany:** Same “recent 500” is fetched once per item; 5 items ⇒ 5× same query.
2. **No hash short-circuit:** If `sourceImageHash` is present, a single `findFirst({ where: { userId, sourceImageHash } })` could resolve duplicates in **~5 ms** without loading 500 rows or running similarity.
3. **OCR similarity on long text:** Levenshtein on 500 chars × 500 rows is expensive; using per-item snippet (e.g. rawLine) would shorten strings and reduce CPU.
4. **All work in request path:** Duplicate check is synchronous; every item waits for DB + CPU.

---

## 4. Analytics Computation Cost

### Current implementation

- **getMonthlyAggregate(userId, yearMonth):**  
  `findMany({ userId, transactionDate: { gte, lte }, isDuplicate: false })` over the whole month, then in-memory sum by type and by category.  
  **Cost:** 1 query returning all rows in the month (e.g. 50–500 rows); **~20–80 ms** for a typical user.

- **getDashboardData(userId):**  
  Calls **getMonthlyAggregate** for **this month** and **last month** → **2 full table scans** (by userId + date range).  
  **Cost:** 2 × (20–80 ms) = **~40–160 ms** plus small in-memory delta math.

- **getYearlyAggregate(userId, year):**  
  findMany over full year + subscription sum.  
  **Cost:** 1 large query (hundreds to thousands of rows) → **~50–300 ms** depending on volume.

- **refreshMonthlyAggregate:**  
  Calls getMonthlyAggregate (same heavy query) then upsert into MonthlyAggregate.  
  **Cost:** Same as one getMonthlyAggregate + 1 write; **~30–100 ms**.

- **Read path:** Dashboard and insights **do not read from MonthlyAggregate**; they always call getMonthlyAggregate/getDashboardData, so every dashboard or insight request pays the full scan cost.

### Bottlenecks

1. **Aggregates not used on read:** MonthlyAggregate/YearlyAggregate are written but never read; every dashboard/open is 2× full month scan.
2. **No Redis cache for dashboard:** getDashboardData is recomputed on every request; no short TTL cache.
3. **N+1 style:** getMonthlySummary calls getMonthlyAggregate twice (current + previous); getBehavioralInsights calls getDashboardData which itself calls getMonthlyAggregate twice.
4. **Large range scans:** For users with many transactions, monthly/yearly queries return large result sets and do more in-memory aggregation.

---

## 5. Insights Generation Latency

### Current implementation

**getMonthlySummary:**

1. getMonthlyAggregate(current month) — **~20–80 ms**
2. getMonthlyAggregate(previous month) — **~20–80 ms**
3. Anthropic call (summary sentence) — **~300–800 ms**
4. **Total (cache miss):** **~350–1000 ms**

**getBehavioralInsights:**

1. **redis.get(cacheKey)** — **~1–3 ms** (cache hit → return; **~2 ms**).
2. On miss: getDashboardData → 2× getMonthlyAggregate — **~40–160 ms**
3. Build deterministic cards (CPU) — **~1 ms**
4. Anthropic call — **~300–800 ms**
5. redis.setex — **~1–2 ms**
6. **Total (cache miss):** **~350–970 ms**

### Bottlenecks

1. **Two monthly aggregates per request:** Both summary and behavioral need current + previous month; no shared cache of “dashboard” or “monthly aggregates,” so repeated work.
2. **AI in critical path:** 300–800 ms block on every first view (or cache miss) for that user/month.
3. **Cache TTL 1 hour:** User who adds transactions and reopens Insights within the hour may see stale data unless cache is invalidated on write; if invalidated, every reopen pays full cost again.
4. **No “instant” shell:** API could return deterministic summary + placeholder for “AI summary” and stream or poll for the polished sentence so the screen paints in **&lt; 100 ms** and AI fills in later.

---

## 6. Bottleneck Summary

| Area | Main bottlenecks |
|------|-------------------|
| Screenshot processing | Sequential per-item DB/Redis; redundant getMerchantRule; duplicate check per item; refresh + detectSubscriptions in request path (detectSubscriptions = full user scan). |
| AI extraction | Not implemented; when added, will add 300–800 ms if done synchronously. |
| Duplicate detection | Same findMany(500) repeated per item; no hash-first path; heavy Levenshtein. |
| Analytics | Aggregates not read; dashboard always scans Transaction twice; no dashboard cache. |
| Insights | 2× getMonthlyAggregate + 1 AI call per request on cache miss; no instant shell. |

---

## 7. Improvements to Keep the App Feeling Extremely Fast

### Screenshot processing

1. **Batch DB/Redis per screenshot**  
   - Fetch “recent transactions” for duplicate check **once** per request; pass the list into a **batch** duplicate check that returns one result per item.  
   - Fetch **getMerchantRule** for all distinct merchants in the batch in **one** query (e.g. `where merchantNormalized in [...]`).  
   - Fetch **getRates(baseCurrency)** once per request (same baseCurrency for all items).  
   **Effect:** Cut 2–3× (N−1) round-trips for N items; e.g. 5 items from ~15 to ~5–6.

2. **Remove redundant getMerchantRule**  
   - classifyCategory already calls getMerchantRule; use its result in ingestion and do not call getMerchantRule again.  
   **Effect:** 1 fewer DB call per item.

3. **Move refresh + detectSubscriptions off the request path**  
   - After persisting transactions, **enqueue a job** (e.g. “refresh-aggregates”, “detect-subscriptions”) with userId and yearMonth.  
   - Return 200 immediately after writes; worker runs refresh and detectSubscriptions in the background.  
   **Effect:** Response time no longer includes 50–500+ ms (or more) for detectSubscriptions; user sees “saved” in **&lt; 500 ms** for typical 3–5 items.

4. **Default to async ingestion for multi-item screenshots**  
   - If parsed items &gt; 2 (or 3), return **202** with a job id and process in worker; client polls or uses push for “processing complete.”  
   - Sync path only for 1–2 items so single-receipt uploads feel instant.  
   **Effect:** Heavy screenshots don’t block the UI; perceived latency for single receipts stays low.

5. **Set request timeout**  
   - e.g. 15–30 s for POST parse-screenshot; return 408 or 503 on timeout and ask user to retry or use async.  
   **Effect:** Prevents very long hangs and encourages async for large payloads.

### AI extraction (when added)

6. **Use only when necessary**  
   - Call AI only when parser returns 0 transactions or confidence is below threshold; use deterministic path first.  
   **Effect:** Most screenshots avoid AI latency entirely.

7. **Prefer async for AI extraction**  
   - For screenshots that need AI, enqueue job and return 202; client shows “Analyzing…” and polls or gets push when done.  
   **Effect:** Sync path stays under ~500 ms; AI adds no latency to the initial response.

8. **Optional: streaming or “partial results”**  
   - If API supports it, return deterministic transactions immediately and stream or add AI-refined fields in a follow-up response.  
   **Effect:** User sees something in &lt; 200 ms; refinements appear when ready.

### Duplicate detection

9. **Hash-first fast path**  
   - If `sourceImageHash` is present, run `findFirst({ where: { userId, sourceImageHash } })`. If found, return duplicate immediately; skip loading 500 and similarity loop.  
   **Effect:** Most re-uploads and many duplicates resolve in **~5–15 ms** instead of 50–80 ms.

10. **Single fetch of “recent” per request**  
    - Load “recent 500” (or time-bounded window) once per screenshot; run duplicate scoring for all items against that list in memory.  
    **Effect:** 1 DB round-trip instead of N; saves ~10–30 ms × (N−1) and reduces DB load.

11. **Cap OCR length for similarity**  
    - Use `rawLine` or first 100–200 chars of OCR for textSimilarity instead of 500 chars; or skip OCR similarity when hash is present.  
    **Effect:** Less CPU per candidate; lower p95 latency for duplicate check.

### Analytics

12. **Read from MonthlyAggregate when available**  
    - getMonthlyAggregate: first try **MonthlyAggregate** for (userId, yearMonth). If row exists and is “fresh” (e.g. updated in last few minutes or not stale), return it. Otherwise compute from Transaction and optionally refresh the row.  
    **Effect:** Dashboard and insights pay 1 indexed read (~5 ms) instead of full month scan (~30–80 ms) for past months and recently refreshed current month.

13. **Cache getDashboardData in Redis**  
    - Key e.g. `dashboard:${userId}`, TTL 2–5 min. On cache hit return immediately; on miss compute and set. Invalidate on new transaction (or rely on TTL).  
    **Effect:** Repeat opens of dashboard in same 2–5 min are **~2–5 ms** (Redis) instead of 40–160 ms.

14. **Precompute on write (already partially there)**  
    - Keep refreshMonthlyAggregate in a post-write job; ensure worker runs and MonthlyAggregate is updated so that next read can use it.  
    **Effect:** Current month also benefits from aggregate table after first ingestion of the day.

### Insights

15. **Return deterministic shell first**  
    - getMonthlySummary: return immediately with `summary` (deterministic sentence), `details`, `deltaPercent`; if AI is enabled, optionally trigger async job to “polish” summary and cache it for next request.  
    - getBehavioralInsights: return deterministic cards (trend, top category) immediately; trigger async for extra AI cards and merge into cache.  
    **Effect:** First paint in **&lt; 100 ms**; AI improves copy in background or on next load.

16. **Cache monthly aggregates for insight request**  
    - When generating insights, call getDashboardData once (or use dashboard cache); reuse for both summary and behavioral so we don’t run 2× getMonthlyAggregate again.  
    **Effect:** One aggregate fetch per insight request instead of two.

17. **Longer or smarter cache for insights**  
    - Cache insights per user+month with invalidation when new transactions are added (or TTL 24h).  
    **Effect:** Repeat views and same-day revisits are instant (Redis hit).

### General

18. **Add latency budgets and monitoring**  
    - Log duration for: normalize+parse, per-item pipeline, duplicate check, refresh, detectSubscriptions, aggregate reads, AI calls.  
    - Set targets (e.g. p95 parse-screenshot &lt; 800 ms for ≤3 items) and alert when exceeded.  
    **Effect:** Prevents regressions and focuses optimization on the slowest stages.

19. **Connection pooling and DB tuning**  
    - Ensure Prisma connection pool size is adequate for concurrent requests; consider read replicas for getMonthlyAggregate/getDashboardData if DB becomes the bottleneck.  
    **Effect:** Reduces queueing and tail latency under load.

---

## 8. Expected Latency After Improvements

| Scenario | Today (est. p95) | After improvements (target) |
|----------|-------------------|-----------------------------|
| 1 item, new user | ~300 ms | **~150 ms** (batch + hash path + no post-loop in path) |
| 3 items, cache hit | ~800 ms | **~250 ms** (batch, single dup fetch, rates once, job for refresh/detect) |
| 5 items, heavy user | ~3–6 s | **~400 ms** (same + async for refresh/detect) |
| Dashboard load | ~160 ms | **~10 ms** (aggregate table + Redis cache) |
| Insights (cache miss) | ~1000 ms | **~100 ms** (deterministic shell) + AI in background |
| Insights (cache hit) | ~2 ms | **~2 ms** (unchanged) |

Implementing batching, hash-first duplicate check, moving refresh and detectSubscriptions to a job, reading from aggregates and caching the dashboard, and returning an instant deterministic shell for insights will keep the app feeling extremely fast while preserving product quality.
