import { FastifyRequest, FastifyReply } from 'fastify';
import { checkEntitlement, type Entitlement } from '../services/billing.service.js';
import type { AuthenticatedRequest } from './auth.middleware.js';

export function requireEntitlement(feature: Entitlement) {
  return async function (request: FastifyRequest, reply: FastifyReply): Promise<void> {
    const userId = (request as AuthenticatedRequest).userId;
    if (!userId) {
      reply.status(401).send({ error: 'Unauthorized' });
      return;
    }
    const allowed = await checkEntitlement(userId, feature);
    if (!allowed) {
      reply.status(402).send({
        error: 'Entitlement required',
        code: 'ENTITLEMENT_REQUIRED',
        feature,
      });
    }
  };
}
