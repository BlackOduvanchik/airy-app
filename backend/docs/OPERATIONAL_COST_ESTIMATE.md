# Airy — Operational Cost Estimate at Scale

**Assumptions:**  
- 10k, 50k, 100k monthly active users  
- 20 screenshots uploaded per user per month  
- Pricing references: Anthropic (Claude Sonnet ~$3/MTok in, $15/MTok out; Haiku ~$0.80/MTok in, $4/MTok out), AWS list prices (us-east-1 style), generic cloud DB/cache.  
- All figures are **monthly** in USD unless noted. Verify with current vendor pricing before budgeting.

---

## 1. Volume Summary

| Users | Screenshots/month | API requests (approx) |
|-------|-------------------|------------------------|
| 10k   | 200,000           | ~250k (screenshot + list/dashboard) |
| 50k   | 1,000,000         | ~1.25M                 |
| 100k  | 2,000,000         | ~2.5M                  |

---

## 2. AI Extraction

**Assumption:** AI extraction is used when deterministic parser returns 0 transactions or low-confidence / multi-transaction cases. **20% of screenshots** trigger one AI call each (80% handled by parser only).

- **Calls/month:** 10k → 40k | 50k → 200k | 100k → 400k  
- **Per call (Claude Sonnet):** ~800 input tokens (system + OCR snippet), ~400 output (structured JSON).  
  - Input: 800 × $3/1M = $0.0024  
  - Output: 400 × $15/1M = $0.006  
  - **≈ $0.0084/call**  
- **Monthly cost (Sonnet):**

| Users | AI extraction calls | Cost (Sonnet) |
|-------|---------------------|---------------|
| 10k   | 40,000              | **~$336**     |
| 50k   | 200,000             | **~$1,680**   |
| 100k  | 400,000             | **~$3,360**   |

**If using Claude Haiku for extraction:** ~$0.0022/call → 10k: ~$88, 50k: ~$440, 100k: ~$880.

---

## 3. AI Insights Generation

**Assumption:** 2 AI calls per user per month (monthly summary + behavioral insights). Cache (e.g. 1h TTL) avoids repeat calls for same user/month within the hour; **2 calls/user/month** is used for first view or cache miss.

- **Calls/month:** 10k → 20k | 50k → 100k | 100k → 200k  
- **Monthly summary:** ~250 input, ~60 output → ~$0.00135/call  
- **Behavioral insights:** ~400 input, ~150 output → ~$0.0042/call  
- **Combined average:** ~$0.0028/call × 2 = **~$0.0056/user/month**  
- **Monthly cost:**

| Users | Insight calls | Cost (Sonnet) |
|-------|----------------|---------------|
| 10k   | 20,000         | **~$112**     |
| 50k   | 100,000        | **~$560**     |
| 100k  | 200,000        | **~$1,120**   |

---

## 4. Backend Compute

**Assumption:** API + workers (Node/Fastify + BullMQ). Bursty load: assume peak ~3× average request rate. One small container (0.25 vCPU, 512MB) ≈ 20–30 RPS; scale for peak.

- **10k users:** ~8 req/min avg, ~25/min peak → 2 API tasks + 1 worker ≈ 3 tasks. **~$75–100/month** (e.g. Fargate 0.25 vCPU, 0.5 GB).  
- **50k users:** ~40 req/min avg → 4–5 API + 2 workers ≈ 6–7 tasks. **~$200–280.**  
- **100k users:** ~80 req/min avg → 8–10 API + 3–4 workers ≈ 12 tasks. **~$400–500.**

| Users | Est. tasks | Cost (approx) |
|-------|------------|---------------|
| 10k   | 3          | **~$90**      |
| 50k   | 7          | **~$240**     |
| 100k  | 12         | **~$450**     |

---

## 5. Database (Postgres)

