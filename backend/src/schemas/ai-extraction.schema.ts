import { z } from 'zod';

/**
 * Strict JSON schema for AI extraction responses. No freeform text.
 */
export const aiExtractedTransactionSchema = z.object({
  type: z.enum(['expense', 'income']),
  amountOriginal: z.number(),
  currencyOriginal: z.string().length(3),
  merchant: z.string().optional(),
  title: z.string().optional(),
  transactionDate: z.string(), // YYYY-MM-DD
  transactionTime: z.string().optional(),
  category: z.string(),
  subcategory: z.string().optional(),
  isSubscriptionLikely: z.boolean().optional(),
  confidence: z.number().min(0).max(1),
  confidencePerField: z
    .object({
      amount: z.number().optional(),
      date: z.number().optional(),
      merchant: z.number().optional(),
      category: z.number().optional(),
    })
    .optional(),
});

export const aiExtractionResponseSchema = z.object({
  transactions: z.array(aiExtractedTransactionSchema),
  overallConfidence: z.number().min(0).max(1).optional(),
});

export type AiExtractedTransaction = z.infer<typeof aiExtractedTransactionSchema>;
export type AiExtractionResponse = z.infer<typeof aiExtractionResponseSchema>;
