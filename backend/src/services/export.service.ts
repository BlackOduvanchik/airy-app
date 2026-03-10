/**
 * Export service: CSV and JSON generation from user transactions. Supports pagination.
 */
import { prisma } from '../lib/prisma.js';
import { format } from 'date-fns';

const EXPORT_MAX_PAGE_SIZE = 5000;

export interface ExportPageOptions {
  from?: Date;
  to?: Date;
  limit?: number;
  cursor?: string;
}

export interface ExportPageResult<T> {
  data: T;
  nextCursor: string | null;
  hasMore: boolean;
}

function buildWhere(userId: string, from?: Date, to?: Date) {
  const where: { userId: string; transactionDate?: object } = { userId };
  if (from || to) {
    where.transactionDate = {} as object;
    if (from) (where.transactionDate as Record<string, Date>).gte = from;
    if (to) (where.transactionDate as Record<string, Date>).lte = to;
  }
  return where;
}

export async function exportCsv(
  userId: string,
  from?: Date,
  to?: Date,
  options?: { limit?: number; cursor?: string }
): Promise<string | { csv: string; nextCursor: string | null; hasMore: boolean }> {
  const limit = options?.limit != null ? Math.min(options.limit, EXPORT_MAX_PAGE_SIZE) : undefined;
  const where = buildWhere(userId, from, to);
  const txs = await prisma.transaction.findMany({
    where,
    orderBy: [{ transactionDate: 'desc' }, { id: 'desc' }],
    ...(limit != null && { take: limit + 1 }),
    ...(options?.cursor && { cursor: { id: options.cursor }, skip: 1 }),
  });
  const hasMore = limit != null && txs.length > limit;
  const rows = hasMore ? txs.slice(0, limit) : txs;
  const headers = [
    'id',
    'type',
    'amountOriginal',
    'currencyOriginal',
    'amountBase',
    'baseCurrency',
    'merchant',
    'title',
    'transactionDate',
    'category',
    'subcategory',
    'isSubscription',
    'comment',
    'sourceType',
    'createdAt',
  ];
  const csvRows = rows.map((t) =>
    headers.map((h) => {
      const v = (t as Record<string, unknown>)[h];
      if (v instanceof Date) return format(v, 'yyyy-MM-dd');
      if (typeof v === 'string' && v.includes(',')) return `"${v}"`;
      return String(v ?? '');
    }).join(',')
  );
  const csv = [headers.join(','), ...csvRows].join('\n');
  if (options?.limit != null || options?.cursor) {
    const nextCursor = hasMore && rows.length > 0 ? rows[rows.length - 1].id : null;
    return { csv, nextCursor, hasMore };
  }
  return csv;
}

export async function exportJson(
  userId: string,
  from?: Date,
  to?: Date,
  options?: { limit?: number; cursor?: string }
): Promise<ExportPageResult<object>> {
  const limit = options?.limit != null ? Math.min(options.limit, EXPORT_MAX_PAGE_SIZE) : undefined;
  const where = buildWhere(userId, from, to);
  const txs = await prisma.transaction.findMany({
    where,
    orderBy: [{ transactionDate: 'desc' }, { id: 'desc' }],
    ...(limit != null && { take: limit + 1 }),
    ...(options?.cursor && { cursor: { id: options.cursor }, skip: 1 }),
  });
  const hasMore = limit != null && txs.length > limit;
  const page = hasMore ? txs.slice(0, limit) : txs;
  const nextCursor = hasMore && page.length > 0 ? page[page.length - 1].id : null;
  return {
    data: {
      exportedAt: new Date().toISOString(),
      count: page.length,
      transactions: page.map((t) => ({
        ...t,
        amountOriginal: Number(t.amountOriginal),
        amountBase: Number(t.amountBase),
        confidence: t.confidence ? Number(t.confidence) : null,
        transactionDate: format(t.transactionDate, 'yyyy-MM-dd'),
        createdAt: t.createdAt.toISOString(),
        updatedAt: t.updatedAt.toISOString(),
      })),
    },
    nextCursor,
    hasMore: hasMore ?? false,
  };
}

export { EXPORT_MAX_PAGE_SIZE };
