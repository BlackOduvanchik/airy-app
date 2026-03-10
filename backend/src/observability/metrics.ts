/**
 * Observability: parse success rate, low-confidence rate, duplicate rate, latency.
 * In production, wire to Prometheus/DataDog; here we log and optionally store in Redis.
 */
import { logger } from '../lib/logger.js';

export function recordParseResult(opts: {
  success: boolean;
  lowConfidence: boolean;
  duplicateSkipped: boolean;
  reviewRequired: boolean;
  latencyMs: number;
  userId?: string;
  requestId?: string;
}) {
  logger.info(
    {
      ...opts,
      metric: 'parse_result',
    },
    'Parse result'
  );
}

export function recordAiUsage(opts: { userId: string; feature: string; tokens?: number }) {
  logger.info({ ...opts, metric: 'ai_usage' }, 'AI usage');
}
