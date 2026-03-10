# Airy Backend

Production-ready TypeScript backend for the Airy iOS expense tracker. Hybrid pipeline: **deterministic extraction first**, **AI classification second**.

## Stack

- **Runtime:** Node.js + TypeScript
- **Framework:** Fastify
- **DB:** PostgreSQL + Prisma
- **Cache/Queue:** Redis + BullMQ
- **AI:** Anthropic (structured extraction and insights)

## Setup

1. Copy `.env.example` to `.env` and set:
   - `DATABASE_URL` (Postgres)
   - `REDIS_URL` (optional for queues)
   - `JWT_SECRET` (min 16 chars; optional if using only `x-user-id`)
   - `ANTHROPIC_API_KEY` (optional if `MOCK_AI=true`)

2. Install and generate Prisma client:

   ```bash
   npm install
   npx prisma generate
   ```

3. Push schema and seed (optional):

   ```bash
   npx prisma db push
   npm run db:seed
   ```

4. Run:

   ```bash
   npm run dev
   ```

   Health: `GET http://localhost:3000/health`

## Mock mode

- **MOCK_AI=true** — No Anthropic calls; deterministic insights and summaries.
- **MOCK_EXCHANGE_RATES=true** — No rate API; fixed USD/EUR/GBP.
- Use header **x-user-id: &lt;userId&gt;** instead of JWT (create a user first via `/api/auth/register-or-login` and use returned `user.id`).

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for pipeline, duplicate detection, merchant memory, subscription detection, and entitlements.

See [API.md](API.md) for route contracts.

## Testing

```bash
npm run test
```
