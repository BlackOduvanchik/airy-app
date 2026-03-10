/**
 * Airy Backend — Entry point (HTTP API only; run worker via npm run worker).
 */
import Fastify from 'fastify';
import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import jwt from '@fastify/jwt';
import { randomUUID } from 'node:crypto';
import { ZodError } from 'zod';
import { config } from './config.js';
import { logger } from './lib/logger.js';
import { registerRoutes } from './routes/index.js';
import { rateLimitByIp } from './middleware/rate-limit.js';
import { requestLogger } from './observability/request-logger.js';
import { prisma } from './lib/prisma.js';
import { redis } from './lib/redis.js';

declare module 'fastify' {
  interface FastifyRequest {
    requestId?: string;
  }
}

async function build() {
  if (config.NODE_ENV === 'production' && !config.JWT_SECRET) {
    throw new Error('JWT_SECRET is required in production');
  }
  const app = Fastify({ logger: false, bodyLimit: 1024 * 1024 });
  app.decorateRequest('requestId', '');
  app.addHook('onRequest', async (request, reply) => {
    const id = (request.headers['x-request-id'] as string) || randomUUID();
    request.requestId = id;
    reply.header('x-request-id', id);
  });
  app.addHook('onRequest', requestLogger.onRequest);
  app.addHook('onResponse', requestLogger.onResponse);
  app.addHook('onRequest', async (request, reply) => {
    await rateLimitByIp(request, reply);
  });
  app.setErrorHandler((err, request, reply) => {
    const requestId = request.requestId ?? '';
    if (err instanceof ZodError) {
      reply.status(400).send({
        error: 'Validation failed',
        code: 'VALIDATION_ERROR',
        details: err.flatten(),
      });
      return;
    }
    if (err.validation) {
      reply.status(400).send({ error: 'Validation failed', details: err.validation });
      return;
    }
    logger.error({ err, url: request.url, requestId }, 'Request error');
    reply.status(500).send({ error: 'Internal server error' });
  });
  const corsOrigin = config.ALLOWED_ORIGINS
    ? config.ALLOWED_ORIGINS.split(',').map((s) => s.trim()).filter(Boolean)
    : true;
  await app.register(cors, { origin: corsOrigin });
  await app.register(helmet, { contentSecurityPolicy: false });
  if (config.JWT_SECRET) {
    await app.register(jwt, {
      secret: config.JWT_SECRET,
      sign: { expiresIn: '30d' },
    });
    app.decorateRequest('user', null);
    app.addHook('preHandler', async (request, reply) => {
      try {
        if (request.headers.authorization) {
          await request.jwtVerify();
          request.user = request.user ?? (request as { user?: object }).user;
        }
      } catch {
        // ignore; routes that need auth will verify again
      }
    });
  }
  await registerRoutes(app);
  app.get('/health', (_, reply) => reply.send({ ok: true }));
  app.get('/health/ready', async (_, reply) => {
    try {
      await prisma.$queryRaw`SELECT 1`;
      await redis.ping();
      return reply.send({ ok: true });
    } catch (e) {
      logger.warn({ err: e }, 'Readiness check failed');
      return reply.status(503).send({ ok: false, error: 'Service unavailable' });
    }
  });

  return app;
}

async function main() {
  const app = await build();
  await app.listen({ port: config.PORT, host: '0.0.0.0' });
  logger.info({ port: config.PORT }, 'Airy backend listening');
}

main().catch((e) => {
  logger.error(e);
  process.exit(1);
});
