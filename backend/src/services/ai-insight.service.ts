/**
 * AI insight engine: Money Mirror, monthly summary, anomaly. Structured JSON only; grounded in computed metrics.
 */
import Anthropic from '@anthropic-ai/sdk';
import { config } from '../config.js';
import { getMonthlyAggregate, getDashboardData } from './analytics.service.js';
import { format, subMonths } from 'date-fns';
import { redis } from '../lib/redis.js';
import { logger } from '../lib/logger.js';
import { recordAiUsage } from '../observability/metrics.js';

const INSIGHT_CACHE_PREFIX = 'airy:insights:';
const CACHE_TTL = 60 * 60; // 1 hour

export async function invalidateInsightsCache(userId: string): Promise<void> {
  const keys = await redis.keys(`${INSIGHT_CACHE_PREFIX}${userId}:*`);
  if (keys.length > 0) await redis.del(...keys);
}

export interface InsightItem {
  type: string;
  title: string;
  body: string;
  metricRef?: string;
}

const EXTRACTION_SCHEMA = `You must respond with valid JSON only, no markdown or explanation. Schema:
{ "insights": [ { "type": string, "title": string, "body": string, "metricRef": string (optional) } ] }
Keep each insight short (1-2 sentences). Be specific and use the numbers provided.`;

export async function getMonthlySummary(userId: string, yearMonth?: string): Promise<{
  summary: string;
  details: string[];
  deltaPercent: number;
}> {
  const ym = yearMonth ?? format(new Date(), 'yyyy-MM');
  const prev = format(subMonths(new Date(ym + '-01'), 1), 'yyyy-MM');
  const current = await getMonthlyAggregate(userId, ym);
  const previous = await getMonthlyAggregate(userId, prev);
  const delta =
    previous.totalSpent > 0
      ? ((current.totalSpent - previous.totalSpent) / previous.totalSpent) * 100
      : 0;

  const details: string[] = [];
  const allCategories = new Set([
    ...Object.keys(current.byCategory),
    ...Object.keys(previous.byCategory),
  ]);
  for (const cat of allCategories) {
    const curr = current.byCategory[cat] ?? 0;
    const prevVal = previous.byCategory[cat] ?? 0;
    if (prevVal === 0 && curr === 0) continue;
    const pct =
      prevVal > 0 ? Math.round(((curr - prevVal) / prevVal) * 100) : (curr ? 100 : 0);
    details.push(`${cat} ${pct >= 0 ? '+' : ''}${pct}%`);
  }

  let summary = `You spent ${delta >= 0 ? delta.toFixed(0) : Math.abs(delta).toFixed(0)}% ${delta >= 0 ? 'more' : 'less'} than last month.`;
  if (config.MOCK_AI) return { summary, details, deltaPercent: delta };

  try {
    const anthropic = new Anthropic({ apiKey: config.ANTHROPIC_API_KEY });
    const response = await anthropic.messages.create({
      model: 'claude-sonnet-4-20250514',
      max_tokens: 200,
      messages: [
        {
          role: 'user',
          content: `Write one short sentence (max 15 words) summarizing this spending: total this month ${current.totalSpent}, last month ${previous.totalSpent}, change ${delta.toFixed(0)}%. Category changes: ${details.slice(0, 5).join(', ')}. Reply with JSON: { "summary": "your sentence" }`,
        },
      ],
    });
    const text = response.content[0].type === 'text' ? response.content[0].text : '';
    const parsed = JSON.parse(text.replace(/```json?\s*|\s*```/g, '').trim());
    if (parsed.summary) summary = parsed.summary;
    recordAiUsage({ userId, feature: 'monthly_summary' });
  } catch (e) {
    logger.warn({ err: e }, 'AI summary failed');
  }
  return { summary, details, deltaPercent: delta };
}

