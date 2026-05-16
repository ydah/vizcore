const DEFAULT_SIZE = 64;
const HASH_OFFSET = 0x811c9dc5;
const HASH_PRIME = 0x01000193;

export const lineSegmentsFingerprint = (points, {
  width = DEFAULT_SIZE,
  height = DEFAULT_SIZE,
} = {}) => {
  const pixels = rasterizeLineSegments(points, { width, height });
  let hash = HASH_OFFSET;

  for (const value of pixels) {
    hash ^= value;
    hash = Math.imul(hash, HASH_PRIME) >>> 0;
  }

  return hash.toString(16).padStart(8, "0");
};

export const rasterizeLineSegments = (points, {
  width = DEFAULT_SIZE,
  height = DEFAULT_SIZE,
} = {}) => {
  const safeWidth = clampInt(width, 8, 512);
  const safeHeight = clampInt(height, 8, 512);
  const pixels = new Uint8Array(safeWidth * safeHeight);
  const input = Array.isArray(points) || ArrayBuffer.isView(points) ? Array.from(points) : [];

  for (let index = 0; index + 3 < input.length; index += 4) {
    const x1 = normalizedToPixel(input[index], safeWidth);
    const y1 = normalizedToPixel(-input[index + 1], safeHeight);
    const x2 = normalizedToPixel(input[index + 2], safeWidth);
    const y2 = normalizedToPixel(-input[index + 3], safeHeight);
    drawLine(pixels, safeWidth, safeHeight, x1, y1, x2, y2);
  }

  return pixels;
};

const drawLine = (pixels, width, height, x1, y1, x2, y2) => {
  const dx = Math.abs(x2 - x1);
  const dy = Math.abs(y2 - y1);
  const steps = Math.max(dx, dy, 1);

  for (let step = 0; step <= steps; step += 1) {
    const amount = step / steps;
    const x = Math.round(x1 + (x2 - x1) * amount);
    const y = Math.round(y1 + (y2 - y1) * amount);
    if (x < 0 || y < 0 || x >= width || y >= height) {
      continue;
    }
    pixels[y * width + x] = 255;
  }
};

const normalizedToPixel = (value, size) => {
  const normalized = (clamp(Number(value) || 0, -1, 1) + 1) * 0.5;
  return Math.round(normalized * (size - 1));
};

const clampInt = (value, min, max) => {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) return min;
  return Math.round(Math.min(Math.max(numeric, min), max));
};

const clamp = (value, min, max) => Math.min(Math.max(value, min), max);
