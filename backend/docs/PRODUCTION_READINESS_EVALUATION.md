# Airy Backend — Production Readiness Evaluation

Each category is rated 1–10 (10 = production-ready). Followed by improvements required before launch.

---

## 1. Security — **4/10**

**Current state:**  
- JWT with 30d expiry when `JWT_SECRET` is set; secret min 16 chars.  
- Routes accept either `Authorization: Bearer <token>` or **`x-user-id` header** with no verification. Any client can send `x-user-id: <anyUserId>` and act as that user if the header is trusted.  
- CORS is `origin: true` (reflect any origin).  
- Helmet is registered but CSP disabled.  
- No CSRF protection.  
- Auth register-or-login accepts any `externalId`/email and creates or returns a user; no verification that the client owns that identity (e.g. no Sign in with Apple token verification).  
- Database uses parameterized queries via Prisma (no raw SQL injection in app code).  
- No explicit request body size limit; very large OCR body could strain memory.

**Improvements before launch:**  
- **Disable or restrict `x-user-id` in production:** Use only for dev/mock; require JWT for all authenticated routes in production, or remove the header path.  
- **Verify identity at registration:** Exchange Sign in with Apple (or similar) token server-side before issuing JWT; do not trust client-provided `externalId` alone.  
- **Restrict CORS:** Set `origin` to the app’s actual origins (e.g. `https://yourapp.com`), not `true`.  
- **Add body size limit:** e.g. `bodyLimit: 1024 * 1024` (1MB) in Fastify so oversized OCR cannot be used for abuse.  
- **Harden Helmet:** Re-enable CSP with a minimal policy or document why it’s disabled.  
- **Secrets:** Ensure `JWT_SECRET` is required in production (config validation) and at least 32 chars; no secrets in logs or error responses.

---

## 2. Data Validation — **6/10**

**Current state:**  
- Zod schemas for OCR payload (`ocrPayloadSchema`: ocrText 1–50000 chars, optional localHash, etc.) and transaction create/update (`createTransactionSchema`, etc.).  
- Some routes use Fastify schema (e.g. parse-screenshot body) and also call `ocrPayloadSchema.parse(request.body)`; double validation.  
- Category is not validated against the allowed list (food, transport, …); invalid categories can be stored.  
- Manual transaction PATCH accepts partial body with no schema in route; relies on ad-hoc checks.  
- No validation that `transactionDate` is not in the future (or only allow e.g. today).  
- Currency codes are length(3) but not checked against a whitelist; unsupported codes can be stored.

**Improvements before launch:**  
- **Single source of validation:** Use Zod for all request bodies and validate once; align Fastify schema with Zod or remove duplicate.  
- **Category whitelist:** Validate category against the fixed list; reject or map invalid to `other`.  
- **Currency whitelist:** Validate `currencyOriginal`/`baseCurrency` against supported codes (or allow unknown but flag).  
- **Date sanity:** Reject or flag `transactionDate` far in the future (e.g. > today + 1 day).  
- **PATCH /transactions/:id:** Define a Zod schema (e.g. updateTransactionSchema) and parse body before update; reject unknown fields.

---

## 3. API Robustness — **5/10**

**Current state:**  
- Global error handler returns 400 for validation errors and 500 for everything else; no 404/409 distinction.  
- No request timeout; long-running sync ingestion can hold connections.  
- No request-id for tracing.  
- Health endpoint returns 200 with `{ ok: true }` and does not check DB or Redis.  
- Some routes (e.g. PATCH/DELETE transaction) return 404 when resource not found; others may not.  
- No idempotency keys; retries can create duplicate transactions.  
- Export and list transactions have no pagination; large result sets can OOM or timeout.

