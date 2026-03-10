/**
 * Aggregates and subscriptions post-processing jobs.
 */
import {
  refreshMonthlyAggregate,
  refreshYearlyAggregate,
} from '../services/analytics.service.js';
import { detectSubscriptions } from '../services/subscription-detector.service.js';
import { logger } from '../lib/logger.js';

export interface AggregatesRefreshPayload {
  userId: string;
  yearMonth: string;
}

export interface SubscriptionsDetectPayload {
  userId: string;
}

export type AggregateJobPayload =
  | { type: 'refresh'; userId: string; yearMonth: string }
  | { type: 'subscriptions'; userId: string }
  | { type: 'yearly'; userId: string; year: number };

export async function processAggregatesJob(data: unknown): Promise<void> {
  const payload = data as AggregateJobPayload;
  if (payload.type === 'subscriptions') {
    if (!payload.userId) throw new Error('Missing userId');
    await detectSubscriptions(payload.userId);
    logger.info({ userId: payload.userId }, 'Subscriptions detect job completed');
    return;
  }
  if (payload.type === 'yearly') {
    if (!payload.userId || payload.year == null) throw new Error('Missing userId or year');
    await refreshYearlyAggregate(payload.userId, payload.year);
    logger.info({ userId: payload.userId, year: payload.year }, 'Yearly aggregate refresh completed');
    return;
  }
  if (payload.type === 'refresh') {
    if (!payload.userId || !payload.yearMonth) throw new Error('Missing userId or yearMonth');
    await refreshMonthlyAggregate(payload.userId, payload.yearMonth);
    logger.info({ userId: payload.userId, yearMonth: payload.yearMonth }, 'Aggregates refresh job completed');
    return;
  }
  throw new Error('Unknown aggregate job type');
}
