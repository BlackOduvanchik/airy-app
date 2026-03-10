import { FastifyInstance } from 'fastify';
import {
  getMonthlySummary,
  getBehavioralInsights,
  getMoneyMirror,
  getYearlyReview,
} from '../services/ai-insight.service.js';
import { checkEntitlement } from '../services/billing.service.js';
import type { AuthenticatedRequest } from '../middleware/auth.middleware.js';
import { authMiddleware } from '../middleware/auth.middleware.js';

export async function insightsRoutes(app: FastifyInstance) {
  app.addHook('preHandler', async (request, reply) => {
    await authMiddleware(request as AuthenticatedRequest, reply);
  });

  app.get('/insights/monthly-summary', async (request, reply) => {
    const userId = (request as AuthenticatedRequest).userId;
    const month = (request.query as { month?: string }).month;
    const allowed = await checkEntitlement(userId!, 'advanced_insights');
    if (!allowed) return reply.status(402).send({ error: 'Pro feature', code: 'ENTITLEMENT_REQUIRED' });
    return getMonthlySummary(userId!, month);
  });

  app.get('/insights/behavioral', async (request, reply) => {
    const userId = (request as AuthenticatedRequest).userId;
    const allowed = await checkEntitlement(userId!, 'advanced_insights');
    if (!allowed) return reply.status(402).send({ error: 'Pro feature', code: 'ENTITLEMENT_REQUIRED' });
    return getBehavioralInsights(userId!);
  });

  app.get('/insights/money-mirror', async (request, reply) => {
    const userId = (request as AuthenticatedRequest).userId;
    const month = (request.query as { month?: string }).month;
    const allowed = await checkEntitlement(userId!, 'advanced_insights');
    if (!allowed) {
      return reply.status(402).send({
        error: 'Pro feature',
        code: 'ENTITLEMENT_REQUIRED',
        feature: 'advanced_insights',
      });
    }
    return getMoneyMirror(userId!, month);
  });

  app.get('/insights/yearly-review', async (request, reply) => {
    const userId = (request as AuthenticatedRequest).userId;
    const yearStr = (request.query as { year?: string }).year;
    const year = yearStr ? parseInt(yearStr, 10) : new Date().getFullYear();
    const allowed = await checkEntitlement(userId!, 'yearly_review');
    if (!allowed) {
      return reply.status(402).send({
        error: 'Pro feature',
        code: 'ENTITLEMENT_REQUIRED',
        feature: 'yearly_review',
      });
    }
    return getYearlyReview(userId!, year);
  });
}
