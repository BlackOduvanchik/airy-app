/**
 * Rate limiting: Redis-based sliding window (incr + expire).
 * Per-IP and optional per-user limits.
 */
import { FastifyRequest, FastifyReply } from 'fastify';
import { redis } from '../lib/redis.js';
import { logger } from '../lib/logger.js';

const WINDOW_SEC = 60;
const IP_LIMIT = 100;
const USER_PARSE_LIMIT = 30;

function getClientIp(request: FastifyRequest): string {
  const forwarded = request.headers['x-forwarded-for'];
  if (typeof forwarded === 'string') return forwarded.split(',')[0].trim();
  return request.ip ?? '127.0.0.1';
}

async function getCountAndIncr(key: string): Promise<{ count: number; ttl: number }> {
  const multi = redis.multi();
  multi.incr(key);
  multi.ttl(key);
  const results = await multi.exec();
  const count = (results?.[0]?.[1] as number) ?? 0;
  let ttl = (results?.[1]?.[1] as number) ?? -1;
  if (ttl === -1) {
    await redis.expire(key, WINDOW_SEC);
    ttl = WINDOW_SEC;
  }
  return { count, ttl };
}

/** Global per-IP rate limit (e.g. 100 req/min). */
export async function rateLimitByIp(
  request: FastifyRequest,
  reply: FastifyReply
): Promise<void> {
  const ip = getClientIp(request);
  const key = `airy:ratelimit:ip:${ip}`;
  try {
    const { count, ttl } = await getCountAndIncr(key);
    reply.header('X-RateLimit-Limit', IP_LIMIT);
    reply.header('X-RateLimit-Remaining', Math.max(0, IP_LIMIT - count));
    if (count > IP_LIMIT) {
      reply.header('Retry-After', String(ttl));
      reply.status(429).send({
        error: 'Too many requests',
        code: 'RATE_LIMIT_EXCEEDED',
        retryAfter: ttl,
      });
    }
  } catch (e) {
    logger.warn({ err: e, requestId: (request as { requestId?: string }).requestId }, 'Rate limit Redis error');
    // Fail open: do not block on Redis errors
  }
}

/** Per-user rate limit for heavy endpoints (e.g. parse-screenshot 30/min). */
export async function rateLimitParseScreenshot(
  request: FastifyRequest,
  reply: FastifyReply
): Promise<void> {
  const r = request as { userId?: string };
  const userId = r.userId;
  if (!userId) return;
  const key = `airy:ratelimit:parse:${userId}`;
  try {
    const { count, ttl } = await getCountAndIncr(key);
    reply.header('X-RateLimit-Limit', USER_PARSE_LIMIT);
    reply.header('X-RateLimit-Remaining', Math.max(0, USER_PARSE_LIMIT - count));
    if (count > USER_PARSE_LIMIT) {
      reply.header('Retry-After', String(ttl));
      reply.status(429).send({
        error: 'Too many parse requests',
        code: 'PARSE_RATE_LIMIT_EXCEEDED',
        retryAfter: ttl,
      });
    }
  } catch (e) {
    logger.warn({ err: e, requestId: (request as { requestId?: string }).requestId }, 'Rate limit Redis error');
  }
}