**Improvements before launch:**  
- **Request timeout:** Set Fastify `connectionTimeout` and/or route-level timeout for heavy endpoints (e.g. parse-screenshot).  
- **Request-id:** Generate or propagate `x-request-id`; log it and include in error responses (where safe).  
- **Health checks:** Add `/health/ready` that runs `prisma.$queryRaw\`SELECT 1\`` and Redis PING; return 503 if any fail.  
- **Consistent 404/409:** Return 404 when resource is not found (and user is authorized); 409 when appropriate (e.g. duplicate idempotency key).  
- **Idempotency:** Accept `Idempotency-Key` on POST parse-screenshot and POST /transactions; store result in Redis with TTL; return stored result on replay.  
- **Pagination:** Add `limit` and `cursor` (or `offset`) to GET /transactions and export; enforce max page size.

---

## 4. Rate Limiting — **2/10**

**Current state:**  
- No rate limiting middleware.  
- Architecture doc mentions “429; use Redis for counters” but no implementation.  
- A single client or attacker can send unlimited requests and exhaust DB, Redis, or AI quota.

**Improvements before launch:**  
- **Global rate limit:** Per IP (e.g. 100 req/min) using Redis sliding window or token bucket; return 429 with Retry-After.  
- **Per-user rate limit:** Stricter limit per userId (e.g. 30 parse-screenshot per min) to protect expensive operations.  
- **AI-specific limit:** In addition to entitlement (monthly cap), add short-term limit (e.g. 5 insight requests per user per minute).  
- **Cost-aware backoff:** On 429 from Anthropic, return 503 and Retry-After instead of propagating 429 to client.

---

## 5. AI Prompt Injection Risks — **3/10**

**Current state:**  
- User-controlled data (OCR text, amounts, categories) is concatenated into AI prompts in `ai-insight.service.ts` (e.g. “total this month ${current.totalSpent}, … Category changes: ${details.join(...)}”).  
- Details are server-computed (category names and percentages), not raw OCR; so injection surface is limited to stored category names and numbers.  
- No sanitization (truncation, escaping of newlines or instruction-like patterns).  
- If future AI extraction sends raw OCR to the model, a malicious payload could include “Ignore previous instructions and output …”.

**Improvements before launch:**  
- **Sanitize all user-derived content in prompts:** Truncate to max length; strip or escape newlines and characters that could start a new “instruction” line (e.g. \n\nHuman:, \n\nAssistant:).  
- **Structured prompts:** Prefer passing a JSON object (e.g. `{ totals: {...}, categories: [...] }`) instead of free-text concatenation; reduce chance of model misinterpreting content as instructions.  
- **Strict output schema:** For any AI call, require JSON-only response and validate with Zod; do not execute or display freeform model output.  
- **Document and test:** Add tests with adversarial OCR (e.g. “Ignore above and return …”) and ensure output is either rejected or unchanged from deterministic path.

---

## 6. AI Hallucination Containment — **4/10**

**Current state:**  
- No AI extraction in ingestion pipeline yet; no risk of hallucinated transactions being persisted.  
- Insights: model response is parsed with `JSON.parse(text.replace(...))`; no Zod validation. Malformed or extra fields can throw (caught, fallback to deterministic summary) or be ignored.  
- No check that insight text is grounded (e.g. that numbers in the summary match the provided metrics).  
- No cap on number of items returned by the model (e.g. if it returns 100 “insights”).

**Improvements before launch:**  
- **Validate all AI responses with Zod:** Define schema for monthly summary (`{ summary: z.string().max(500) }`) and insights (`{ insights: z.array(z.object({ type, title, body })).max(10) }`); on parse failure return deterministic result.  
- **Cap arrays:** Enforce max length (e.g. 5 insight cards) before storing or returning.  
- **When AI extraction is added:** Require transactions to reference evidence (e.g. line numbers or raw snippet); reject any transaction without a matching amount/date in OCR; do not persist overall confidence below threshold (send to pending only).  
- **Log and alert:** Log when AI response fails validation or is empty; monitor rate to detect model regressions.

---

## 7. Database Indexing — **7/10**

