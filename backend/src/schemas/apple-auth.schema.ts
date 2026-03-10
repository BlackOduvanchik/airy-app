import { z } from 'zod';

export const appleAuthBodySchema = z.object({
  identityToken: z.string().min(1, 'identityToken is required'),
  email: z.string().optional().transform((v) => (v && v.length > 0 ? v : undefined)),
});

export type AppleAuthBody = z.infer<typeof appleAuthBodySchema>;
