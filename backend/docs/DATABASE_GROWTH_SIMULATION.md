# Airy — Database Growth Simulation

**Assumptions:** 100,000 users; 500 transactions per user on average (50M transactions total).  
Covers table growth, index strategy, query performance, analytics cost, and schema optimizations.

---

## 1. Table Growth

### Row counts

| Table | Rows | Notes |
|-------|------|--------|
| **User** | 100,000 | 1 per user |
| **Transaction** | **50,000,000** | 100k × 500 |
| **PendingTransaction** | ~50,000 | Assume 0.1% of tx in pending at any time; or 1 per user at peak |
| **MerchantRule** | ~2,000,000 | ~20 rules per user |
| **Subscription** | ~500,000 | ~5 subscriptions per user |
| **MonthlyAggregate** | ~1,200,000 | 100k × 12 months (rolling) |
| **YearlyAggregate** | ~200,000 | 100k × 2 years (rolling) |
| **AiUsageLog** | ~1,200,000+ | Append-only; 100k × 12 months × 1+ row/month |

### Estimated row sizes (PostgreSQL)

- **Transaction:** id (25) + userId (25) + type (8) + amountOriginal (8) + currencyOriginal (6) + amountBase (8) + baseCurrency (6) + merchant (257) + title (513) + transactionDate (8) + transactionTime (11) + category (65) + subcategory (65) + booleans (2) + subscriptionId (25) + comment (TOAST, ~100 avg) + sourceType (33) + sourceImageHash (129) + ocrText (TOAST, ~500 avg) + confidence (8) + duplicateOfId (25) + createdAt/updatedAt (16) + null bitmap + alignment. **~600–800 bytes/row** in main table (TOAST for comment/ocrText). Use **~700 bytes** for estimate.
- **User:** ~150 bytes/row  
- **MerchantRule:** ~400 bytes/row  
- **Subscription:** ~200 bytes/row  
- **MonthlyAggregate:** ~300 bytes/row (byCategory Json variable)  
- **YearlyAggregate:** ~250 bytes/row  
- **PendingTransaction:** ~500 bytes/row (payload Json)  
- **AiUsageLog:** ~100 bytes/row  

### Table and index size (approximate)

| Table | Rows | Row size | Table size | Index size (est.) | Total |
|-------|------|----------|------------|-------------------|--------|
| Transaction | 50M | 700 B | **~35 GB** | **~8 GB** | **~43 GB** |
| User | 100k | 150 B | ~15 MB | ~5 MB | ~20 MB |
| MerchantRule | 2M | 400 B | ~800 MB | ~150 MB | ~950 MB |
| Subscription | 500k | 200 B | ~100 MB | ~30 MB | ~130 MB |
| MonthlyAggregate | 1.2M | 300 B | ~360 MB | ~40 MB | ~400 MB |
| YearlyAggregate | 200k | 250 B | ~50 MB | ~15 MB | ~65 MB |
| PendingTransaction | 50k | 500 B | ~25 MB | ~5 MB | ~30 MB |
| AiUsageLog | 1.2M | 100 B | ~120 MB | ~20 MB | ~140 MB |
| **Total** | | | **~37 GB** | **~8.3 GB** | **~45 GB** |

**Transaction** dominates. Index estimates for Transaction (50M rows):

- `(userId, transactionDate)`: 50M × (25 + 8) ≈ **1.6 GB**
- `(userId, sourceImageHash)`: similar, **~1.6 GB**
- `(userId, merchant)`: **~1.6 GB**
- `(userId, category)`: **~1.6 GB**
- Primary key: **~1.2 GB**
- Total index **~8 GB** is in line with the above.

---

## 2. Index Strategy

### Current indexes (from schema)

**Transaction**

- `@@index([userId, transactionDate])`
- `@@index([userId, sourceImageHash])`
- `@@index([userId, merchant])`
- `@@index([userId, category])`

**Other tables**

- MerchantRule: `@@unique([userId, merchantNormalized])`, `@@index([userId])`
- Subscription: `@@unique([userId, merchant])`, `@@index([userId])`
- MonthlyAggregate: `@@unique([userId, yearMonth])`, `@@index([userId])`
- YearlyAggregate: `@@unique([userId, year])`, `@@index([userId])`
- PendingTransaction: `@@index([userId])`
- AiUsageLog: `@@index([userId, month])`

### Query vs index usage

| Query | Filter / order | Index used | Rows touched |
|-------|-----------------|------------|-------------|
| getMonthlyAggregate | userId, transactionDate ∈ [start,end], isDuplicate=false | (userId, transactionDate) | ~40–50 per user per month |
| getYearlyAggregate | userId, transactionDate ∈ [year] | (userId, transactionDate) | ~500 per user |
| checkDuplicate | userId, orderBy transactionDate desc, take 500 | (userId, transactionDate) | 500 |
| detectSubscriptions | userId, type=expense, orderBy transactionDate asc | (userId, transactionDate) or full userId scan | **500** (all user tx) |
| GET /transactions (list) | userId, optional month/year, orderBy transactionDate desc, take 200 | (userId, transactionDate) | 200 |
| Export | userId, optional date range, orderBy transactionDate desc, **no limit** | (userId, transactionDate) | **up to 500** |
| findFirst by id, userId | id, userId | Primary key | 1 |
| MerchantRule lookup | userId, merchantNormalized | unique (userId, merchantNormalized) | 1 |