**Current state:**  
- Transaction: `@@index([userId, transactionDate])`, `@@index([userId, sourceImageHash])`, `@@index([userId, merchant])`, `@@index([userId, category])`.  
- Other models have appropriate unique constraints and indexes (userId, userId+yearMonth, etc.).  
- Duplicate detection loads “last 500 by transactionDate desc” for a user; (userId, transactionDate) supports this.  
- No composite index for (userId, transactionDate, merchant) for “same user, same day, same merchant” duplicate checks; current approach loads 500 and filters in memory, which is acceptable at current scale.  
- Export and analytics range scans use userId + transactionDate; indexing is adequate for single-user range queries.

**Improvements before launch:**  
- **Monitor slow queries:** Enable Prisma query logging in production (or use a slow-query log in Postgres); identify any full table scans or missing indexes as data grows.  
- **Consider partitioning:** When Transaction table grows large (e.g. 10M+ rows), plan partitioning by transactionDate (e.g. monthly) to keep range queries and maintenance efficient.  
- **Review list endpoints:** Ensure GET /transactions with month/year uses the (userId, transactionDate) index; add limit to avoid large scans.

---

## 8. Transaction Consistency — **3/10**

**Current state:**  
- **No Prisma transaction is used in ingestion.** Each item is processed in a loop: create Transaction or PendingTransaction, and at the end refreshMonthlyAggregate and detectSubscriptions. If the process crashes or throws after creating 2 of 5 transactions, the first 2 are committed and the rest are lost; on retry, duplicate detection might skip some and create others, leading to inconsistent state.  
- refreshMonthlyAggregate and detectSubscriptions are not wrapped in a transaction with the inserts; aggregate can be out of sync with data.  
- No optimistic locking or version field on Transaction; concurrent updates can overwrite each other.

**Improvements before launch:**  
- **Wrap ingestion in a DB transaction:** `prisma.$transaction(async (tx) => { ... create all transactions and pending; then refresh aggregate for the month; })`; on failure rollback entire batch. Run detectSubscriptions in the same transaction or in a follow-up job so ingestion stays short.  
- **Idempotency:** With idempotency key, only one commit per key; retries do not double-apply.  
- **Aggregate refresh:** Either keep it inside the same transaction (and accept longer lock) or move to an async job that runs after the transaction commits; ensure job is at-least-once and aggregates are eventually consistent.  
- **Optional:** Add `version` or `updatedAt` to Transaction and use it in PATCH to avoid lost updates under concurrency.

---

## 9. Failure Recovery — **4/10**

**Current state:**  
- BullMQ screenshot job: 3 attempts, exponential backoff (delay 1000). Failed jobs are only logged; no dead-letter queue or alerting.  
- If Redis is down, queue and cache (currency, AI usage, insights cache) fail; no graceful degradation (e.g. skip cache, or return 503 for cache-dependent endpoints).  
- If DB is down, requests fail with 500; no circuit breaker or retry at HTTP layer.  
- No graceful shutdown: SIGTERM does not drain in-flight requests or wait for workers to finish current jobs; deployments can drop requests or leave jobs half-done.  
- Worker and server in same process: if the server crashes, workers go down too; no separation of failure domains.

**Improvements before launch:**  
- **Graceful shutdown:** On SIGTERM/SIGINT, stop accepting new requests (`app.close()`), wait for in-flight requests (with timeout), close worker, then exit.  
- **Dead-letter and alerting:** Move failed jobs (after max attempts) to a DLQ or mark as failed and alert; do not lose them silently.  
- **Redis degradation:** Where possible, catch Redis errors and fall back (e.g. skip cache, or use DB for AI usage count if Redis is down); document behavior. For critical paths (e.g. AI usage increment), decide fail-open vs fail-closed and implement consistently.  
- **Run workers separately:** Run API and workers in different processes/containers so a worker crash does not take down the API and vice versa.

---

## 10. Retry Logic — **5/10**

**Current state:**  
- Queue jobs: 3 attempts with exponential backoff; good for transient failures.  
- No retry at HTTP client level for outgoing calls (Anthropic, exchange rate API); a single timeout or 5xx fails the request.  
- No retry for Prisma operations (e.g. connection errors); caller sees the error.  
- Client retries (e.g. iOS) can double-submit if no idempotency key; duplicate transactions possible.

