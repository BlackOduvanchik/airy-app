/**
 * Verify Apple identity tokens (JWT) using Apple's JWKS.
 * Validates signature (RS256), iss and aud claims.
 */
import * as jose from 'jose';
import { config } from '../config.js';

const APPLE_KEYS_URL = 'https://appleid.apple.com/auth/keys';
const APPLE_ISSUER = 'https://appleid.apple.com';

export interface AppleTokenPayload {
  sub: string;
  email?: string;
}

let cachedJwks: jose.RemoteJWKSet | null = null;

function getAppleJwks(): jose.RemoteJWKSet {
  if (!cachedJwks) {
    cachedJwks = jose.createRemoteJWKSet(new URL(APPLE_KEYS_URL));
  }
  return cachedJwks;
}

/**
 * Verify the Apple identity token and return sub (and optional email from payload).
 * Throws if token is invalid or APPLE_BUNDLE_ID is not set.
 */
export async function verifyAppleIdentityToken(identityToken: string): Promise<AppleTokenPayload> {
  const bundleId = config.APPLE_BUNDLE_ID;
  if (!bundleId) {
    throw new Error('APPLE_BUNDLE_ID is required for Apple Sign-In');
  }

  const jwks = getAppleJwks();
  const { payload } = await jose.jwtVerify(identityToken, jwks, {
    issuer: APPLE_ISSUER,
    audience: bundleId,
    algorithms: ['RS256'],
  });

  const sub = payload.sub as string;
  if (!sub) {
    throw new Error('Apple token missing sub claim');
  }

  return {
    sub,
    email: payload.email as string | undefined,
  };
}
