import { FastifyInstance } from 'fastify';
import { prisma } from '../lib/prisma.js';
import { checkEntitlement } from '../services/billing.service.js';
import type { AuthenticatedRequest } from '../middleware/auth.middleware.js';
import { authMiddleware } from '../middleware/auth.middleware.js';

export async function subscriptionsRoutes(app: FastifyInstance) {
  app.addHook('preHandler', async (request, reply) => {
    await authMiddleware(request as AuthenticatedRequest, reply);
  });

  app.get('/subscriptions', async (request, reply) => {
    const userId = (request as AuthenticatedRequest).userId;
    const allowed = await checkEntitlement(userId!, 'subscriptions_dashboard');
    if (!allowed) {
      return reply.status(402).send({
        error: 'Pro feature',
        code: 'ENTITLEMENT_REQUIRED',
        feature: 'subscriptions_dashboard',
      });
    }
    const list = await prisma.subscription.findMany({
      where: { userId },
      orderBy: { nextBillingDate: 'asc' },
    });
    return { subscriptions: list };
  });
}