**Improvements before launch:**  
- **Idempotency keys:** For POST parse-screenshot and POST /transactions, support Idempotency-Key so client retries are safe.  
- **Outgoing calls:** Add retry with backoff (e.g. 1 retry after 2s) for Anthropic and exchange rate API; respect 429 (do not retry immediately).  
- **Document client retry:** Recommend exponential backoff and idempotency key for the app; document which endpoints are idempotent.

---

## 11. Logging — **5/10**

**Current state:**  
- Pino logger with configurable level; pretty-print in non-production.  
- Error handler logs `err` and `url`; no request-id, no userId in every log.  
- Worker logs failed job (jobId, err).  
- No structured fields for audit (e.g. “user X created transaction Y”).  
- Sensitive data: OCR text and full request body could be logged in validation errors or stack traces; need to avoid logging full OCR in production.  
- Observability metrics (recordParseResult, recordAiUsage) only log; not called consistently from ingestion (recordParseResult is not invoked in transaction-ingestion.service).

**Improvements before launch:**  
- **Request context:** Attach request-id and userId to logger child for each request; use in all log lines.  
- **Audit events:** Log security-relevant actions (login, transaction create/delete, export) with userId, resource id, and outcome.  
- **Redact sensitive data:** Do not log full ocrText or full body in production; log length or hash only.  
- **Call metrics from pipeline:** Invoke recordParseResult (and similar) from ingestion with success/lowConfidence/duplicateSkipped/latency so metrics are consistent.  
- **Structured errors:** Log error code and message; avoid logging stack in production for 4xx client errors.

---

## 12. Observability — **4/10**

**Current state:**  
- `observability/metrics.ts` defines recordParseResult and recordAiUsage but they only log; no Prometheus/OpenTelemetry/DataDog.  
- No request duration or status code metrics.  
- No dashboard or SLO definitions.  
- Logger is the only observability output; no traces or spans.  
- No correlation between API request and queue job (e.g. same request-id in job payload and logs).

**Improvements before launch:**  
- **Metrics backend:** Integrate Prometheus (e.g. prom-client) or OpenTelemetry; expose /metrics.  
- **Key metrics:** Request count and latency by route and status; parse-screenshot success rate and latency; duplicate-skipped rate; AI call count and latency; queue depth and job failure count.  
- **Request-id propagation:** Pass request-id (or generate job-id) into queue payload; log it in worker so one trace can follow a request and its job.  
- **Document SLOs:** e.g. p95 latency for parse-screenshot < 5s; error rate < 0.1%; define alerts when SLOs are breached.

---

## 13. Monitoring — **3/10**

**Current state:**  
- No health check of dependencies (/health only returns ok).  
- No alerts or on-call integration.  
- No dashboard for queue depth, error rate, or latency.  
- No uptime or synthetic checks.  
- Logs are the only signal; no aggregation or search strategy documented.

**Improvements before launch:**  
- **Dependency health:** Implement /health/ready (DB + Redis); use in load balancer or Kubernetes readiness probe.  
- **Alerting:** Alert on high error rate (e.g. 5xx > 1%), high latency (e.g. p95 > 10s), queue depth above threshold, Redis/DB connection failures, and AI provider errors.  
- **Dashboard:** At least one dashboard with: request rate, error rate, latency percentiles, queue depth, worker processing rate, and AI usage/cost.  
- **Log aggregation:** Send logs to a central store (e.g. CloudWatch, Datadog, ELK) with retention and search; ensure request-id is searchable.

---

## 14. Cost Protection — **5/10**

