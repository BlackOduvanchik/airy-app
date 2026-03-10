import { FastifyInstance } from 'fastify';
import {
  listMerchantRules,
  upsertMerchantRule,
  deleteMerchantRule,
} from '../services/merchant-memory.service.js';
import type { AuthenticatedRequest } from '../middleware/auth.middleware.js';
import { authMiddleware } from '../middleware/auth.middleware.js';

export async function merchantMemoryRoutes(app: FastifyInstance) {
  app.addHook('preHandler', async (request, reply) => {
    await authMiddleware(request as AuthenticatedRequest, reply);
  });

  app.get('/merchant-rules', async (request) => {
    const userId = (request as AuthenticatedRequest).userId;
    return listMerchantRules(userId!);
  });

  app.post('/merchant-rules', {
    schema: {
      body: {
        type: 'object',
        required: ['merchantNormalized', 'category'],
        properties: {
          merchantNormalized: { type: 'string' },
          category: { type: 'string' },
          subcategory: { type: 'string' },
          isSubscription: { type: 'boolean' },
        },
      },
    },
  }, async (request) => {
    const userId = (request as AuthenticatedRequest).userId;
    const body = request.body as {
      merchantNormalized: string;
      category: string;
      subcategory?: string;
      isSubscription?: boolean;
    };
    return upsertMerchantRule(userId!, body);
  });

  app.delete('/merchant-rules/:id', async (request, reply) => {
    const userId = (request as AuthenticatedRequest).userId;
    const { id } = request.params as { id: string };
    await deleteMerchantRule(userId!, id);
    return { deleted: true };
  });
}
