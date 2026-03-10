import { FastifyInstance } from 'fastify';
import { authRoutes } from './auth.routes.js';
import { transactionsRoutes } from './transactions.routes.js';
import { subscriptionsRoutes } from './subscriptions.routes.js';
import { analyticsRoutes } from './analytics.routes.js';
import { insightsRoutes } from './insights.routes.js';
import { exportRoutes } from './export.routes.js';
import { entitlementsRoutes } from './entitlements.routes.js';
import { merchantMemoryRoutes } from './merchant-memory.routes.js';
import { billingRoutes } from './billing.routes.js';

export async function registerRoutes(app: FastifyInstance) {
  await app.register(authRoutes, { prefix: '/api' });
  await app.register(transactionsRoutes, { prefix: '/api' });
  await app.register(subscriptionsRoutes, { prefix: '/api' });
  await app.register(analyticsRoutes, { prefix: '/api' });
  await app.register(insightsRoutes, { prefix: '/api' });
  await app.register(exportRoutes, { prefix: '/api' });
  await app.register(entitlementsRoutes, { prefix: '/api' });
  await app.register(merchantMemoryRoutes, { prefix: '/api' });
  await app.register(billingRoutes, { prefix: '/api' });
}
