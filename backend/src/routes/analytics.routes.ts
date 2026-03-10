import { FastifyInstance } from 'fastify';
import { getMonthlyAggregate, getYearlyAggregate, getDashboardData } from '../services/analytics.service.js';
import { checkEntitlement } from '../services/billing.service.js';
import type { AuthenticatedRequest } from '../middleware/auth.middleware.js';
import { authMiddleware } from '../middleware/auth.middleware.js';

export async function analyticsRoutes(app: FastifyInstance) {
  app.addHook('preHandler', async (request, reply) => {
    await authMiddleware(request as AuthenticatedRequest, reply);
  });

  app.get('/analytics/dashboard', async (request) => {
    const userId = (request as AuthenticatedRequest).userId;
    return getDashboardData(userId!);
  });

  app.get<{ Querystring: { month: string } }>('/analytics/monthly', async (request) => {
    const userId = (request as AuthenticatedRequest).userId;
    const month = request.query.month ?? new Date().toISOString().slice(0, 7);
    return getMonthlyAggregate(userId!, month);
  });

  app.get<{ Querystring: { year: string } }>('/analytics/yearly', async (request, reply) => {
    const userId = (request as AuthenticatedRequest).userId;
    const allowed = await checkEntitlement(userId!, 'yearly_review');
    if (!allowed) {
      return reply.status(402).send({
        error: 'Pro feature',
        code: 'ENTITLEMENT_REQUIRED',
        feature: 'yearly_review',
      });
    }
    const year = parseInt(request.query.year ?? String(new Date().getFullYear()), 10);
    return getYearlyAggregate(userId!, year);
  });
}
