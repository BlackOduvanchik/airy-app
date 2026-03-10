/**
 * Screenshot processing job: run ingestion pipeline async.
 */
import { ingestScreenshot } from '../services/transaction-ingestion.service.js';
import { logger } from '../lib/logger.js';

export interface ScreenshotJobPayload {
  userId: string;
  ocrText: string;
  localHash?: string;
  baseCurrency: string;
}

export async function processScreenshotJob(data: unknown): Promise<void> {
  const payload = data as ScreenshotJobPayload;
  if (!payload.userId || !payload.ocrText) {
    throw new Error('Missing userId or ocrText');
  }
  const result = await ingestScreenshot({
    userId: payload.userId,
    ocrText: payload.ocrText,
    localHash: payload.localHash,
    baseCurrency: payload.baseCurrency ?? 'USD',
  });
  logger.info({ userId: payload.userId, result }, 'Screenshot job completed');
}
