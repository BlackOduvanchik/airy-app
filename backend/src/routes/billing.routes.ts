import { FastifyInstance } from 'fastify';
import { syncAppStoreSubscription, getEntitlements } from '../services/billing.service.js';
import type { AuthenticatedRequest } from '../middleware/auth.middleware.js';
import { authMiddleware } from '../middleware/auth.middleware.js';

export async function billingRoutes(app: FastifyInstance) {
  app.addHook('preHandler', async (request, reply) => {
    await authMiddleware(request as AuthenticatedRequest, reply);
  });

  app.post<{
    Body: { productId?: string; transactionId?: string; expiresAt?: string };
  }>('/billing/sync', async (request, reply) => {
    const userId = (request as AuthenticatedRequest).userId;
    const { productId, transactionId, expiresAt } = request.body ?? {};
    const expiresAtDate = expiresAt ? new Date(expiresAt) : undefined;
    const entitlements = await syncAppStoreSubscription(
      userId!,
      productId,
      transactionId,
      expiresAtDate
    );
    return entitlements;
  });
}