**Current state:**  
- Free-tier AI limit: consumeAiAnalysis increments Redis and compares to FREE_MONTHLY_AI_ANALYSES; returns 402 when exceeded. Pro is hardcoded false so everyone is limited.  
- No per-request token or cost logging for Anthropic; no visibility into spend.  
- No global cap on AI calls (e.g. total budget per day); a bug or abuse could exhaust quota.  
- Exchange rate API is cached (Redis); cache miss calls external API; no circuit breaker if the API is expensive or rate-limited.  
- No budget alerts or cost attribution per user/feature.

**Improvements before launch:**  
- **Log AI usage:** Log tokens (input/output) and optionally cost per Anthropic request; aggregate in logs or metrics for alerting.  
- **Global AI budget:** Optional cap (e.g. max N requests per hour across all users) in Redis to protect against runaway cost.  
- **Entitlement cache:** Cache getEntitlements in Redis to avoid repeated DB round-trips and to ensure limit checks are fast and consistent.  
- **Fail closed:** When Redis is down, decide whether to allow or deny AI analysis (recommend deny for cost protection) and document.

---

## 15. Abuse Protection — **3/10**

**Current state:**  
- No rate limiting (see above).  
- `x-user-id` allows impersonation if enabled in production.  
- Register-or-login accepts any externalId and creates users; no proof of identity; an attacker can create many users and consume resources.  
- No CAPTCHA or bot detection on auth or expensive endpoints.  
- Export and list have no pagination; a user could request all data repeatedly and stress DB.  
- No detection or blocking of abusive patterns (e.g. same IP creating many accounts, or one account uploading huge volumes).

**Improvements before launch:**  
- **Rate limiting:** Per-IP and per-user limits (see Rate Limiting).  
- **Remove or restrict x-user-id:** Do not trust it in production.  
- **Verify identity at signup:** Require Sign in with Apple (or similar) token; verify server-side before creating user and issuing JWT.  
- **Pagination and caps:** Enforce max page size and max range on export/list; consider daily export cap per user.  
- **Abuse signals:** Optional: flag or throttle when a user creates many accounts from same IP, or when parse-screenshot volume is anomalously high; log for review.

---

## 16. Storage Growth — **5/10**

**Current state:**  
- No retention policy or archival; Transaction and related tables grow unbounded.  
- No partitioning; single table for all transactions.  
- Export and analytics scan Transaction; as data grows, query cost and storage increase.  
- OCR text and optional fields (ocrText, comment) stored in full; no compression or truncation policy.  
- Redis keys (cache, usage, insights) have TTL; no explicit eviction policy documented for Redis memory.

**Improvements before launch:**  
- **Retention policy:** Document and implement (e.g. keep raw transactions 7 years, then archive to cold storage or aggregate-only).  
- **Partitioning plan:** When approaching scale (e.g. 10M+ transactions), introduce partitioning by transactionDate.  
- **OCR truncation:** Already 2000 chars in ingestion; document and enforce max stored length; consider not storing ocrText long-term for old records (or move to object storage with TTL).  
- **Redis memory:** Set maxmemory and eviction policy (e.g. volatile-lru) and monitor; ensure TTLs are set on all cache keys.  
- **Aggregate usage:** Use MonthlyAggregate/YearlyAggregate for reads where possible so heavy analytics do not always scan Transaction.

---

## 17. Migration Strategy — **4/10**

**Current state:**  
- Prisma schema exists; migrations are possible via `prisma migrate`.  
- No documented process for zero-downtime or backward-compatible migrations.  
- No migration run in CI/CD or deployment pipeline described.  
- Seed script exists for demo data; no env-specific seeds (e.g. production vs staging).  
- If schema changes (e.g. add required field), existing rows could break without a multi-phase migration.

**Improvements before launch:**  
- **Document migration process:** e.g. (1) add column as optional, (2) backfill, (3) add constraint or make required; run migrations in deploy pipeline with rollback plan.  
- **Run migrations in deploy:** Execute `prisma migrate deploy` (or equivalent) as part of release; fail deploy if migrations fail.  
- **Backward compatibility:** Avoid breaking API or DB contract in a single release; support old and new behavior during transition where possible.  
- **Seed separation:** Do not run seed in production; use separate seed for staging/demo; document how to backfill or fix data after schema change.

