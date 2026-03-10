/**
 * Billing / entitlement service: free vs Pro feature gating.
 * Resolves from config (PRO_USER_IDS, ENABLE_PRO_FOR_ALL) or User subscription fields (App Store sync).
 * In production, subscription updates require server-side App Store verification when transactionId is sent.
 */
import { config } from '../config.js';
import { prisma } from '../lib/prisma.js';
import { getTransactionInfo, isAppStoreConfigured } from './app-store-verify.service.js';

export type Entitlement =
  | 'monthly_ai_limit'
  | 'unlimited_ai_analysis'
  | 'advanced_insights'
  | 'subscriptions_dashboard'
  | 'yearly_review'
  | 'export_extended'
  | 'cloud_sync';

export interface Entitlements {
  monthly_ai_limit: number;
  unlimited_ai_analysis: boolean;
  advanced_insights: boolean;
  subscriptions_dashboard: boolean;
  yearly_review: boolean;
  export_extended: boolean;
  cloud_sync: boolean;
}

/** Sync App Store subscription: update User and return entitlements. Uses server-side verification when configured. */
export async function syncAppStoreSubscription(
  userId: string,
  productId?: string,
  transactionId?: string,
  expiresAt?: Date
): Promise<Entitlements> {
  const data: {
    subscriptionProductId?: string;
    subscriptionExpiresAt?: Date | null;
    appStoreTransactionId?: string;
  } = {};

  if (transactionId != null) {
    const isProduction = config.NODE_ENV === 'production';
    if (isProduction && !isAppStoreConfigured()) {
      throw new Error(
        'App Store Connect API must be configured in production when syncing with transactionId. Set APPLE_APP_STORE_CONNECT_KEY_ID, ISSUER_ID, and private key.'
      );
    }
    const verified = await getTransactionInfo(transactionId);
    if (verified != null) {
      if (verified.isValid) {
        data.subscriptionProductId = verified.productId;
        data.subscriptionExpiresAt = verified.expiresAt;
        data.appStoreTransactionId = transactionId;
      }
      // When verification is configured, only update from Apple response.
    } else {
      if (isProduction) {
        throw new Error(
          'Transaction could not be verified with Apple. Sync rejected in production.'
        );
      }
      // Non-production: allow trusting client for local/dev.
      data.appStoreTransactionId = transactionId;
      if (productId != null) data.subscriptionProductId = productId;
      if (expiresAt !== undefined) data.subscriptionExpiresAt = expiresAt ?? null;
    }
  } else {
    if (productId != null) data.subscriptionProductId = productId;
    if (expiresAt !== undefined) data.subscriptionExpiresAt = expiresAt ?? null;
  }

  if (Object.keys(data).length > 0) {
    await prisma.user.update({
      where: { id: userId },
      data,
    });
  }
  return getEntitlements(userId);
}

/** Resolve from config or User subscription (App Store). */
export async function getEntitlements(userId: string): Promise<Entitlements> {
  const proIds = config.PRO_USER_IDS
    ? config.PRO_USER_IDS.split(',').map((s) => s.trim()).filter(Boolean)
    : [];
  if (config.ENABLE_PRO_FOR_ALL || proIds.includes(userId)) {
    const freeLimit = config.FREE_MONTHLY_AI_ANALYSES;
    return {
      monthly_ai_limit: 999999,
      unlimited_ai_analysis: true,
      advanced_insights: true,
      subscriptions_dashboard: true,
      yearly_review: true,
      export_extended: true,
      cloud_sync: true,
    };
  }
  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: { subscriptionExpiresAt: true },
  });
  const isPro =
    user?.subscriptionExpiresAt != null && user.subscriptionExpiresAt > new Date();
  const freeLimit = config.FREE_MONTHLY_AI_ANALYSES;
  return {
    monthly_ai_limit: isPro ? 999999 : freeLimit,
    unlimited_ai_analysis: isPro,
    advanced_insights: isPro,
    subscriptions_dashboard: isPro,
    yearly_review: isPro,
    export_extended: isPro,
    cloud_sync: isPro,
  };
}

export async function checkEntitlement(
  userId: string,
  feature: Entitlement
): Promise<boolean> {
  const e = await getEntitlements(userId);
  if (feature === 'monthly_ai_limit') return e.monthly_ai_limit > 0;
  if (feature === 'unlimited_ai_analysis') return e.unlimited_ai_analysis;
  if (feature === 'advanced_insights') return e.advanced_insights;
  if (feature === 'subscriptions_dashboard') return e.subscriptions_dashboard;
  if (feature === 'yearly_review') return e.yearly_review;
  if (feature === 'export_extended') return e.export_extended;
  if (feature === 'cloud_sync') return e.cloud_sync;
  return false;
}

export async function consumeAiAnalysis(userId: string): Promise<boolean> {
  const e = await getEntitlements(userId);
  if (e.unlimited_ai_analysis) return true;
  const month = new Date().toISOString().slice(0, 7);
  const key = `airy:ai_usage:${userId}:${month}`;
  const { redis } = await import('../lib/redis.js');
  const current = await redis.incr(key);
  if (current === 1) await redis.expire(key, 60 * 60 * 24 * 32);
  return current <= e.monthly_ai_limit;
}

/** Returns remaining AI analyses for the month, or null if unlimited. */
export async function getAiUsageRemaining(userId: string): Promise<number | null> {
  const e = await getEntitlements(userId);
  if (e.unlimited_ai_analysis) return null;
  const month = new Date().toISOString().slice(0, 7);
  const key = `airy:ai_usage:${userId}:${month}`;
  const { redis } = await import('../lib/redis.js');
  const current = await redis.get(key);
  const count = current ? parseInt(current, 10) : 0;
  return Math.max(0, e.monthly_ai_limit - count);
}
