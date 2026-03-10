import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

const DEFAULT_CATEGORIES = [
  'food',
  'food_delivery',
  'groceries',
  'transport',
  'subscriptions',
  'entertainment',
  'shopping',
  'health',
  'beauty',
  'travel',
  'bills',
  'work_tools',
  'fees',
  'transfers',
  'income',
  'other',
];

async function main() {
  // Create demo user for mock mode
  const user = await prisma.user.upsert({
    where: { email: 'demo@airy.app' },
    update: {},
    create: {
      email: 'demo@airy.app',
      externalId: 'demo-device-1',
    },
  });

  // Seed is minimal; categories are app-level constants. Optionally add demo transactions:
  const baseDate = new Date();
  baseDate.setMonth(baseDate.getMonth() - 1);
  await prisma.transaction.createMany({
    data: [
      {
        userId: user.id,
        type: 'expense',
        amountOriginal: 12.5,
        currencyOriginal: 'USD',
        amountBase: 12.5,
        baseCurrency: 'USD',
        merchant: 'Netflix',
        transactionDate: baseDate,
        category: 'subscriptions',
        sourceType: 'manual',
        isSubscription: true,
      },
      {
        userId: user.id,
        type: 'expense',
        amountOriginal: 8.99,
        currencyOriginal: 'USD',
        amountBase: 8.99,
        baseCurrency: 'USD',
        merchant: 'Spotify',
        transactionDate: baseDate,
        category: 'subscriptions',
        sourceType: 'manual',
        isSubscription: true,
      },
    ],
    skipDuplicates: true,
  });

  console.log('Seed done. Demo user:', user.id);
}

main()
  .then(() => prisma.$disconnect())
  .catch((e) => {
    console.error(e);
    prisma.$disconnect();
    process.exit(1);
  });