**Gaps**

1. **isDuplicate** is not in any index. getMonthlyAggregate and getYearlyAggregate filter `isDuplicate: false` after index seek; Postgres can use (userId, transactionDate) and then filter isDuplicate, which is acceptable but a **covering index (userId, transactionDate) WHERE isDuplicate = false** would be better for analytics.
2. **detectSubscriptions** filters `type: 'expense'` but there is no (userId, type) index; (userId, transactionDate) still narrows to one user, then type filter in memory. For 500 rows per user this is fine; for 5k+ an index (userId, type, transactionDate) could help.
3. **Export** has no `take`; with 500 tx/user it returns 500 rows per request; with 5k tx/user it would return 5k rows (memory and response size risk).

---

## 3. Query Performance (50M Transaction rows)

### Duplicate check

- **Query:** findMany where userId, orderBy transactionDate desc, take 500, select 6 columns.
- **Index:** (userId, transactionDate) — index scan on userId, then read 500 rows in descending date order. **~10–25 ms** at 50M rows (index is selective per userId; 500 rows is small).
- **Verdict:** Good; main cost is application-side Levenshtein, not DB.

### getMonthlyAggregate

- **Query:** findMany where userId, transactionDate gte/lte (one month), isDuplicate = false.
- **Index:** (userId, transactionDate). Range scan for one user over ~30 days; then filter isDuplicate. **~40–50 rows** per user per month.
- **Estimate:** Index range scan + heap fetch for ~50 rows. **~15–40 ms** per call at 50M rows (depends on buffer cache).
- **Verdict:** Acceptable; 2× per dashboard (this + last month) ⇒ **~30–80 ms** for getDashboardData.

### getYearlyAggregate

- **Query:** findMany where userId, transactionDate in [Jan 1 – Dec 31], isDuplicate = false.
- **Index:** (userId, transactionDate). Range scan for one user over 365 days; **~500 rows**.
- **Estimate:** **~50–150 ms** per call (500 rows fetch + in-memory aggregation).
- **Verdict:** Heavier than monthly; should be served from YearlyAggregate when possible.

### detectSubscriptions

- **Query:** findMany where userId, type = 'expense', orderBy transactionDate asc, **no limit**.
- **Index:** (userId, transactionDate). Full scan of all rows for that userId (500 rows); type filter in memory. **~20–60 ms** for 500 rows.
- **Verdict:** OK at 500 tx/user; at 5k+ tx/user would become **~100–300 ms** and high memory.

### GET /transactions (list by month)

- **Query:** findMany where userId, transactionDate in range, orderBy transactionDate desc, take 200.
- **Index:** (userId, transactionDate). **~5–20 ms** (200 rows).

### Export (no limit)

- **Query:** findMany where userId (and optional date range), orderBy transactionDate desc, **no take**.
- **Rows returned:** Up to 500 per user (or all in date range). **~30–80 ms** for 500 rows; memory and response size scale with row count.
- **Verdict:** Add pagination or cap (e.g. take 5000) to avoid OOM and timeouts for heavy users.

### refreshMonthlyAggregate

- **Query:** Same as getMonthlyAggregate (full month scan) + one upsert on MonthlyAggregate. **~20–50 ms** for the findMany + **~2–5 ms** upsert.

---

## 4. Analytics Query Cost (Summary)

| Operation | Frequency (example) | Rows read | Est. latency (50M tx) |
|-----------|---------------------|-----------|-------------------------|
| getMonthlyAggregate | 2× per dashboard load, 2× per insight request | ~50 × 2 | 30–80 ms |
| getYearlyAggregate | 1× per yearly view | ~500 | 50–150 ms |
| getDashboardData | 1× per dashboard open | ~100 (2 months) | 40–160 ms |
| refreshMonthlyAggregate | 1× per ingestion (or job) | ~50 + 1 write | 25–60 ms |
| detectSubscriptions | 1× per ingestion (or job) | 500 | 20–60 ms |
| checkDuplicate | N× per screenshot (N items) | 500 × N | 15–25 ms × N (DB only) |

**Total analytics “cost” per dashboard open:** 2 × getMonthlyAggregate ⇒ **~40–160 ms** today, with no use of MonthlyAggregate table on read path. If we **read from MonthlyAggregate** when available: 1–2 indexed lookups ⇒ **~2–10 ms**.

---

## 5. Schema Optimizations

### 5.1 Use aggregates on read

- **Change:** getMonthlyAggregate and getYearlyAggregate should **read from MonthlyAggregate / YearlyAggregate** when a row exists for (userId, yearMonth/year), and only fall back to scanning Transaction when the aggregate is missing or stale (e.g. current month).
- **Effect:** Dashboard and most insight requests become 1–2 small lookups (**~2–10 ms**) instead of scanning 50–500 Transaction rows. Big win at 50M rows.

### 5.2 Covering index for analytics (optional)

