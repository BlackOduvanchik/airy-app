/**
 * Merchant memory: store and apply user correction rules (category, subscription).
 */
import { prisma } from '../lib/prisma.js';

export function normalizeMerchant(name: string): string {
  return name
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .replace(/[^\w\s]/g, '')
    .trim()
    .slice(0, 256);
}

export interface MerchantRuleInput {
  merchantNormalized: string;
  category: string;
  subcategory?: string;
  isSubscription?: boolean;
}

export async function upsertMerchantRule(
  userId: string,
  input: MerchantRuleInput
) {
  const normalized = normalizeMerchant(input.merchantNormalized);
  return prisma.merchantRule.upsert({
    where: {
      userId_merchantNormalized: { userId, merchantNormalized: normalized },
    },
    update: {
      category: input.category,
      subcategory: input.subcategory ?? null,
      isSubscription: input.isSubscription ?? false,
      lastConfirmedAt: new Date(),
    },
    create: {
      userId,
      merchantNormalized: normalized,
      category: input.category,
      subcategory: input.subcategory ?? null,
      isSubscription: input.isSubscription ?? false,
    },
  });
}

export type MerchantRuleLookup = {
  category: string;
  subcategory?: string;
  isSubscription: boolean;
};

export async function getMerchantRule(
  userId: string,
  merchantName: string
): Promise<MerchantRuleLookup | null> {
  const normalized = normalizeMerchant(merchantName);
  const rule = await prisma.merchantRule.findUnique({
    where: { userId_merchantNormalized: { userId, merchantNormalized: normalized } },
  });
  if (!rule) return null;
  return {
    category: rule.category,
    subcategory: rule.subcategory ?? undefined,
    isSubscription: rule.isSubscription,
  };
}

/** Fetch rules for multiple merchants in one query; returns Map of normalized name -> rule. */
export async function getMerchantRulesBatch(
  userId: string,
  merchantNames: string[]
): Promise<Map<string, MerchantRuleLookup>> {
  const normalized = [...new Set(merchantNames.map((n) => normalizeMerchant(n)).filter(Boolean))];
  if (normalized.length === 0) return new Map();
  const rules = await prisma.merchantRule.findMany({
    where: { userId, merchantNormalized: { in: normalized } },
  });
  const map = new Map<string, MerchantRuleLookup>();
  for (const r of rules) {
    map.set(r.merchantNormalized, {
      category: r.category,
      subcategory: r.subcategory ?? undefined,
      isSubscription: r.isSubscription,
    });
  }
  return map;
}

export async function listMerchantRules(userId: string) {
  return prisma.merchantRule.findMany({
    where: { userId },
    orderBy: { lastConfirmedAt: 'desc' },
  });
}

export async function deleteMerchantRule(userId: string, ruleId: string) {
  return prisma.merchantRule.deleteMany({
    where: { id: ruleId, userId },
  });
}
