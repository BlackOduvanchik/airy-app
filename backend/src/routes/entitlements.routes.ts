import { FastifyInstance } from 'fastify';
import { getEntitlements } from '../services/billing.service.js';
import type { AuthenticatedRequest } from '../middleware/auth.middleware.js';
import { authMiddleware } from '../middleware/auth.middleware.js';

export async function entitlementsRoutes(app: FastifyInstance) {
  app.addHook('preHandler', async (request, reply) => {
    await authMiddleware(request as AuthenticatedRequest, reply);
  });

  app.get('/entitlements', async (request) => {
    const userId = (request as AuthenticatedRequest).userId;
    return getEntitlements(userId!);
  });
}
