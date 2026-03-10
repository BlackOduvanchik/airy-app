# Airy Backend — API Contract

Base URL: `http://localhost:3000/api` (or your host). All authenticated routes accept either `Authorization: Bearer <jwt>` or `x-user-id: <userId>` (for local/mock).

## Auth

- **POST /api/auth/register-or-login**  
  Body: `{ "externalId": string, "email"?: string }`  
  Returns: `{ "token": string, "user": { "id", "email" } }`

## Transactions

- **POST /api/transactions/parse-screenshot**  
  Body: `{ "ocrText": string, "localHash"?: string, "baseCurrency"?: string }`  
  Returns: `{ "accepted", "duplicateSkipped", "pendingReview", "pendingIds", "errors" }`

- **POST /api/transactions/parse-screenshot/async**  
  Same body; returns `{ "queued": true }`. Job runs in background.

- **GET /api/transactions/pending**  
  Returns: `{ "pending": PendingTransaction[] }`

- **POST /api/transactions/pending/:id/confirm**  
  Confirms a pending transaction and creates a Transaction.

- **POST /api/transactions**  
  Body: CreateTransaction (type, amountOriginal, currencyOriginal, amountBase, baseCurrency, merchant?, title?, transactionDate, transactionTime?, category, subcategory?, isSubscription?, comment?, sourceType?)

- **PATCH /api/transactions/:id**  
  Body: partial UpdateTransaction

- **DELETE /api/transactions/:id**

- **GET /api/transactions?month=&year=**  
  Returns: `{ "transactions": Transaction[] }`

## Subscriptions

- **GET /api/subscriptions**  
  Returns: `{ "subscriptions": Subscription[] }`

## Analytics

- **GET /api/analytics/dashboard**  
  Returns: thisMonth (totalSpent, totalIncome, byCategory, transactionCount), previousMonthSpent, deltaPercent

- **GET /api/analytics/monthly?month=YYYY-MM**  
  Returns: yearMonth, totalSpent, totalIncome, byCategory, transactionCount

- **GET /api/analytics/yearly?year=YYYY**  
  Returns: year, totalSpent, totalIncome, topCategories, subscriptionTotal

## Insights (Pro)

- **GET /api/insights/monthly-summary?month=**  
  Returns: summary, details[], deltaPercent

- **GET /api/insights/behavioral**  
  Returns: InsightItem[]

## Export

- **GET /api/export/csv?from=&to=**  
  Returns: CSV file

- **GET /api/export/json?from=&to=**  
  Pro only. Returns: { exportedAt, count, transactions }

## Entitlements

- **GET /api/entitlements**  
  Returns: { monthly_ai_limit, unlimited_ai_analysis, advanced_insights, subscriptions_dashboard, yearly_review, export_extended, cloud_sync }

## Merchant memory

- **GET /api/merchant-rules**  
  Returns: MerchantRule[]

- **POST /api/merchant-rules**  
  Body: { merchantNormalized, category, subcategory?, isSubscription? }

- **DELETE /api/merchant-rules/:id**

## Health

- **GET /health**  
  Returns: `{ "ok": true }`
