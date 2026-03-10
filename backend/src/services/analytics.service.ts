/**
 * Analytics engine: precompute and cache monthly/yearly aggregates, category breakdowns, trends.
 */
import { prisma } from '../lib/prisma.js';
import { redis } from '../lib/redis.js';
import { subMonths, format } from 'date-fns';

const DASHBOARD_CACHE_TTL_SEC = 5 * 60; // 5 min
const DASHBOARD_CACHE_KEY = (userId: string) => `airy:dashboard:${userId}`;

function computeMonthlyFromTransactions(
  userId: string,
  yearMonth: string,
  txs: { type: string; amountBase: unknown; category: string }[]
) {
  const totalSpent = txs
    .filter((t) => t.type === 'expense')
    .reduce((s, t) => s + Number(t.amountBase), 0);
  const totalIncome = txs
    .filter((t) => t.type === 'income')
    .reduce((s, t) => s + Number(t.amountBase), 0);
  const byCategory: Record<string, number> = {};
  for (const t of txs.filter((t) => t.type === 'expense')) {
    byCategory[t.category] = (byCategory[t.category] ?? 0) + Number(t.amountBase);
  }
  return {
    yearMonth,
    totalSpent,
    totalIncome,
    byCategory,
    transactionCount: txs.length,
  };
}

export async function getMonthlyAggregate(userId: string, yearMonth: string) {
  const cached = await prisma.monthlyAggregate.findUnique({
    where: { userId_yearMonth: { userId, yearMonth } },
  });
  if (cached) {
    return {
      yearMonth: cached.yearMonth,
      totalSpent: Number(cached.totalSpent),
      totalIncome: Number(cached.totalIncome),
      byCategory: (cached.byCategory as Record<string, number>) ?? {},
      transactionCount: cached.transactionCount,
    };
  }

  const [y, m] = yearMonth.split('-').map(Number);
  const start = new Date(y, m - 1, 1);
  const end = new Date(y, m, 0, 23, 59, 59);

  const txs = await prisma.transaction.findMany({
    where: {
      userId,
      transactionDate: { gte: start, lte: end },
      isDuplicate: false,
    },
    select: {
      type: true,
      amountBase: true,
      category: true,
      merchant: true,
    },
  });

  return computeMonthlyFromTransactions(userId, yearMonth, txs);
}

function computeYearlyFromTransactions(
  txs: { type: string; amountBase: unknown; category: string }[],
  subscriptionTotal: number
) {
  const totalSpent = txs
    .filter((t) => t.type === 'expense')
    .reduce((s, t) => s + Number(t.amountBase), 0);
  const totalIncome = txs
    .filter((t) => t.type === 'income')
    .reduce((s, t) => s + Number(t.amountBase), 0);
  const byCategory: Record<string, number> = {};
  for (const t of txs.filter((t) => t.type === 'expense')) {
    byCategory[t.category] = (byCategory[t.category] ?? 0) + Number(t.amountBase);
  }
  const topCategories = Object.entries(byCategory)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 10)
    .map(([category, amount]) => ({ category, amount }));
  return { totalSpent, totalIncome, topCategories, subscriptionTotal };
}

export async function getYearlyAggregate(userId: string, year: number) {
  const cached = await prisma.yearlyAggregate.findUnique({
    where: { userId_year: { userId, year } },
  });
  if (cached) {
    return {
      year: cached.year,
      totalSpent: Number(cached.totalSpent),
      totalIncome: Number(cached.totalIncome),
      topCategories: (cached.topCategories as { category: string; amount: number }[]) ?? [],
      subscriptionTotal: cached.subscriptionTotal != null ? Number(cached.subscriptionTotal) : 0,
    };
  }

  const start = new Date(year, 0, 1);
  const end = new Date(year, 11, 31, 23, 59, 59);

  const txs = await prisma.transaction.findMany({
    where: {
      userId,
      transactionDate: { gte: start, lte: end },
      isDuplicate: false,
    },
    select: { type: true, amountBase: true, category: true },
  });

  const subs = await prisma.subscription.findMany({
    where: { userId, status: { in: ['confirmed_subscription', 'subscription_candidate'] } },
    select: { amount: true },
  });
  const subscriptionTotal = subs.reduce((s, sub) => s + Number(sub.amount), 0);

  const data = computeYearlyFromTransactions(txs, subscriptionTotal);
  return {
    year,
    totalSpent: data.totalSpent,
    totalIncome: data.totalIncome,
    topCategories: data.topCategories,
    subscriptionTotal: data.subscriptionTotal,
  };
}

