/**
 * Airy Backend — Worker entrypoint (BullMQ only, no HTTP).
 */
import { logger } from './lib/logger.js';
import { createScreenshotWorker, createAggregatesWorker } from './queues/index.js';
import { processScreenshotJob } from './queues/screenshot.job.js';
import { processAggregatesJob } from './queues/aggregates.job.js';

async function main() {
  try {
    const screenshotWorker = createScreenshotWorker(processScreenshotJob);
    screenshotWorker.on('failed', (job, err) =>
      logger.warn({ jobId: job?.id, err }, 'Screenshot job failed')
    );
    const aggregatesWorker = createAggregatesWorker(async (data) => processAggregatesJob(data));
    aggregatesWorker.on('failed', (job, err) =>
      logger.warn({ jobId: job?.id, err }, 'Aggregates job failed')
    );
    logger.info('Airy worker started (screenshot-processing, aggregates-refresh)');
  } catch (e) {
    logger.error({ err: e }, 'Worker failed to start (Redis may be down)');
    process.exit(1);
  }
}

main();
