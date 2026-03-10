/**
 * Transaction ingestion: orchestrate screenshot pipeline (normalize → parse → classify → duplicate → persist).
 * When deterministic parse is empty but OCR text exists, call AI extraction; validate with ai-extraction schema and merge into pipeline.
 */
import { prisma } from '../lib/prisma.js';
import { normalizeOcrText } from './ocr-normalize.service.js';
import { parseTransactionsFromOcr, type ParsedItem } from './transaction-parser.service.js';
import { extractTransactionsFromOcr } from './ai-extraction.service.js';
import {
  findDuplicateByHash,
  getRecentTransactions,
  checkDuplicateBatch,
  type RecentTransaction,
} from './duplicate-detection.service.js';
import { classifyCategory } from './category-classification.service.js';
import { getMerchantRulesBatch, normalizeMerchant } from './merchant-memory.service.js';
import { convert } from './currency.service.js';
import { aggregatesQueue } from '../queues/index.js';
import { invalidateDashboardCache } from './analytics.service.js';
import { invalidateInsightsCache } from './ai-insight.service.js';
import { ALLOWED_CATEGORIES } from '../schemas/transaction.schema.js';
import { logger } from '../lib/logger.js';

const LOW_CONFIDENCE_THRESHOLD = 0.6;

/** Unified item shape: parser output or AI output (AI may include category + confidence). */
type IngestionItem = ParsedItem & { category?: string; confidence?: number };

export interface ScreenshotIngestionInput {
  userId: string;
  ocrText: string;
  localHash?: string;
  baseCurrency: string;
  requestId?: string;
}

export interface IngestionResult {
  accepted: number;
  duplicateSkipped: number;
  pendingReview: number;
  pendingIds: string[];
  errors: string[];
  reason?: 'no_transactions_found' | 'ocr_empty';
}