- **Change:** Add a **partial index** for analytics that only index non-duplicate transactions and include columns needed for aggregation:
  - `CREATE INDEX CONCURRENTLY idx_transaction_user_date_dup_type_amount ON "Transaction" ("userId", "transactionDate") INCLUDE (type, amountBase, category) WHERE "isDuplicate" = false;`
- **Effect:** getMonthlyAggregate / getYearlyAggregate can be index-only for that filter; fewer heap fetches. Smaller gain than using precomputed aggregates.

### 5.3 Partition Transaction by time

- **Change:** Partition `Transaction` by `transactionDate` (e.g. by month or quarter). Example: `Transaction_2025_01`, `Transaction_2025_02`, …
- **Effect:** Monthly and yearly queries only touch relevant partitions; delete/archive of old data is drop partition; vacuum and index size per partition stay smaller. **Recommended once table is ~50 GB+ or when retention/archival is required.**
- **Note:** Prisma does not manage partitioning; use raw SQL migrations. Application queries unchanged if partition key is in the predicate.

### 5.4 Cap and paginate export

- **Change:** In export service, add `take: 5000` (or 10k) and support cursor/offset or `skip` so clients can page. Reject or cap date range (e.g. max 1 year) for export.
- **Effect:** Bounded memory and response size; predictable latency; no full-table export for a user with 50k tx.

### 5.5 Index for subscription detection (optional)

- **Change:** Add `@@index([userId, type, transactionDate])` so detectSubscriptions can use an index that includes `type = 'expense'`.
- **Effect:** Slightly more efficient scan for “all expenses by user by date” at very high tx count per user (e.g. 5k+). Marginal at 500 tx/user.

### 5.6 Reduce stored OCR size

- **Change:** Store only first 500–1000 characters of `ocrText` (or move to object storage with TTL). Already truncating to 2000 in ingestion; consider 1000 for long-term.
- **Effect:** Lower table and TOAST size; smaller backups; duplicate check already uses a short snippet. Saves ~20–30% on Transaction row size if OCR is large.

### 5.7 AiUsageLog retention and partitioning

- **Change:** Partition AiUsageLog by month or trim old rows (e.g. keep 24 months). Optionally aggregate by (userId, month, feature) and delete raw rows older than 90 days.
- **Effect:** Prevents unbounded growth; keeps table and index small for analytics on recent usage.

### 5.8 Consider (userId, transactionDate) as primary sort everywhere

- **Current:** All main Transaction access is by userId and optionally transactionDate range. Existing (userId, transactionDate) index is the right one.
- **Recommendation:** Keep it; ensure no query does a full table scan (e.g. avoid “all transactions” without userId). Export and list already filter by userId.

---

## 6. Recommended Index Summary (no schema change required)

Existing indexes are sufficient for 50M rows if:

1. **Read path uses MonthlyAggregate / YearlyAggregate** so Transaction is not scanned for every dashboard/insight.
2. **Export is paginated or capped** so we never read 10k+ rows in one query.
3. **detectSubscriptions** stays per-user and is run in a job; at 500 tx/user it is acceptable.

Optional additions:

- **Partial covering index** for Transaction (userId, transactionDate) WHERE isDuplicate = false, INCLUDE (type, amountBase, category) for analytics if you keep scanning Transaction in some paths.
- **Partitioning** by transactionDate when you need retention policy or when Transaction table exceeds ~50 GB.

---

## 7. Growth Projection (2–3 years)

If users stay at 100k but transactions grow by ~40/month per user:

- **1 year:** 100k × 500 = 50M tx (~45 GB total DB).
- **2 years:** 100k × 980 ≈ 98M tx (~90 GB); **3 years:** ~150M tx (~135 GB).

Without partitioning or archival, the Transaction table and its indexes grow linearly. Recommendation:

- **Year 1:** Rely on current indexes + aggregate read path + export cap.
- **Year 2:** Introduce partitioning by transactionDate (e.g. monthly) and/or move old Transaction rows to cold storage and keep only aggregates for old periods.
- **Ongoing:** Monitor slow-query log and index usage; add partial/covering index only if analytics still scan Transaction after switching to aggregates.

---

## 8. Summary Table

| Aspect | At 50M Transaction rows | Recommendation |
|--------|--------------------------|-----------------|
| **Table growth** | ~45 GB total; Transaction ~43 GB | Plan partitioning/archival by year 2 |
| **Index strategy** | (userId, transactionDate) is critical; current set is adequate | Add partial index only if needed after aggregate read path |
| **Query performance** | getMonthly 15–40 ms; getYearly 50–150 ms; duplicate 10–25 ms | Use Monthly/YearlyAggregate on read ⇒ &lt;10 ms |
| **Analytics cost** | 2× full month scan per dashboard (40–160 ms) | Read from aggregates + Redis cache ⇒ 2–10 ms |
| **Schema optimizations** | — | Use aggregates on read; cap/paginate export; partition in year 2; trim OCR; AiUsageLog retention |

Implementing the aggregate read path and export cap gives the largest benefit for analytics and stability at 100k users and 500 tx/user; partitioning and retention keep growth under control as data doubles or triples.
