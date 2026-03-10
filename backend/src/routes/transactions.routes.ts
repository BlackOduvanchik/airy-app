import { FastifyInstance } from 'fastify';
import { prisma } from '../lib/prisma.js';
import { redis } from '../lib/redis.js';
import { ingestScreenshot } from '../services/transaction-ingestion.service.js';
import { screenshotQueue } from '../queues/index.js';
import { ocrPayloadSchema } from '../schemas/ocr-payload.schema.js';
import { createTransactionSchema, categorySchema, confirmPendingBodySchema } from '../schemas/transaction.schema.js';
import { convert } from '../services/currency.service.js';
import { upsertMerchantRule } from '../services/merchant-memory.service.js';
import { consumeAiAnalysis, getAiUsageRemaining } from '../services/billing.service.js';
import { invalidateDashboardCache } from '../services/analytics.service.js';
import { invalidateInsightsCache } from '../services/ai-insight.service.js';
import type { AuthenticatedRequest } from '../middleware/auth.middleware.js';
import { authMiddleware } from '../middleware/auth.middleware.js';
import { rateLimitParseScreenshot } from '../middleware/rate-limit.js';
import { recordParseResult } from '../observability/metrics.js';

const IDEMPOTENCY_TTL_SEC = 24 * 60 * 60;

