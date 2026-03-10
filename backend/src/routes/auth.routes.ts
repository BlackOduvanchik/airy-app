import { FastifyInstance } from 'fastify';
import { findOrCreateUserByExternalId, findOrCreateUserByAppleSubject } from '../services/auth.service.js';
import { verifyAppleIdentityToken } from '../services/apple-auth.service.js';
import { appleAuthBodySchema } from '../schemas/apple-auth.schema.js';

const registerBodySchema = {
  externalId: { type: 'string' },
  email: { type: 'string', nullable: true },
};

export async function authRoutes(app: FastifyInstance) {
  app.post<{ Body: { externalId: string; email?: string } }>(
    '/auth/register-or-login',
    {
      schema: { body: registerBodySchema },
    },
    async (request, reply) => {
      const { externalId, email } = request.body;
      const user = await findOrCreateUserByExternalId(externalId, email);
      const token = app.jwt.sign(
        { userId: user.id, email: user.email, externalId: user.externalId },
        { expiresIn: '30d' }
      );
      return { token, user: { id: user.id, email: user.email } };
    }
  );

  app.post<{ Body: { identityToken: string; email?: string } }>(
    '/auth/apple',
    {
      schema: {
        body: {
          type: 'object',
          required: ['identityToken'],
          properties: {
            identityToken: { type: 'string' },
            email: { type: 'string' },
          },
        },
      },
    },
    async (request, reply) => {
      const parsed = appleAuthBodySchema.safeParse(request.body);
      if (!parsed.success) {
        return reply.code(400).send({ error: 'Invalid body', details: parsed.error.flatten() });
      }
      const { identityToken, email: bodyEmail } = parsed.data;
      let payload: { sub: string; email?: string };
      try {
        payload = await verifyAppleIdentityToken(identityToken);
      } catch (err) {
        return reply.code(401).send({ error: err instanceof Error ? err.message : 'Invalid Apple token' });
      }
      const email = bodyEmail ?? payload.email ?? null;
      const user = await findOrCreateUserByAppleSubject(payload.sub, email);
      const token = app.jwt.sign(
        { userId: user.id, email: user.email, externalId: user.externalId },
        { expiresIn: '30d' }
      );
      return { token, user: { id: user.id, email: user.email } };
    }
  );
}
