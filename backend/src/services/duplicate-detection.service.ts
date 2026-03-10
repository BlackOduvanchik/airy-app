/**
 * Duplicate detection: weighted scoring on hash, amount, date, merchant, OCR similarity.
 * Exact match → auto-skip; high score → duplicate candidate; ambiguous → review.
 */
import { prisma } from '../lib/prisma.js';

const WEIGHTS = {
  imageHash: 0.35,
  amount: 0.2,
  currency: 0.05,
  merchant: 0.2,
  date: 0.15,
  ocrSimilarity: 0.05,
};

const AUTO_SKIP_THRESHOLD = 0.95;
const DUPLICATE_CANDIDATE_THRESHOLD = 0.7;

function normalizeMerchant(m: string): string {
  return m
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .replace(/[^\w\s]/g, '')
    .trim()
    .slice(0, 128);
}

function merchantSimilarity(a: string, b: string): number {
  const na = normalizeMerchant(a);
  const nb = normalizeMerchant(b);
  if (!na || !nb) return 0;
  if (na === nb) return 1;
  const longer = na.length > nb.length ? na : nb;
  const shorter = na.length > nb.length ? nb : na;
  const edit = levenshtein(na, nb);
  return 1 - edit / longer.length;
}

function levenshtein(a: string, b: string): number {
  const matrix: number[][] = [];
  for (let i = 0; i <= b.length; i++) matrix[i] = [i];
  for (let j = 0; j <= a.length; j++) matrix[0][j] = j;
  for (let i = 1; i <= b.length; i++) {
    for (let j = 1; j <= a.length; j++) {
      if (b[i - 1] === a[j - 1]) matrix[i][j] = matrix[i - 1][j - 1];
      else matrix[i][j] = 1 + Math.min(matrix[i - 1][j - 1], matrix[i][j - 1], matrix[i - 1][j]);
    }
  }
  return matrix[b.length][a.length];
}

function textSimilarity(a: string, b: string): number {
  if (!a || !b) return 0;
  const na = a.slice(0, 500).toLowerCase();
  const nb = b.slice(0, 500).toLowerCase();
  if (na === nb) return 1;
  const edit = levenshtein(na, nb);
  return 1 - edit / Math.max(na.length, nb.length, 1);
}

function amountSimilarity(amount1: number, amount2: number): number {
  if (amount1 === amount2) return 1;
  const max = Math.max(Math.abs(amount1), Math.abs(amount2), 0.01);
  const diff = Math.abs(amount1 - amount2);
  return Math.max(0, 1 - diff / max);
}

function dateProximity(date1: string, date2: string): number {
  const d1 = new Date(date1).getTime();
  const d2 = new Date(date2).getTime();
  const diffDays = Math.abs(d1 - d2) / (24 * 60 * 60 * 1000);
  if (diffDays === 0) return 1;
  if (diffDays <= 1) return 0.9;
  if (diffDays <= 3) return 0.7;
  if (diffDays <= 7) return 0.4;
  return 0;
}

export interface DuplicateCheckInput {
  userId: string;
  amount: number;
  currency: string;
  date: string;
  merchant?: string;
  sourceImageHash?: string;
  ocrText?: string;
}

export interface DuplicateResult {
  isDuplicate: boolean;
  duplicateOfId?: string;
  score: number;
  action: 'auto_skip' | 'duplicate_candidate' | 'review' | 'none';
}

export type RecentTransaction = {
  id: string;
  amountOriginal: unknown;
  currencyOriginal: string | null;
  transactionDate: Date;
  merchant: string | null;
  sourceImageHash: string | null;
  ocrText: string | null;
};

/** If sourceImageHash is provided and matches an existing transaction, return auto_skip immediately. */
export async function findDuplicateByHash(
  userId: string,
  sourceImageHash: string
): Promise<DuplicateResult | null> {
  const existing = await prisma.transaction.findFirst({
    where: { userId, sourceImageHash },
    orderBy: { transactionDate: 'desc' },
    select: { id: true },
  });
  if (!existing) return null;
  return {
    isDuplicate: true,
    duplicateOfId: existing.id,
    score: 1,
    action: 'auto_skip',
  };
}

