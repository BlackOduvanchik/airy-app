import Redis from 'ioredis';
import { config } from '../config.js';

const globalForRedis = globalThis as unknown as { redis: Redis };

export const redis: Redis =
  globalForRedis.redis ??
  new Redis(config.REDIS_URL, {
    maxRetriesPerRequest: null,
  });

if (process.env.NODE_ENV !== 'production') globalForRedis.redis = redis;