export async function refreshYearlyAggregate(userId: string, year: number) {
  const start = new Date(year, 0, 1);
  const end = new Date(year, 11, 31, 23, 59, 59);
  const txs = await prisma.transaction.findMany({
    where: {
      userId,
      transactionDate: { gte: start, lte: end },
      isDuplicate: false,
    },
    select: { type: true, amountBase: true, category: true },
  });
  const subs = await prisma.subscription.findMany({
    where: { userId, status: { in: ['confirmed_subscription', 'subscription_candidate'] } },
    select: { amount: true },
  });
  const subscriptionTotal = subs.reduce((s, sub) => s + Number(sub.amount), 0);
  const data = computeYearlyFromTransactions(txs, subscriptionTotal);

  await prisma.yearlyAggregate.upsert({
    where: { userId_year: { userId, year } },
    update: {
      totalSpent: data.totalSpent,
      totalIncome: data.totalIncome,
      topCategories: data.topCategories as object,
      subscriptionTotal: data.subscriptionTotal,
    },
    create: {
      userId,
      year,
      totalSpent: data.totalSpent,
      totalIncome: data.totalIncome,
      topCategories: data.topCategories as object,
      subscriptionTotal: data.subscriptionTotal,
    },
  });
}

export async function getDashboardData(userId: string) {
  const cacheKey = DASHBOARD_CACHE_KEY(userId);
  const cached = await redis.get(cacheKey);
  if (cached) return JSON.parse(cached) as Awaited<ReturnType<typeof getDashboardDataUncached>>;

  const data = await getDashboardDataUncached(userId);
  await redis.setex(cacheKey, DASHBOARD_CACHE_TTL_SEC, JSON.stringify(data));
  return data;
}

async function getDashboardDataUncached(userId: string) {
  const now = new Date();
  const thisMonth = format(now, 'yyyy-MM');
  const lastMonth = format(subMonths(now, 1), 'yyyy-MM');
  const current = await getMonthlyAggregate(userId, thisMonth);
  const previous = await getMonthlyAggregate(userId, lastMonth);
  const delta =
    previous.totalSpent > 0
      ? ((current.totalSpent - previous.totalSpent) / previous.totalSpent) * 100
      : 0;

  return {
    thisMonth: {
      totalSpent: current.totalSpent,
      totalIncome: current.totalIncome,
      byCategory: current.byCategory,
      transactionCount: current.transactionCount,
    },
    previousMonthSpent: previous.totalSpent,
    deltaPercent: Math.round(delta * 10) / 10,
  };
}

export async function invalidateDashboardCache(userId: string): Promise<void> {
  await redis.del(DASHBOARD_CACHE_KEY(userId));
}

export async function refreshMonthlyAggregate(userId: string, yearMonth: string) {
  const data = await getMonthlyAggregate(userId, yearMonth);
  await prisma.monthlyAggregate.upsert({
    where: {
      userId_yearMonth: { userId, yearMonth },
    },
    update: {
      totalSpent: data.totalSpent,
      totalIncome: data.totalIncome,
      byCategory: data.byCategory as object,
      transactionCount: data.transactionCount,
    },
    create: {
      userId,
      yearMonth,
      totalSpent: data.totalSpent,
      totalIncome: data.totalIncome,
      byCategory: data.byCategory as object,
      transactionCount: data.transactionCount,
    },
  });
}
