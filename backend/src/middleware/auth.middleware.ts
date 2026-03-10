import { FastifyRequest, FastifyReply } from 'fastify';
import { config } from '../config.js';

export interface AuthenticatedRequest extends FastifyRequest {
  userId?: string;
}

/**
 * Expects JWT in Authorization: Bearer <token>.
 * In non-production, x-user-id header is accepted when ALLOW_DEV_USER_HEADER is true.
 */
export async function authMiddleware(
  request: AuthenticatedRequest,
  reply: FastifyReply
): Promise<void> {
  if (config.ALLOW_DEV_USER_HEADER) {
    const header = request.headers['x-user-id'];
    if (header && typeof header === 'string') {
      request.userId = header;
      return;
    }
  }
  try {
    await request.jwtVerify();
    request.userId = (request.user as { userId: string }).userId;
  } catch {
    reply.status(401).send({ error: 'Unauthorized' });
  }
}