**Assumption:** RDS or managed Postgres. ~3 transactions stored per screenshot (parser can return multiple), plus manual entries. Growth: ~60 rows/user/month → 10k: 600k rows/month, 100k: 6M rows/month. After 12 months: 10k → ~7M rows, 100k → ~72M rows. ~500 bytes/row → 10k: ~3.5 GB, 100k: ~36 GB (year 1).

- **10k:** db.t3.small or 1 vCPU managed → **~$40–50/month**  
- **50k:** 2 vCPU, more storage → **~$120–150/month**  
- **100k:** 2–4 vCPU, 50+ GB → **~$200–280/month**

| Users | Est. DB cost |
|-------|--------------|
| 10k   | **~$45**     |
| 50k   | **~$135**    |
| 100k  | **~$240**    |

---

## 6. Storage

**Assumption:**  
- **DB storage:** Included in DB section above.  
- **Redis:** Cache (rates, insights, entitlements) + queues. ~100–200 bytes per key. 10k users: ~500k keys → ~100 MB; 100k: ~5M keys → ~1 GB.  
- **Object storage:** $0 if OCR-only (no image upload). If optional image fallback (e.g. 5% of screenshots, 500 KB): 10k → ~0.5 GB, 100k → ~5 GB → **~$0.15–1.50/month** (S3).

- **Redis (ElastiCache / managed):** 10k: cache.small → **~$15–25**; 50k: **~$35–50**; 100k: **~$50–75.**  
- **Object storage:** **~$0** (OCR-only) or **~$1–5** (optional images).

| Users | Redis      | Object storage | Total storage |
|-------|------------|----------------|---------------|
| 10k   | ~$20       | ~$0            | **~$20**      |
| 50k   | ~$40       | ~$0            | **~$40**      |
| 100k  | ~$65       | ~$2            | **~$67**      |

---

## 7. Bandwidth

**Assumption:**  
- Inbound: OCR payload ~4 KB average (max 50 KB); response ~1–2 KB.  
- 10k: 200k × 4 KB ≈ 800 MB in, 400 MB out ≈ 1.2 GB total.  
- 100k: 2M × 4 KB ≈ 8 GB in, 4 GB out ≈ 12 GB total.  
- Many clouds include 10–100 GB egress; estimate **$0–20/month** at 100k if over free tier.

| Users | Est. data transfer | Cost      |
|-------|--------------------|-----------|
| 10k   | ~1.5 GB            | **~$0**   |
| 50k   | ~6 GB              | **~$0**   |
| 100k  | ~12 GB             | **~$0–15**|

---

## 8. Total Monthly Cost Summary

| Cost category      | 10k users | 50k users | 100k users |
|--------------------|-----------|-----------|------------|
| AI extraction      | $336      | $1,680    | $3,360     |
| AI insights        | $112      | $560      | $1,120     |
| Backend compute    | $90       | $240      | $450       |
| Database           | $45       | $135      | $240       |
| Storage (Redis etc)| $20       | $40       | $67        |
| Bandwidth          | $0        | $0        | $10        |
| **Total**          | **~$613** | **~$2,655**| **~$5,247**|

**Per user per month (approx):** 10k → **~$0.061** | 50k → **~$0.053** | 100k → **~$0.052**.  
AI (extraction + insights) is **~73%** of total at each scale.

---

## 9. Optimizations to Reduce Cost (Preserving Quality)

### AI extraction

1. **Use a smaller/cheaper model for extraction**  
   - Use **Claude Haiku** for extraction (structured, factual task): ~$0.0022/call vs ~$0.0084 (Sonnet).  
   - **Saving:** ~74% on extraction → 100k: ~$880 vs $3,360 (**~$2,480/month**).

2. **Reduce % of screenshots that call AI**  
   - Improve deterministic parser (more formats, locales) so only **~10%** of screenshots need AI (e.g. 0 parsed or ambiguous).  
   - 100k: 200k calls instead of 400k → **~$1,680** (Sonnet) or **~$440** (Haiku).

