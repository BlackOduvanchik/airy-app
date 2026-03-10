import { z } from 'zod';

export const ALLOWED_CATEGORIES = [
  'other',
  'food',
  'groceries',
  'food_delivery',
  'transport',
  'subscriptions',
  'entertainment',
  'bills',
  'health',
  'fees',
  'transfers',
  'income',
] as const;

export const categorySchema = z
  .string()
  .max(64)
  .refine((v) => (ALLOWED_CATEGORIES as readonly string[]).includes(v), {
    message: `Category must be one of: ${ALLOWED_CATEGORIES.join(', ')}`,
  });

export const transactionTypeSchema = z.enum(['expense', 'income']);
export const sourceTypeSchema = z.enum(['manual', 'screenshot']);

export const createTransactionSchema = z.object({
  type: transactionTypeSchema,
  amountOriginal: z.number().positive(),
  currencyOriginal: z.string().length(3),
  amountBase: z.number().nonnegative(),
  baseCurrency: z.string().length(3),
  merchant: z.string().max(256).optional(),
  title: z.string().max(512).optional(),
  transactionDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  transactionTime: z.string().max(10).optional(),
  category: categorySchema.default('other'),
  subcategory: z.string().max(64).optional(),
  isSubscription: z.boolean().optional().default(false),
  comment: z.string().max(2000).optional(),
  sourceType: sourceTypeSchema.default('manual'),
});

export const updateTransactionSchema = createTransactionSchema.partial();

/** Optional overrides for confirming a pending transaction. */
export const confirmPendingBodySchema = createTransactionSchema.partial();

export const extractedTransactionSchema = createTransactionSchema.extend({
  confidence: z.number().min(0).max(1).optional(),
  ocrText: z.string().optional(),
  sourceImageHash: z.string().optional(),
});

export type CreateTransaction = z.infer<typeof createTransactionSchema>;
export type UpdateTransaction = z.infer<typeof updateTransactionSchema>;
export type ConfirmPendingBody = z.infer<typeof confirmPendingBodySchema>;
export type ExtractedTransaction = z.infer<typeof extractedTransactionSchema>;