export async function getBehavioralInsights(userId: string): Promise<InsightItem[]> {
  const cacheKey = `${INSIGHT_CACHE_PREFIX}${userId}:${format(new Date(), 'yyyy-MM')}`;
  const cached = await redis.get(cacheKey);
  if (cached) return JSON.parse(cached) as InsightItem[];

  const dashboard = await getDashboardData(userId);
  const insights: InsightItem[] = [];

  if (dashboard.deltaPercent > 20) {
    insights.push({
      type: 'trend',
      title: 'Spending increase',
      body: `You spent ${dashboard.deltaPercent}% more this month than last month.`,
      metricRef: 'month_over_month',
    });
  } else if (dashboard.deltaPercent < -10) {
    insights.push({
      type: 'trend',
      title: 'Spending decrease',
      body: `You spent ${Math.abs(dashboard.deltaPercent)}% less this month.`,
      metricRef: 'month_over_month',
    });
  }

  const topCategory = Object.entries(dashboard.thisMonth.byCategory).sort(
    (a, b) => b[1] - a[1]
  )[0];
  if (topCategory) {
    insights.push({
      type: 'category',
      title: 'Top category',
      body: `Most spending was on ${topCategory[0]} (${topCategory[1].toFixed(0)} in base currency).`,
      metricRef: topCategory[0],
    });
  }

  if (config.MOCK_AI) {
    await redis.setex(cacheKey, CACHE_TTL, JSON.stringify(insights));
    return insights;
  }

  try {
    const anthropic = new Anthropic({ apiKey: config.ANTHROPIC_API_KEY });
    const response = await anthropic.messages.create({
      model: 'claude-sonnet-4-20250514',
      max_tokens: 500,
      messages: [
        {
          role: 'user',
          content: `Given these metrics, generate 1-3 short behavioral insights. Metrics: total spent this month ${dashboard.thisMonth.totalSpent}, vs last month delta ${dashboard.deltaPercent}%. Category breakdown: ${JSON.stringify(dashboard.thisMonth.byCategory)}. ${EXTRACTION_SCHEMA}`,
        },
      ],
    });
    const text = response.content[0].type === 'text' ? response.content[0].text : '';
    const parsed = JSON.parse(text.replace(/```json?\s*|\s*```/g, '').trim());
    if (parsed.insights?.length) {
      insights.push(...parsed.insights.slice(0, 3));
      recordAiUsage({ userId, feature: 'behavioral_insights' });
    }
  } catch (e) {
    logger.warn({ err: e }, 'AI insights failed');
  }

  await redis.setex(cacheKey, CACHE_TTL, JSON.stringify(insights));
  return insights;
}

export interface AnomalyItem {
  category: string;
  currentAmount: number;
  averageAmount: number;
  ratio: number;
}

const ANOMALY_MONTHS = 5;
const ANOMALY_RATIO_THRESHOLD = 2;

/** Category spend vs rolling average; flag where current month spend > 2× average. */
export async function getAnomalies(
  userId: string,
  yearMonth?: string
): Promise<AnomalyItem[]> {
  const ym = yearMonth ?? format(new Date(), 'yyyy-MM');
  const [y, m] = ym.split('-').map(Number);
  const currentStart = new Date(y, m - 1, 1);
  const currentEnd = new Date(y, m, 0, 23, 59, 59);
  const current = await getMonthlyAggregate(userId, ym);
  const byCategoryCurrent = current.byCategory ?? {};
  const categoryTotalsByMonth: Record<string, number[]> = {};
  for (let i = 1; i <= ANOMALY_MONTHS; i++) {
    const prev = subMonths(currentStart, i);
    const prevYm = format(prev, 'yyyy-MM');
    const prevAgg = await getMonthlyAggregate(userId, prevYm);
    const byCat = prevAgg.byCategory ?? {};
    for (const [cat, amount] of Object.entries(byCat)) {
      if (!categoryTotalsByMonth[cat]) categoryTotalsByMonth[cat] = [];
      categoryTotalsByMonth[cat].push(amount);
    }
  }
  const anomalies: AnomalyItem[] = [];
  for (const [category, currentAmount] of Object.entries(byCategoryCurrent)) {
    const pastAmounts = categoryTotalsByMonth[category] ?? [];
    const averageAmount =
      pastAmounts.length > 0
        ? pastAmounts.reduce((a, b) => a + b, 0) / pastAmounts.length
        : 0;
    if (averageAmount > 0 && currentAmount > ANOMALY_RATIO_THRESHOLD * averageAmount) {
      anomalies.push({
        category,
        currentAmount,
        averageAmount,
        ratio: currentAmount / averageAmount,
      });
    }
  }
  return anomalies;
}

