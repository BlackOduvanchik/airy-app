/**
 * Request logging: record start time on request, log method, url, requestId, statusCode, durationMs on response.
 */
import { FastifyRequest, FastifyReply } from 'fastify';
import { logger } from '../lib/logger.js';

declare module 'fastify' {
  interface FastifyRequest {
    startTimeMs?: number;
  }
}

export const requestLogger = {
  onRequest(request: FastifyRequest, _reply: FastifyReply, done: () => void) {
    (request as FastifyRequest & { startTimeMs: number }).startTimeMs = Date.now();
    done();
  },
  onResponse(
    request: FastifyRequest,
    reply: FastifyReply,
    _payload: unknown,
    done: (err?: Error) => void
  ) {
    const start = (request as FastifyRequest & { startTimeMs?: number }).startTimeMs ?? Date.now();
    const durationMs = Date.now() - start;
    logger.info(
      {
        method: request.method,
        url: request.url,
        requestId: request.requestId,
        statusCode: reply.statusCode,
        durationMs,
      },
      'Request'
    );
    done();
  },
};
