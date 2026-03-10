/**
 * App Store Server API: verify transactions and get subscription info.
 * Uses App Store Connect API key (JWT) for authentication.
 */
import * as jose from 'jose';
import { readFile } from 'fs/promises';
import { config } from '../config.js';

const PRODUCTION_URL = 'https://api.storekit.itunes.apple.com';
const SANDBOX_URL = 'https://api.storekit-sandbox.itunes.apple.com';

export interface TransactionInfo {
  productId: string;
  expiresAt: Date | null;
  isValid: boolean;
}

function getPrivateKeyPem(): string | null {
  const pem = config.APPLE_APP_STORE_CONNECT_PRIVATE_KEY;
  if (pem) return pem;
  return null;
}

async function loadPrivateKeyPem(): Promise<string | null> {
  const fromEnv = getPrivateKeyPem();
  if (fromEnv) return fromEnv;
  const path = config.APPLE_APP_STORE_CONNECT_PRIVATE_KEY_PATH;
  if (path) {
    const content = await readFile(path, 'utf-8');
    return content;
  }
  return null;
}

export function isAppStoreConfigured(): boolean {
  return !!(
    config.APPLE_APP_STORE_CONNECT_KEY_ID &&
    config.APPLE_APP_STORE_CONNECT_ISSUER_ID &&
    (config.APPLE_APP_STORE_CONNECT_PRIVATE_KEY || config.APPLE_APP_STORE_CONNECT_PRIVATE_KEY_PATH)
  );
}

/**
 * Build a signed JWT for the App Store Server API (ES256, aud: appstoreconnect-v1).
 */
async function createAppStoreJwt(): Promise<string> {
  const keyId = config.APPLE_APP_STORE_CONNECT_KEY_ID;
  const issuerId = config.APPLE_APP_STORE_CONNECT_ISSUER_ID;
  const bundleId = config.APPLE_BUNDLE_ID;
  if (!keyId || !issuerId || !bundleId) {
    throw new Error('App Store Connect config missing: KEY_ID, ISSUER_ID, or APPLE_BUNDLE_ID');
  }
  const pem = await loadPrivateKeyPem();
  if (!pem) {
    throw new Error('App Store Connect private key not set (PRIVATE_KEY or PRIVATE_KEY_PATH)');
  }
  const privateKey = await jose.importPKCS8(pem.replace(/\\n/g, '\n'), 'ES256');
  const now = Math.floor(Date.now() / 1000);
  const token = await new jose.SignJWT({ bid: bundleId })
    .setProtectedHeader({ alg: 'ES256', kid: keyId, typ: 'JWT' })
    .setIssuer(issuerId)
    .setAudience('appstoreconnect-v1')
    .setIssuedAt(now)
    .setExpirationTime(now + 60 * 20)
    .sign(privateKey);
  return token;
}

/**
 * Call Apple's Get Transaction Info. Tries production first, then sandbox if 404.
 */
async function fetchTransactionFromApple(transactionId: string): Promise<{ signedTransactionInfo?: string } | null> {
  const token = await createAppStoreJwt();
  const headers: Record<string, string> = {
    Authorization: `Bearer ${token}`,
    'Content-Type': 'application/json',
  };
  const urls = [`${PRODUCTION_URL}/inApps/v1/transactions/${transactionId}`, `${SANDBOX_URL}/inApps/v1/transactions/${transactionId}`];
  for (const url of urls) {
    const res = await fetch(url, { method: 'GET', headers });
    if (res.ok) {
      const body = (await res.json()) as { signedTransactionInfo?: string };
      return body;
    }
    if (res.status !== 404) {
      const text = await res.text();
      throw new Error(`App Store API error ${res.status}: ${text}`);
    }
  }
  return null;
}

/**
 * Decode the signed transaction JWS payload (no signature verification; we trust the response from Apple over HTTPS).
 * Payload has expiresDate (ms), productId, etc.
 */
function decodeSignedTransactionInfo(signedTransactionInfo: string): { productId?: string; expiresDate?: number } {
  const parts = signedTransactionInfo.split('.');
  if (parts.length !== 3) throw new Error('Invalid JWS format');
  const payload = jose.decodeJwt(signedTransactionInfo) as { productId?: string; expiresDate?: number };
  return payload;
}

/**
 * Get transaction info from Apple. Returns productId and expiresAt.
 * When App Store Connect config is missing, returns null (caller can skip verification).
 */
export async function getTransactionInfo(transactionId: string): Promise<TransactionInfo | null> {
  if (!isAppStoreConfigured()) {
    return null;
  }
  const body = await fetchTransactionFromApple(transactionId);
  if (!body?.signedTransactionInfo) {
    return null;
  }
  const payload = decodeSignedTransactionInfo(body.signedTransactionInfo);
  const productId = payload.productId ?? '';
  const expiresDate = payload.expiresDate;
  const expiresAt = expiresDate != null ? new Date(expiresDate) : null;
  const isValid = !!productId && (expiresAt === null || expiresAt > new Date());
  return {
    productId,
    expiresAt,
    isValid,
  };
}
