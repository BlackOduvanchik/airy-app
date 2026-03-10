import { z } from 'zod';

/**
 * Payload from iOS app: OCR text + metadata. No raw image required (privacy-first).
 */
export const ocrPayloadSchema = z.object({
  ocrText: z.string().min(1).max(50000),
  localHash: z.string().optional(), // client-side image/perceptual hash for duplicate detection
  imageFingerprint: z.string().optional(),
  locale: z.string().optional().default('en'),
  source: z.enum(['camera', 'photo_library']).optional(),
});

export type OcrPayload = z.infer<typeof ocrPayloadSchema>;