export async function ingestScreenshot(input: ScreenshotIngestionInput): Promise<IngestionResult> {
  const result: IngestionResult = {
    accepted: 0,
    duplicateSkipped: 0,
    pendingReview: 0,
    pendingIds: [],
    errors: [],
  };
  const normalizedText = normalizeOcrText(input.ocrText);
  let parsed: IngestionItem[] = parseTransactionsFromOcr(normalizedText);

  if (parsed.length === 0 && normalizedText.trim().length > 0) {
    const aiItems = await extractTransactionsFromOcr(normalizedText, input.userId);
    if (aiItems.length > 0) {
      parsed = aiItems as IngestionItem[];
    }
  }

  if (parsed.length === 0) {
    result.reason = normalizedText.trim().length === 0 ? 'ocr_empty' : 'no_transactions_found';
    result.errors.push(result.reason === 'ocr_empty' ? 'OCR text empty' : 'No transactions found in OCR text');
    return result;
  }

  if (input.localHash) {
    const byHash = await findDuplicateByHash(input.userId, input.localHash);
    if (byHash) {
      result.duplicateSkipped = parsed.length;
      enqueuePostProcessing(input.userId);
      return result;
    }
  }

  const [recentTx, rulesMap] = await Promise.all([
    getRecentTransactions(input.userId),
    getMerchantRulesBatch(
      input.userId,
      parsed.map((p) => p.merchant ?? '').filter(Boolean)
    ),
  ]);

  const duplicateInputs = parsed.map((item) => ({
    amount: item.amount,
    currency: item.currency,
    date: item.date,
    merchant: item.merchant,
    ocrText: normalizedText.slice(0, 1000),
  }));
  const duplicateResults = checkDuplicateBatch(duplicateInputs, recentTx as RecentTransaction[]);

  const toInsert: Parameters<typeof prisma.transaction.create>[0]['data'][] = [];
  const toPending: Parameters<typeof prisma.pendingTransaction.create>[0]['data'][] = [];

  for (let i = 0; i < parsed.length; i++) {
    const item = parsed[i];
    const dup = duplicateResults[i];
    try {
      if (dup.action === 'auto_skip' || (dup.action === 'duplicate_candidate' && dup.isDuplicate)) {
        result.duplicateSkipped++;
        continue;
      }

      const normalizedMerchant = normalizeMerchant(item.merchant ?? '');
      const rule = rulesMap.get(normalizedMerchant);
      let rawCategory: string;
      let finalConfidence: number;
      if (item.category != null && (ALLOWED_CATEGORIES as readonly string[]).includes(item.category)) {
        rawCategory = item.category;
        finalConfidence = item.confidence ?? LOW_CONFIDENCE_THRESHOLD;
      } else {
        const classified = await classifyCategory(
          input.userId,
          item.merchant,
          item.rawLine,
          rule ?? undefined
        );
        rawCategory = classified.category;
        finalConfidence = classified.confidence;
      }
      const finalCategory = (ALLOWED_CATEGORIES as readonly string[]).includes(rawCategory)
        ? rawCategory
        : 'other';

      const amountBase = await convert(item.amount, item.currency, input.baseCurrency);

      const txType = finalCategory === 'income' || item.isCredit ? 'income' : 'expense';

      if (finalConfidence < LOW_CONFIDENCE_THRESHOLD) {
        toPending.push({
          userId: input.userId,
          payload: {
            type: txType,
            amountOriginal: item.amount,
            currencyOriginal: item.currency,
            amountBase,
            baseCurrency: input.baseCurrency,
            merchant: item.merchant,
            transactionDate: item.date,
            transactionTime: item.time,
            category: finalCategory,
            sourceType: 'screenshot',
            sourceImageHash: input.localHash,
          },
          ocrText: normalizedText.slice(0, 2000),
          sourceImageHash: input.localHash ?? null,
          confidence: finalConfidence,
          reason: 'low_confidence',
        });
        result.pendingReview++;
        continue;
      }

      toInsert.push({
        userId: input.userId,
        type: txType,
        amountOriginal: item.amount,
        currencyOriginal: item.currency,
        amountBase,
        baseCurrency: input.baseCurrency,
        merchant: item.merchant,
        transactionDate: new Date(item.date),
        transactionTime: item.time ?? null,
        category: finalCategory,
        sourceType: 'screenshot',
        sourceImageHash: input.localHash ?? null,
        ocrText: normalizedText.slice(0, 2000),
        confidence: finalConfidence,
        isDuplicate: false,
      });
      result.accepted++;
    } catch (e) {
      logger.warn({ err: e, item, requestId: input.requestId }, 'Ingest item failed');
      result.errors.push(String(e));
    }
  }

  const createdPendingIds: string[] = [];
  await prisma.$transaction(async (tx) => {
    for (const data of toInsert) {
      await tx.transaction.create({ data });
    }
    for (const data of toPending) {
      const pending = await tx.pendingTransaction.create({ data });
      createdPendingIds.push(pending.id);
    }
  });
  result.pendingIds.push(...createdPendingIds);

  enqueuePostProcessing(input.userId);
  if (result.accepted > 0 || result.pendingReview > 0) {
    await invalidateDashboardCache(input.userId).catch(() => {});
    await invalidateInsightsCache(input.userId).catch(() => {});
  }
  return result;
}

function enqueuePostProcessing(userId: string): void {
  const yearMonth = new Date().toISOString().slice(0, 7);
  const year = new Date().getFullYear();
  aggregatesQueue.add('refresh', { type: 'refresh' as const, userId, yearMonth }).catch((e) => {
    logger.warn({ err: e, userId }, 'Failed to enqueue aggregates refresh');
  });
  aggregatesQueue.add('subscriptions', { type: 'subscriptions' as const, userId }).catch((e) => {
    logger.warn({ err: e, userId }, 'Failed to enqueue subscriptions detect');
  });
  aggregatesQueue.add('yearly', { type: 'yearly' as const, userId, year }).catch((e) => {
    logger.warn({ err: e, userId }, 'Failed to enqueue yearly aggregate refresh');
  });
}