3. **Cache extraction by OCR hash**  
   - Same OCR text (e.g. re-upload) → return cached extraction; store in Redis with TTL (e.g. 7 days).  
   - Cuts duplicate uploads and re-processing; saving scales with repeat uploads.

4. **Batch API / async**  
   - Use Anthropic Batch API for non-real-time extraction (e.g. async path); often discounted.  
   - Trade-off: user sees “processing” instead of immediate result.

### AI insights

5. **Cache aggressively**  
   - Cache insights per user/month (e.g. 24h or until new transactions). Already partially in place; ensure all insight endpoints use cache and invalidate only on new data.  
   - Reduces repeat calls when user opens Insights multiple times.

6. **Use Haiku for insights**  
   - Behavioral insights and short summary can be done with Haiku; test quality.  
   - ~$0.001/call vs ~$0.0028 → **~$200k → ~$200** at 100k vs ~$1,120 (**~$920/month**).

7. **Deterministic-first summary**  
   - Always return a deterministic summary (e.g. “You spent X% more than last month”); call AI only to “polish” one sentence and cache result.  
   - Reduces AI calls on cache miss or allows fallback when AI fails.

### Backend compute

8. **Right-size and scale to zero where possible**  
   - Use scale-to-zero (e.g. Lambda, Cloud Run) for low traffic or dev; fixed tasks for production.  
   - Tune CPU/memory from real usage; avoid over-provisioning.

9. **Separate API and workers**  
   - Scale API for request rate and workers for queue depth; avoid over-scaling both together.  
   - Use spot/preemptible for workers if acceptable for your SLA.

### Database

10. **Use aggregates for reads**  
    - Serve dashboard and analytics from **MonthlyAggregate / YearlyAggregate** (and Redis cache) instead of scanning Transaction every time.  
    - Lowers DB load and can allow smaller instance or better throughput.

11. **Retention and archival**  
    - Move old Transaction rows to cold storage or aggregate-only after e.g. 2 years; keep recent data hot.  
    - Reduces primary DB size and backup cost.

### Storage and bandwidth

12. **Cap and compress OCR in storage**  
    - Store only first N characters of ocrText (e.g. 2k) for display/debug; avoid storing 50k chars per screenshot.  
    - Reduces DB size and backup cost.

13. **Redis eviction and TTL**  
    - Set maxmemory and eviction policy (e.g. volatile-lru); ensure all keys have TTL.  
    - Prevents unbounded growth and controls Redis cost.

---

## 10. Optimized Cost Snapshot (Rough)

Applying **Haiku for extraction + 10% AI extraction rate + Haiku for insights + cache** (without changing product quality materially):

| Cost category      | 100k (original) | 100k (optimized) |
|--------------------|------------------|-------------------|
| AI extraction      | $3,360           | ~$440 (Haiku, 10%)|
| AI insights        | $1,120           | ~$200 (Haiku + cache) |
| Backend compute    | $450             | $450 (unchanged)  |
| Database           | $240             | $240 (unchanged)  |
| Storage            | $67              | $67 (unchanged)   |
| Bandwidth          | $10              | $10 (unchanged)   |
| **Total**         | **~$5,247**      | **~$1,407**       |

**Rough saving at 100k: ~$3,840/month (~73%)** with quality preserved by (1) Haiku for structured extraction/insights, (2) stronger deterministic parser, (3) cache for insights and optional extraction cache.

---

## 11. Sensitivity and Notes

- **AI pricing** is volatile; re-run with current Anthropic (and any alternatives) before budgeting.  
- **Screenshot rate:** 20/user/month is an assumption; if real usage is 10 or 30, scale costs linearly for AI and bandwidth.  
- **Free-tier caps** (e.g. 10 AI analyses/month) cap cost per user but don’t change unit cost; total cost scales with paid/Pro usage.  
- **Reserved/commit discounts:** 1-year commit for compute/DB can cut costs ~20–40%; consider once usage is stable.

Use this as a planning baseline and update with actual usage and vendor quotes before launch and at each scale milestone.