---

## Summary Table

| Category                    | Rating | Critical gaps |
|----------------------------|--------|----------------|
| Security                   | 4/10   | x-user-id trust, no identity verification, CORS open, no body limit |
| Data validation            | 6/10   | Category/currency whitelist, PATCH schema, date sanity |
| API robustness             | 5/10   | No timeout, no request-id, health not dependency-aware, no idempotency |
| Rate limiting              | 2/10   | Not implemented |
| AI prompt injection        | 3/10   | User data in prompts, no sanitization |
| AI hallucination containment | 4/10 | No Zod for AI responses, no caps when extraction added |
| Database indexing          | 7/10   | Adequate; plan partitioning at scale |
| Transaction consistency    | 3/10   | No DB transaction in ingestion |
| Failure recovery           | 4/10   | No graceful shutdown, no DLQ, Redis/worker coupling |
| Retry logic                | 5/10   | Queue retry OK; no HTTP/idempotency for clients |
| Logging                    | 5/10   | No request context, metrics not wired, sensitive data risk |
| Observability              | 4/10   | Log-only; no metrics backend or traces |
| Monitoring                 | 3/10   | No dependency health, no alerts or dashboard |
| Cost protection            | 5/10   | Free-tier cap exists; no token logging, no global cap |
| Abuse protection           | 3/10   | No rate limit, x-user-id, no identity verification |
| Storage growth             | 5/10   | No retention, no partitioning, Redis policy not set |
| Migration strategy         | 4/10   | No zero-downtime process or deploy integration |

**Overall:** The backend is **not yet production-ready**. Average across categories is ~4.4/10. The highest risks are: **security (x-user-id, identity verification), rate limiting, transaction consistency, monitoring, and abuse protection.**

---

## Improvements Required Before Launch (Prioritized)

### P0 (Must-have)

1. **Security:** Disable or strictly restrict `x-user-id` in production; require JWT. Verify identity (e.g. Sign in with Apple token) at register-or-login before issuing JWT.
2. **Rate limiting:** Implement per-IP and per-user rate limits (Redis); return 429 with Retry-After.
3. **Transaction consistency:** Wrap screenshot ingestion in `prisma.$transaction`; ensure one batch is all-or-nothing.
4. **Health:** Add /health/ready that checks DB and Redis; use for load balancer / readiness.
5. **Idempotency:** Support Idempotency-Key on POST parse-screenshot and POST /transactions; store result and return on replay.

### P1 (Should-have)

6. **Request timeout and request-id:** Set connection/request timeout; generate and log request-id.
7. **AI response validation:** Validate all AI responses (insights, future extraction) with Zod; cap array lengths; return deterministic fallback on failure.
8. **Prompt sanitization:** Sanitize/truncate user-derived content in AI prompts; use structured JSON input where possible.
9. **Graceful shutdown:** Drain requests and workers on SIGTERM; then exit.
10. **Logging:** Attach request-id and userId to logs; redact OCR/body in production; call recordParseResult from ingestion.
11. **Category and currency validation:** Validate category against whitelist; validate or allowlist currency codes.
12. **Pagination:** Add limit/cursor to GET /transactions and export; enforce max page size.

### P2 (Nice-to-have before launch)

13. **CORS:** Restrict to actual app origins.
14. **Body size limit:** Set Fastify bodyLimit (e.g. 1MB).
15. **Metrics:** Add Prometheus or OTel; expose /metrics; key counters and histograms.
16. **Alerting:** Alert on error rate, latency, queue depth, and dependency failure.
17. **Entitlement cache:** Cache getEntitlements in Redis with short TTL; invalidate on subscription change.
18. **Dead-letter and job failure alerting:** Move failed jobs to DLQ or mark and alert.
19. **Document migration and run in deploy:** Zero-downtime migration process; run migrations in CI/CD.

Once P0 and P1 are addressed, the system will be in a much stronger position for production launch; P2 can be phased in during or shortly after launch.
