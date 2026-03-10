/**
 * Retry with exponential backoff for external calls.
 */
export async function withRetry<T>(
  fn: () => Promise<T>,
  options?: { attempts?: number; delayMs?: number }
): Promise<T> {
  const attempts = options?.attempts ?? 3;
  const delayMs = options?.delayMs ?? 500;
  let lastErr: Error | undefined;
  for (let i = 0; i < attempts; i++) {
    try {
      return await fn();
    } catch (e) {
      lastErr = e instanceof Error ? e : new Error(String(e));
      if (i < attempts - 1) {
        const wait = delayMs * Math.pow(2, i);
        await new Promise((r) => setTimeout(r, wait));
      }
    }
  }
  throw lastErr;
}