export async function transactionsRoutes(app: FastifyInstance) {
  app.addHook('preHandler', async (request, reply) => {
    await authMiddleware(request as AuthenticatedRequest, reply);
  });

  app.post(
    '/transactions/parse-screenshot',
    {
      schema: {
        body: {
          type: 'object',
          required: ['ocrText'],
          properties: {
            ocrText: { type: 'string' },
            localHash: { type: 'string' },
            baseCurrency: { type: 'string', default: 'USD' },
          },
        },
      },
    },
    async (request, reply) => {
      const userId = (request as AuthenticatedRequest).userId;
      if (!userId) return reply.status(401).send({ error: 'Unauthorized' });
      await rateLimitParseScreenshot(request, reply);
      if (reply.sent) return;
      const idempotencyKey = request.headers['idempotency-key'] as string | undefined;
      if (idempotencyKey?.trim()) {
        const cached = await redis.get(`airy:idempotency:${idempotencyKey}`);
        if (cached) {
          return reply.status(200).send(JSON.parse(cached) as object);
        }
      }
      const allowed = await consumeAiAnalysis(userId);
      if (!allowed) {
        const remaining = await getAiUsageRemaining(userId);
        return reply.status(402).send({
          error: 'Monthly AI limit reached',
          code: 'AI_LIMIT',
          ai_analyses_remaining: remaining ?? 0,
        });
      }
      const body = ocrPayloadSchema.parse(request.body);
      const baseCurrency = (request.body as { baseCurrency?: string }).baseCurrency ?? 'USD';
      const startMs = Date.now();
      const result = await ingestScreenshot({
        userId,
        ocrText: body.ocrText,
        localHash: body.localHash,
        baseCurrency,
        requestId: request.requestId,
      });
      recordParseResult({
        success: result.errors.length === 0 && (result.accepted + result.pendingReview + result.duplicateSkipped) > 0,
        lowConfidence: result.pendingReview > 0,
        duplicateSkipped: result.duplicateSkipped > 0,
        reviewRequired: result.pendingReview > 0,
        latencyMs: Date.now() - startMs,
        userId,
        requestId: request.requestId,
      });
      if (idempotencyKey?.trim()) {
        await redis.setex(
          `airy:idempotency:${idempotencyKey}`,
          IDEMPOTENCY_TTL_SEC,
          JSON.stringify(result)
        );
      }
      const aiRemaining = await getAiUsageRemaining(userId);
      return reply.send({
        ...result,
        ...(aiRemaining !== null && { ai_analyses_remaining: aiRemaining }),
      });
    }
  );

  app.post(
    '/transactions/parse-screenshot/async',
    async (request, reply) => {
      const userId = (request as AuthenticatedRequest).userId;
      if (!userId) return reply.status(401).send({ error: 'Unauthorized' });
      const allowed = await consumeAiAnalysis(userId);
      if (!allowed)
        return reply.status(402).send({ error: 'Monthly AI limit reached', code: 'AI_LIMIT' });
      const body = ocrPayloadSchema.parse(request.body);
      const baseCurrency = (request.body as { baseCurrency?: string }).baseCurrency ?? 'USD';
      await screenshotQueue.add('screenshot', {
        userId,
        ocrText: body.ocrText,
        localHash: body.localHash,
        baseCurrency,
      });
      return { queued: true };
    }
  );

  app.get('/transactions/pending', async (request) => {
    const userId = (request as AuthenticatedRequest).userId;
    const list = await prisma.pendingTransaction.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
    });
    return { pending: list };
  });

  app.delete('/transactions/pending/:id', async (request, reply) => {
    const userId = (request as AuthenticatedRequest).userId;
    const { id } = request.params as { id: string };
    const pending = await prisma.pendingTransaction.findFirst({
      where: { id, userId },
    });
    if (!pending) return reply.status(404).send({ error: 'Not found' });
    await prisma.pendingTransaction.delete({ where: { id } });
    return { deleted: true };
  });

  app.post('/transactions/pending/:id/confirm', async (request, reply) => {
    const userId = (request as AuthenticatedRequest).userId;
    const { id } = request.params as { id: string };
    const pending = await prisma.pendingTransaction.findFirst({
      where: { id, userId },
    });
    if (!pending) return reply.status(404).send({ error: 'Not found' });
    const payload = pending.payload as Record<string, unknown>;
    const body = request.body as Record<string, unknown> | undefined;
    const parsed = body && typeof body === 'object' ? confirmPendingBodySchema.safeParse(body) : null;
    const overrides = parsed?.success ? parsed.data : null;
    const merged = {
      type: (overrides?.type ?? payload.type ?? 'expense') as string,
      amountOriginal: (overrides?.amountOriginal ?? payload.amountOriginal) as number,
      currencyOriginal: (overrides?.currencyOriginal ?? payload.currencyOriginal) as string,
      amountBase: payload.amountBase as number,
      baseCurrency: (overrides?.baseCurrency ?? payload.baseCurrency) as string,
      merchant: (overrides?.merchant ?? payload.merchant ?? null) as string | null,
      transactionDate: (overrides?.transactionDate ?? payload.transactionDate) as string,
      transactionTime: (overrides?.transactionTime ?? payload.transactionTime ?? null) as string | null,
      category: (overrides?.category ?? payload.category) as string,
      subcategory: (overrides?.subcategory ?? payload.subcategory ?? null) as string | null,
    };
    if (overrides && (overrides.amountOriginal != null || overrides.currencyOriginal != null || overrides.baseCurrency != null)) {
      merged.amountBase = await convert(merged.amountOriginal, merged.currencyOriginal, merged.baseCurrency);
    }
    await prisma.transaction.create({
      data: {
        userId,
        type: merged.type,
        amountOriginal: merged.amountOriginal,
        currencyOriginal: merged.currencyOriginal,
        amountBase: merged.amountBase,
        baseCurrency: merged.baseCurrency,
        merchant: merged.merchant,
        transactionDate: new Date(merged.transactionDate),
        transactionTime: merged.transactionTime,
        category: merged.category,
        subcategory: merged.subcategory,
        sourceType: 'screenshot',
        sourceImageHash: (payload.sourceImageHash as string) ?? null,
      },
    });
    await prisma.pendingTransaction.delete({ where: { id } });
    await invalidateDashboardCache(userId).catch(() => {});
    await invalidateInsightsCache(userId).catch(() => {});
    return { confirmed: true };
  });

  app.post('/transactions', async (request, reply) => {
    const userId = (request as AuthenticatedRequest).userId;
    if (!userId) return reply.status(401).send({ error: 'Unauthorized' });
    const idempotencyKey = request.headers['idempotency-key'] as string | undefined;
    if (idempotencyKey?.trim()) {
      const cached = await redis.get(`airy:idempotency:tx:${idempotencyKey}`);
      if (cached) return reply.status(200).send(JSON.parse(cached) as object);
    }
    const body = createTransactionSchema.parse(request.body);
    const tx = await prisma.transaction.create({
      data: {
        userId,
        type: body.type,
        amountOriginal: body.amountOriginal,
        currencyOriginal: body.currencyOriginal,
        amountBase: body.amountBase,
        baseCurrency: body.baseCurrency,
        merchant: body.merchant,
        title: body.title,
        transactionDate: new Date(body.transactionDate),
        transactionTime: body.transactionTime,
        category: body.category,
        subcategory: body.subcategory,
        isSubscription: body.isSubscription,
        comment: body.comment,
        sourceType: body.sourceType,
      },
    });
    if (idempotencyKey?.trim()) {
      await redis.setex(
        `airy:idempotency:tx:${idempotencyKey}`,
        IDEMPOTENCY_TTL_SEC,
        JSON.stringify(tx)
      );
    }
    await invalidateDashboardCache(userId).catch(() => {});
    await invalidateInsightsCache(userId).catch(() => {});
    return tx;
  });

  app.patch('/transactions/:id', async (request, reply) => {
    const userId = (request as AuthenticatedRequest).userId;
    const { id } = request.params as { id: string };
    const body = request.body as Record<string, unknown>;
    if (body.category != null) {
      const parsed = categorySchema.safeParse(body.category);
      if (!parsed.success) return reply.status(400).send({ error: 'Invalid category', details: parsed.error.flatten() });
      body.category = parsed.data;
    }
    const tx = await prisma.transaction.findFirst({ where: { id, userId } });
    if (!tx) return reply.status(404).send({ error: 'Not found' });
    const updated = await prisma.transaction.update({
      where: { id },
      data: {
        ...(body.amountOriginal != null && { amountOriginal: body.amountOriginal }),
        ...(body.amountBase != null && { amountBase: body.amountBase }),
        ...(body.merchant != null && { merchant: body.merchant as string }),
        ...(body.category != null && { category: body.category as string }),
        ...(body.subcategory != null && { subcategory: body.subcategory as string }),
        ...(body.transactionDate != null && { transactionDate: new Date(body.transactionDate as string) }),
        ...(body.comment != null && { comment: body.comment as string }),
      },
    });
    if ((body.category != null || body.isSubscription != null) && (updated.merchant ?? tx.merchant)) {
      const merchant = (updated.merchant ?? tx.merchant) as string;
      await upsertMerchantRule(userId, {
        merchantNormalized: merchant,
        category: updated.category,
        isSubscription: updated.isSubscription ?? false,
      }).catch(() => {});
    }
    await invalidateDashboardCache(userId).catch(() => {});
    await invalidateInsightsCache(userId).catch(() => {});
    return updated;
  });

  app.delete('/transactions/:id', async (request, reply) => {
    const userId = (request as AuthenticatedRequest).userId;
    const { id } = request.params as { id: string };
    const tx = await prisma.transaction.findFirst({ where: { id, userId } });
    if (!tx) return reply.status(404).send({ error: 'Not found' });
    await prisma.transaction.delete({ where: { id } });
    await invalidateDashboardCache(userId).catch(() => {});
    await invalidateInsightsCache(userId).catch(() => {});
    return { deleted: true };
  });

  app.get('/transactions', async (request) => {
    const userId = (request as AuthenticatedRequest).userId;
    const { month, year, limit: limitQ, cursor } = request.query as {
      month?: string;
      year?: string;
      limit?: string;
      cursor?: string;
    };
    const limit = Math.min(Math.max(parseInt(limitQ ?? '50', 10) || 50, 1), 100);
    const where: { userId: string; transactionDate?: object } = { userId };
    if (month && year) {
      const y = parseInt(year, 10);
      const m = parseInt(month, 10);
      where.transactionDate = {
        gte: new Date(y, m - 1, 1),
        lte: new Date(y, m, 0, 23, 59, 59),
      };
    }
    const list = await prisma.transaction.findMany({
      where,
      orderBy: [{ transactionDate: 'desc' }, { id: 'desc' }],
      take: limit + 1,
      ...(cursor && { cursor: { id: cursor }, skip: 1 }),
    });
    const hasMore = list.length > limit;
    const transactions = hasMore ? list.slice(0, limit) : list;
    const nextCursor = hasMore && transactions.length > 0 ? transactions[transactions.length - 1].id : null;
    return { transactions, nextCursor, hasMore };
  });
}
