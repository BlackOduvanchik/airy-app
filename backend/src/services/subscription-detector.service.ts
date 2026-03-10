/**
 * Recurring subscription detector: same/similar merchant, similar amount, regular interval.
 */
import { prisma } from '../lib/prisma.js';
import { subDays } from 'date-fns';

const AMOUNT_TOLERANCE = 0.05;
const MIN_OCCURRENCES = 2;

function normalizeMerchant(m: string): string {
  return m.toLowerCase().replace(/\s+/g, ' ').trim().slice(0, 256);
}

export async function detectSubscriptions(userId: string): Promise<void> {
  const transactions = await prisma.transaction.findMany({
    where: { userId, type: 'expense' },
    orderBy: { transactionDate: 'asc' },
    select: {
      id: true,
      merchant: true,
      amountOriginal: true,
      currencyOriginal: true,
      transactionDate: true,
      category: true,
    },
  });

  const byMerchant = new Map<string, typeof transactions>();
  for (const t of transactions) {
    const key = normalizeMerchant(t.merchant ?? '');
    if (!key) continue;
    if (!byMerchant.has(key)) byMerchant.set(key, []);
    byMerchant.get(key)!.push(t);
  }

  for (const [, list] of byMerchant) {
    if (list.length < MIN_OCCURRENCES) continue;
    const amounts = list.map((t) => Number(t.amountOriginal));
    const avg = amounts.reduce((a, b) => a + b, 0) / amounts.length;
    const similarAmount = (a: number) => Math.abs(a - avg) / (avg || 1) <= AMOUNT_TOLERANCE;
    const withSimilarAmount = list.filter((t) => similarAmount(Number(t.amountOriginal)));
    if (withSimilarAmount.length < MIN_OCCURRENCES) continue;

    const dates = withSimilarAmount
      .map((t) => t.transactionDate.getTime())
      .sort((a, b) => a - b);
    const gaps: number[] = [];
    for (let i = 1; i < dates.length; i++) gaps.push((dates[i] - dates[i - 1]) / (24 * 60 * 60 * 1000));
    const avgGap = gaps.length ? gaps.reduce((a, b) => a + b, 0) / gaps.length : 0;
    const isMonthly = avgGap >= 25 && avgGap <= 35;
    const isYearly = avgGap >= 350 && avgGap <= 380;
    const isWeekly = avgGap >= 6 && avgGap <= 8;
    const interval = isYearly ? 'yearly' : isWeekly ? 'weekly' : isMonthly ? 'monthly' : null;
    if (!interval) continue;

    const lastDate = list[list.length - 1].transactionDate;
    const nextBilling =
      interval === 'monthly'
        ? subDays(lastDate, -30)
        : interval === 'yearly'
          ? subDays(lastDate, -365)
          : subDays(lastDate, -7);

    const merchant = list[0].merchant ?? 'Unknown';
    const existing = await prisma.subscription.findFirst({
      where: { userId, merchant },
    });
    if (existing) {
      const data: {
        amount: number;
        currency: string | null;
        interval: string;
        nextBillingDate: Date;
        status?: string;
      } = {
        amount: avg,
        currency: list[0].currencyOriginal,
        interval,
        nextBillingDate: nextBilling,
      };
      if (existing.status === 'subscription_candidate') {
        data.status = 'subscription_candidate';
      }
      await prisma.subscription.update({
        where: { id: existing.id },
        data,
      });
    } else {
      await prisma.subscription.create({
        data: {
          userId,
          merchant,
          amount: avg,
          currency: list[0].currencyOriginal,
          interval,
          nextBillingDate: nextBilling,
          status: 'subscription_candidate',
        },
      });
    }

    await prisma.transaction.updateMany({
      where: { id: { in: list.map((t) => t.id) } },
      data: { isRecurringCandidate: true },
    });
  }
}

// Prisma unique on Subscription: we need a unique constraint. Let me check schema - we don't have userId_merchant. I'll use findFirst + create/update instead.