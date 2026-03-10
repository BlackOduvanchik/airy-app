/**
 * OCR normalization: clean and normalize text from device OCR.
 * Deterministic only.
 */
export function normalizeOcrText(raw: string): string {
  return (
    raw
      .normalize('NFKC')
      .replace(/\r\n/g, '\n')
      .replace(/\r/g, '\n')
      .replace(/\t/g, ' ')
      .split('\n')
      .map((line) => line.trim().replace(/\s+/g, ' '))
      .filter(Boolean)
      .join('\n')
  );
}

export function linesFromNormalized(text: string): string[] {
  return text.split('\n').map((s) => s.trim()).filter(Boolean);
}