export interface MoneyMirrorResponse {
  behavioral: InsightItem[];
  anomalies: AnomalyItem[];
  summary?: string;
}

const MONEY_MIRROR_CACHE_PREFIX = 'airy:insights:';

/** Single Money Mirror API: behavioral insights + anomalies + optional AI summary. */
export async function getMoneyMirror(
  userId: string,
  yearMonth?: string
): Promise<MoneyMirrorResponse> {
  const month = yearMonth ?? format(new Date(), 'yyyy-MM');
  const cacheKey = `${MONEY_MIRROR_CACHE_PREFIX}${userId}:money_mirror:${month}`;
  const cached = await redis.get(cacheKey);
  if (cached) return JSON.parse(cached) as MoneyMirrorResponse;

  const [behavioral, anomalies] = await Promise.all([
    getBehavioralInsights(userId),
    getAnomalies(userId, month),
  ]);

  let summary: string | undefined;
  if (!config.MOCK_AI && config.ANTHROPIC_API_KEY && (behavioral.length > 0 || anomalies.length > 0)) {
    try {
      const anthropic = new Anthropic({ apiKey: config.ANTHROPIC_API_KEY });
      const response = await anthropic.messages.create({
        model: 'claude-sonnet-4-20250514',
        max_tokens: 120,
        messages: [
          {
            role: 'user',
            content: `One short "Money Mirror" reflection sentence (max 20 words) for a user with these insights: ${JSON.stringify(behavioral.slice(0, 2))}. Anomalies: ${JSON.stringify(anomalies)}. Reply with JSON: { "summary": "sentence" }`,
          },
        ],
      });
      const text = response.content[0].type === 'text' ? response.content[0].text : '';
      const parsed = JSON.parse(text.replace(/```json?\s*|\s*```/g, '').trim());
      if (parsed.summary) summary = parsed.summary;
    } catch (e) {
      logger.warn({ err: e }, 'Money Mirror summary failed');
    }
  }

  const result: MoneyMirrorResponse = { behavioral, anomalies, summary };
  await redis.setex(cacheKey, CACHE_TTL, JSON.stringify(result));
  return result;
}

export interface YearlyReviewResponse {
  aggregate: {
    year: number;
    totalSpent: number;
    totalIncome: number;
    topCategories: { category: string; amount: number }[];
    subscriptionTotal: number;
  };
  narrative: string;
}

/** AI-generated short "year in review" paragraph for yearly aggregate. */
export async function getYearlyReview(
  userId: string,
  year: number
): Promise<YearlyReviewResponse> {
  const cacheKey = `${INSIGHT_CACHE_PREFIX}${userId}:yearly_review:${year}`;
  const cached = await redis.get(cacheKey);
  if (cached) return JSON.parse(cached) as YearlyReviewResponse;

  const { getYearlyAggregate } = await import('./analytics.service.js');
  const aggregate = await getYearlyAggregate(userId, year);

  let narrative = `In ${year} you spent ${aggregate.totalSpent.toFixed(0)} and earned ${aggregate.totalIncome.toFixed(0)}.`;
  if (!config.MOCK_AI && config.ANTHROPIC_API_KEY) {
    try {
      const anthropic = new Anthropic({ apiKey: config.ANTHROPIC_API_KEY });
      const response = await anthropic.messages.create({
        model: 'claude-sonnet-4-20250514',
        max_tokens: 200,
        messages: [
          {
            role: 'user',
            content: `Write one short paragraph (2-4 sentences, "year in review") for this user's spending in ${year}. Total spent: ${aggregate.totalSpent}. Total income: ${aggregate.totalIncome}. Top categories: ${JSON.stringify(aggregate.topCategories.slice(0, 5))}. Reply with JSON: { "narrative": "your paragraph" }`,
          },
        ],
      });
      const text = response.content[0].type === 'text' ? response.content[0].text : '';
      const parsed = JSON.parse(text.replace(/```json?\s*|\s*```/g, '').trim());
      if (parsed.narrative) narrative = parsed.narrative;
    } catch (e) {
      logger.warn({ err: e }, 'Yearly review AI failed');
    }
  }

  const result: YearlyReviewResponse = { aggregate, narrative };
  await redis.setex(cacheKey, CACHE_TTL, JSON.stringify(result));
  return result;
}
