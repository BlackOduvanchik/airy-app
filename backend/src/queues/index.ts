/**
 * BullMQ setup: connection and queue definitions.
 */
import { Queue, Worker } from 'bullmq';
import IORedis from 'ioredis';
import { config } from '../config.js';
import { logger } from '../lib/logger.js';

const connection = new IORedis(config.REDIS_URL, { maxRetriesPerRequest: null });

export const screenshotQueue = new Queue('screenshot-processing', {
  connection,
  defaultJobOptions: {
    attempts: 3,
    backoff: { type: 'exponential', delay: 1000 },
    removeOnComplete: { count: 100 },
  },
});

export const aggregatesQueue = new Queue('aggregates-refresh', {
  connection,
  defaultJobOptions: {
    attempts: 2,
    removeOnComplete: { count: 500 },
  },
});

export function createScreenshotWorker(processor: (payload: unknown) => Promise<void>) {
  return new Worker(
    'screenshot-processing',
    async (job) => {
      await processor(job.data);
    },
    {
      connection,
      concurrency: 5,
    }
  );
}

export function createAggregatesWorker(processor: (payload: unknown) => Promise<void>) {
  return new Worker(
    'aggregates-refresh',
    async (job) => {
      await processor(job.data);
    },
    {
      connection,
      concurrency: 2,
    }
  );
}
