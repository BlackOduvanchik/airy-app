/**
 * Deterministic transaction parser: extract amounts, dates, currencies, merchants from OCR text.
 * Supports one or multiple transactions per block of text.
 */
import { normalizeOcrText, linesFromNormalized } from './ocr-normalize.service.js';

export interface ParsedItem {
  /** Absolute amount (positive number). */
  amount: number;
  /** True if the parsed amount was negative or line suggests credit/refund. */
  isCredit?: boolean;
  currency: string;
  date: string; // YYYY-MM-DD
  time?: string;
  merchant?: string;
  rawLine?: string;
}

const CURRENCY_SYMBOLS: Record<string, string> = {
  $: 'USD',
  '€': 'EUR',
  '£': 'GBP',
  '¥': 'JPY',
};
const CURRENCY_CODES = new Set(['USD', 'EUR', 'GBP', 'JPY', 'CAD', 'AUD', 'CHF', 'PLN', 'UAH']);

const AMOUNT_REGEX = /([-+]?\s*\d{1,3}(?:[.,]\d{3})*(?:[.,]\d{2})?|\d+[.,]\d{2})\s*([A-Z]{3}|[$€£¥])?/g;
const DATE_REGEX = /(\d{1,4})[-./](\d{1,2})[-./](\d{1,4})|(\d{1,2})[-./](\d{1,2})[-./](\d{2,4})/g;

function parseAmountFromLine(line: string): { amount: number; isCredit: boolean; currency: string } | null {
  const match = line.match(/([-+]?\s*\d{1,3}(?:[.,]\d{3})*(?:[.,]\d{2})?|\d+[.,]\d{2})\s*([A-Z]{3}|[$€£¥])?/);
  if (!match) return null;
  const amountStr = match[1].replace(/\s/g, '').replace(',', '.');
  const amountRaw = parseFloat(amountStr);
  if (Number.isNaN(amountRaw)) return null;
  const amount = Math.abs(amountRaw);
  const isCredit = amountRaw < 0;
  let currency = 'USD';
  if (match[2]) {
    currency = CURRENCY_SYMBOLS[match[2]] ?? (CURRENCY_CODES.has(match[2]) ? match[2] : 'USD');
  }
  return { amount, isCredit, currency };
}

function parseDateFromLine(line: string): string | null {
  const match = line.match(/(\d{1,4})[-./](\d{1,2})[-./](\d{1,4})/);
  if (!match) return null;
  let y: number, m: number, d: number;
  if (match[1].length === 4) {
    y = parseInt(match[1], 10);
    m = parseInt(match[2], 10);
    d = parseInt(match[3], 10);
  } else {
    d = parseInt(match[1], 10);
    m = parseInt(match[2], 10);
    y = parseInt(match[3], 10);
    if (y < 100) y += 2000;
  }
  if (y < 1900 || y > 2100 || m < 1 || m > 12 || d < 1 || d > 31) return null;
  return `${y}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
}

function parseTimeFromLine(line: string): string | undefined {
  const match = line.match(/(\d{1,2}):(\d{2})(?::(\d{2}))?/);
  if (!match) return undefined;
  return `${match[1].padStart(2, '0')}:${match[2].padStart(2, '0')}`;
}

/**
 * Extract all transaction-like items from normalized OCR text.
 * Each "block" is a group of consecutive lines; we look for amount + date to form one transaction.
 */
export function parseTransactionsFromOcr(ocrText: string): ParsedItem[] {
  const normalized = normalizeOcrText(ocrText);
  const lines = linesFromNormalized(normalized);
  const results: ParsedItem[] = [];
  let i = 0;

  while (i < lines.length) {
    const line = lines[i];
    const amountInfo = parseAmountFromLine(line);
    if (!amountInfo) {
      i++;
      continue;
    }
    const date = parseDateFromLine(line) ?? (i > 0 ? parseDateFromLine(lines[i - 1]) : null);
    const time = parseTimeFromLine(line);
    const merchant = line
      .replace(AMOUNT_REGEX, '')
      .replace(DATE_REGEX, '')
      .replace(/\d{1,2}:\d{2}/, '')
      .trim()
      .slice(0, 256) || undefined;

    const parsedDate = date ?? new Date().toISOString().slice(0, 10);
    const refundLike = /\b(refund|credit|reversal|reimbursement)\b/i.test(line);
    results.push({
      amount: amountInfo.amount,
      isCredit: amountInfo.isCredit || refundLike,
      currency: amountInfo.currency,
      date: parsedDate,
      time,
      merchant: merchant || undefined,
      rawLine: line,
    });
    i++;
  }

  return results;
}
