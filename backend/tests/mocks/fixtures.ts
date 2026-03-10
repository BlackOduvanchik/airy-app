/**
 * Mock fixtures for local development and tests.
 */
export const MOCK_OCR_TEXT = `
Netflix 12.99 USD 2025-03-01
Spotify 9.99 USD 2025-03-02
Bolt 5.50 EUR 2025-03-03 14:22
`;

export const MOCK_USER = {
  id: 'clxx',
  email: 'demo@airy.app',
  externalId: 'demo-device-1',
};

export const MOCK_ENTITLEMENTS_FREE = {
  monthly_ai_limit: 10,
  unlimited_ai_analysis: false,
  advanced_insights: false,
  subscriptions_dashboard: false,
  yearly_review: false,
  export_extended: false,
  cloud_sync: false,
};

export const MOCK_ENTITLEMENTS_PRO = {
  monthly_ai_limit: 999999,
  unlimited_ai_analysis: true,
  advanced_insights: true,
  subscriptions_dashboard: true,
  yearly_review: true,
  export_extended: true,
  cloud_sync: true,
};
