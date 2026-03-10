import { FastifyInstance } from 'fastify';
import { exportCsv, exportJson } from '../services/export.service.js';
import { checkEntitlement } from '../services/billing.service.js';
import type { AuthenticatedRequest } from '../middleware/auth.middleware.js';
import { authMiddleware } from '../middleware/auth.middleware.js';

export async function exportRoutes(app: FastifyInstance) {
  app.addHook('preHandler', async (request, reply) => {
    await authMiddleware(request as AuthenticatedRequest, reply);
  });

  app.get('/export/csv', async (request, reply) => {
    const userId = (request as AuthenticatedRequest).userId;
    const { from, to, limit, cursor } = request.query as { from?: string; to?: string; limit?: string; cursor?: string };
    const opts =
      limit != null || cursor != null
        ? { limit: limit != null ? Math.min(parseInt(limit, 10) || 5000, 5000) : undefined, cursor }
        : undefined;
    const result = await exportCsv(
      userId!,
      from ? new Date(from) : undefined,
      to ? new Date(to) : undefined,
      opts
    );
    if (typeof result === 'string') {
      reply.header('Content-Type', 'text/csv');
      reply.header('Content-Disposition', 'attachment; filename="airy-export.csv"');
      return result;
    }
    return result;
  });

  app.get('/export/json', async (request, reply) => {
    const userId = (request as AuthenticatedRequest).userId;
    const extended = await checkEntitlement(userId!, 'export_extended');
    if (!extended) return reply.status(402).send({ error: 'Pro feature', code: 'ENTITLEMENT_REQUIRED' });
    const { from, to, limit, cursor } = request.query as { from?: string; to?: string; limit?: string; cursor?: string };
    const opts =
      limit != null || cursor != null
        ? { limit: limit != null ? Math.min(parseInt(limit, 10) || 5000, 5000) : undefined, cursor }
        : undefined;
    return exportJson(
      userId!,
      from ? new Date(from) : undefined,
      to ? new Date(to) : undefined,
      opts
    );
  });
}
