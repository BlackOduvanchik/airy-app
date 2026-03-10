/**
 * Auth service: JWT issue/verify, user identity.
 * For local-first, supports device-based externalId without email.
 */
import { prisma } from '../lib/prisma.js';
import { config } from '../config.js';

export interface TokenPayload {
  userId: string;
  email?: string;
  externalId?: string;
}

export async function findOrCreateUserByExternalId(externalId: string, email?: string | null) {
  let user = await prisma.user.findFirst({ where: { externalId } });
  if (!user) {
    user = await prisma.user.create({
      data: { externalId, email: email ?? null },
    });
  } else if (email && user.email !== email) {
    user = await prisma.user.update({
      where: { id: user.id },
      data: { email },
    });
  }
  return user;
}

/** Find or create user by Apple subject (sub). Uses externalId = "apple_<sub>". */
export async function findOrCreateUserByAppleSubject(appleSub: string, email?: string | null) {
  const externalId = `apple_${appleSub}`;
  return findOrCreateUserByExternalId(externalId, email);
}

export async function findUserById(userId: string) {
  return prisma.user.findUnique({ where: { id: userId } });
}

export function getJwtSecret(): string {
  const secret = config.JWT_SECRET;
  if (!secret) throw new Error('JWT_SECRET is required for auth');
  return secret;
}
