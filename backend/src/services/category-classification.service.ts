/**
 * Category classification: rules first (keywords, merchant memory), AI fallback.
 * Returns category + confidence.
 */
import { getMerchantRule, type MerchantRuleLookup } from './merchant-memory.service.js';

const KEYWORD_RULES: { pattern: RegExp; category: string }[] = [
  { pattern: /\bnetflix|spotify|youtube\s*premium|apple\s*one\b/i, category: 'subscriptions' },
  { pattern: /\bbolt|uber|lyft|taxi\b/i, category: 'transport' },
  { pattern: /\bgrab\s*food|doordash|ubereats|delivery\b/i, category: 'food_delivery' },
  { pattern: /\bsupermarket|grocery|tesco|aldi|lidl\b/i, category: 'groceries' },
  { pattern: /\brestaurant|cafe|coffee|food\b/i, category: 'food' },
  { pattern: /\bpharmacy|hospital|clinic|health\b/i, category: 'health' },
  { pattern: /\bcinema|movie|game\s*pass\b/i, category: 'entertainment' },
  { pattern: /\bbill|electric|gas|water|utility\b/i, category: 'bills' },
  { pattern: /\bsalary|income|payment\s*received\b/i, category: 'income' },
  { pattern: /\bfee|charge|commission\b/i, category: 'fees' },
  { pattern: /\btransfer\b/i, category: 'transfers' },
];

const DEFAULT_CATEGORY = 'other';

export async function classifyCategory(
  userId: string,
  merchant: string | undefined,
  ocrSnippet?: string,
  preResolvedRule?: MerchantRuleLookup | null
): Promise<{ category: string; confidence: number }> {
  const text = [merchant, ocrSnippet].filter(Boolean).join(' ').toLowerCase();
  if (!text) return { category: DEFAULT_CATEGORY, confidence: 0.3 };

  const rule = preResolvedRule ?? (await getMerchantRule(userId, merchant ?? text));
  if (rule) return { category: rule.category, confidence: 0.95 };

  for (const { pattern, category } of KEYWORD_RULES) {
    if (pattern.test(text)) return { category, confidence: 0.85 };
  }

  return { category: DEFAULT_CATEGORY, confidence: 0.5 };
}
