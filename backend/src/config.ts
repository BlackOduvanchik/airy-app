/**
 * Central config from env. Validate on load.
 */
import { z } from 'zod';

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().default(3000),
  DATABASE_URL: z.string().min(1),
  REDIS_URL: z.string().default('redis://localhost:6379'),
  JWT_SECRET: z.string().min(16).optional(),
  ANTHROPIC_API_KEY: z.string().optional(),
  EXCHANGE_RATE_API_URL: z.string().url().default('https://api.frankfurter.app'),
  EXCHANGE_RATE_CACHE_TTL_SECONDS: z.coerce.number().default(3600),
  FREE_MONTHLY_AI_ANALYSES: z.coerce.number().default(10),
  MOCK_AI: z.string().transform((v) => v === 'true').default('false'),
  MOCK_EXCHANGE_RATES: z.string().transform((v) => v === 'true').default('false'),
  ALLOW_DEV_USER_HEADER: z
    .string()
    .optional()
    .transform((v) => v === 'true' || v === '1'),
  PRO_USER_IDS: z.string().optional(),
  ENABLE_PRO_FOR_ALL: z.string().transform((v) => v === 'true').default('false'),
  ALLOWED_ORIGINS: z.string().optional(),
  APPLE_BUNDLE_ID: z.string().optional(),
  APPLE_APP_STORE_CONNECT_KEY_ID: z.string().optional(),
  APPLE_APP_STORE_CONNECT_ISSUER_ID: z.string().optional(),
  APPLE_APP_STORE_CONNECT_PRIVATE_KEY: z.string().optional(),
  APPLE_APP_STORE_CONNECT_PRIVATE_KEY_PATH: z.string().optional(),
});

export type Config = z.infer<typeof envSchema> & { ALLOW_DEV_USER_HEADER: boolean };

function loadConfig(): Config {
  const parsed = envSchema.safeParse(process.env);
  if (!parsed.success) {
    console.error('Invalid env:', parsed.error.flatten());
    throw new Error('Config validation failed');
  }
  const data = parsed.data;
  const allowDevHeader =
    data.NODE_ENV === 'production' ? false : (data.ALLOW_DEV_USER_HEADER ?? true);
  if (data.NODE_ENV === 'production' && !data.JWT_SECRET) {
    throw new Error('JWT_SECRET is required in production');
  }
  return {
    ...data,
    ALLOW_DEV_USER_HEADER: allowDevHeader,
  } as Config;
}

export const config = loadConfig();