/** Single query to fetch recent transactions for batch duplicate checks. */
export async function getRecentTransactions(
  userId: string,
  limit = 500
): Promise<RecentTransaction[]> {
  return prisma.transaction.findMany({
    where: { userId },
    orderBy: { transactionDate: 'desc' },
    take: limit,
    select: {
      id: true,
      amountOriginal: true,
      currencyOriginal: true,
      transactionDate: true,
      merchant: true,
      sourceImageHash: true,
      ocrText: true,
    },
  }) as Promise<RecentTransaction[]>;
}

export interface BatchDuplicateInput {
  amount: number;
  currency: string;
  date: string;
  merchant?: string;
  ocrText?: string;
}

/** Score one input against recent transactions in memory; no DB call. */
function scoreAgainstRecent(
  input: BatchDuplicateInput,
  recent: RecentTransaction[]
): { bestScore: number; bestId?: string } {
  let bestScore = 0;
  let bestId: string | undefined;
  for (const t of recent) {
    const dateStr = t.transactionDate.toISOString().slice(0, 10);
    let score = 0;
    let weightSum = 0;
    score += WEIGHTS.amount * amountSimilarity(Number(t.amountOriginal), input.amount);
    weightSum += WEIGHTS.amount;
    score += WEIGHTS.currency * (input.currency === (t.currencyOriginal ?? '') ? 1 : 0);
    weightSum += WEIGHTS.currency;
    const m1 = input.merchant ?? '';
    const m2 = t.merchant ?? '';
    score += WEIGHTS.merchant * merchantSimilarity(m1, m2);
    weightSum += WEIGHTS.merchant;
    score += WEIGHTS.date * dateProximity(input.date, dateStr);
    weightSum += WEIGHTS.date;
    if (input.ocrText && t.ocrText) {
      score += WEIGHTS.ocrSimilarity * textSimilarity(input.ocrText, t.ocrText);
      weightSum += WEIGHTS.ocrSimilarity;
    }
    const normalizedScore = weightSum > 0 ? score / weightSum : 0;
    if (normalizedScore > bestScore) {
      bestScore = normalizedScore;
      bestId = t.id;
    }
  }
  return { bestScore, bestId };
}

/** For each input, compute duplicate result using pre-fetched recent list. */
export function checkDuplicateBatch(
  inputs: BatchDuplicateInput[],
  recent: RecentTransaction[]
): DuplicateResult[] {
  return inputs.map((input) => {
    const { bestScore, bestId } = scoreAgainstRecent(input, recent);
    if (bestScore >= AUTO_SKIP_THRESHOLD)
      return { isDuplicate: true, duplicateOfId: bestId, score: bestScore, action: 'auto_skip' };
    if (bestScore >= DUPLICATE_CANDIDATE_THRESHOLD)
      return { isDuplicate: true, duplicateOfId: bestId, score: bestScore, action: 'duplicate_candidate' };
    if (bestScore >= 0.5)
      return { isDuplicate: false, duplicateOfId: bestId, score: bestScore, action: 'review' };
    return { isDuplicate: false, score: bestScore, action: 'none' };
  });
}

export async function checkDuplicate(
  input: DuplicateCheckInput
): Promise<DuplicateResult> {
  if (input.sourceImageHash) {
    const byHash = await findDuplicateByHash(input.userId, input.sourceImageHash);
    if (byHash) return byHash;
  }
  const recent = await getRecentTransactions(input.userId);
  const [result] = checkDuplicateBatch(
    [
      {
        amount: input.amount,
        currency: input.currency,
        date: input.date,
        merchant: input.merchant,
        ocrText: input.ocrText,
      },
    ],
    recent
  );
  return result;
}
