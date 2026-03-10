/**
 * Currency conversion: fetch rates, convert to base. Cache in Redis.
 */
import { redis } from '../lib/redis.js';
import { config } from '../config.js';
import { logger } from '../lib/logger.js';
import { withRetry } from '../lib/retry.js';

const CACHE_PREFIX = 'airy:rates:';
const RATES_KEY = (date: string) => `${CACHE_PREFIX}${date}`;

interface RatesResponse {
  rates?: Record<string, number>;
  base?: string;
}

export async function getRates(baseCurrency: string): Promise<Record<string, number>> {
  const date = new Date().toISOString().slice(0, 10);
  const cacheKey = RATES_KEY(`${baseCurrency}:${date}`);
  const cached = await redis.get(cacheKey);
  if (cached) return JSON.parse(cached) as Record<string, number>;

  if (config.MOCK_EXCHANGE_RATES) {
    const mock: Record<string, number> = { USD: 1, EUR: 0.92, GBP: 0.79 };
    await redis.setex(cacheKey, config.EXCHANGE_RATE_CACHE_TTL_SECONDS, JSON.stringify(mock));
    return mock;
  }

  try {
    const url = `${config.EXCHANGE_RATE_API_URL}/latest?from=${baseCurrency}`;
    const res = await withRetry(
      async () => {
        const r = await fetch(url);
        if (!r.ok) throw new Error(`Rates API ${r.status}`);
        return r;
      },
      { attempts: 2, delayMs: 300 }
    );
    const data = (await res.json()) as RatesResponse;
    const rates = data.rates ?? { [baseCurrency]: 1 };
    await redis.setex(cacheKey, config.EXCHANGE_RATE_CACHE_TTL_SECONDS, JSON.stringify(rates));
    return rates;
  } catch (e) {
    logger.warn({ err: e }, 'Exchange rate fetch failed');
    return { [baseCurrency]: 1 };
  }
}

export async function convert(
  amount: number,
  fromCurrency: string,
  toCurrency: string
): Promise<number> {
  if (fromCurrency === toCurrency) return amount;
  const rates = await getRates(fromCurrency);
  const rate = rates[toCurrency];
  if (!rate) return amount;
  return Math.round(amount * rate * 10000) / 10000;
}
