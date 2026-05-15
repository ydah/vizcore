const BASE_VERTICES = [
  [-1.0, -1.0, -1.0],
  [1.0, -1.0, -1.0],
  [1.0, 1.0, -1.0],
  [-1.0, 1.0, -1.0],
  [-1.0, -1.0, 1.0],
  [1.0, -1.0, 1.0],
  [1.0, 1.0, 1.0],
  [-1.0, 1.0, 1.0]
];

const EDGES = [
  [0, 1], [1, 2], [2, 3], [3, 0],
  [4, 5], [5, 6], [6, 7], [7, 4],
  [0, 4], [1, 5], [2, 6], [3, 7]
];

export const buildWireframeLines = ({ rotationY, rotationX, deform }) => {
  const amount = clamp(Number(deform || 0), 0, 1);
  const projected = BASE_VERTICES.map((vertex) => {
    const scaled = [
      vertex[0] * (1 + amount * 0.35),
      vertex[1] * (1 + amount * 0.2),
      vertex[2] * (1 + amount * 0.35)
    ];
    return projectVertex(scaled, rotationY, rotationX);
  });

  const lines = [];
  for (const [start, end] of EDGES) {
    lines.push(projected[start][0], projected[start][1]);
    lines.push(projected[end][0], projected[end][1]);
  }
  return lines;
};

export const estimateDeformFromSpectrum = (value) => {
  if (Array.isArray(value)) {
    if (value.length === 0) {
      return 0;
    }
    const sample = value.slice(0, Math.min(24, value.length));
    const sum = sample.reduce((total, entry) => total + Number(entry || 0), 0);
    return clamp(sum / sample.length, 0, 1);
  }
  return clamp(Number(value || 0), 0, 1);
};

export const buildRadialBlobLines = ({ time, params = {}, audio = {} }) => {
  const segments = clampInt(params.segments || 160, 24, 512);
  const baseRadius = clamp(Number(params.radius ?? 0.46), 0.05, 1.4);
  const wobble = clamp(Number(params.wobble ?? audio?.amplitude ?? 0), 0, 3);
  const spectrum = Array.isArray(params.spectrum) ? params.spectrum : Array.isArray(audio?.fft) ? audio.fft : [];
  const bass = clamp(Number(audio?.bands?.low || 0), 0, 1);
  const mid = clamp(Number(audio?.bands?.mid || 0), 0, 1);
  const pulse = clamp(Number(audio?.beat_pulse || (audio?.beat ? 1 : 0)), 0, 1);
  const points = [];

  const sample = (index) => {
    if (!spectrum.length) return 0;
    return clamp(Number(spectrum[index % spectrum.length] || 0), 0, 1);
  };

  for (let index = 0; index < segments; index += 1) {
    const next = (index + 1) % segments;
    appendRadialPoint(points, index, segments, baseRadius, wobble, bass, mid, pulse, time, sample(index));
    appendRadialPoint(points, next, segments, baseRadius, wobble, bass, mid, pulse, time, sample(next));
  }

  return points;
};

export const normalizeWaveformStyle = (value) => {
  const style = String(value || "line").trim().toLowerCase();
  if (style === "mirror" || style === "ribbon") return style;
  return "line";
};

export const buildWaveformLines = ({ time = 0, params = {}, audio = {} } = {}) => {
  const detail = clampInt(params.detail || 96, 16, 256);
  const height = clamp(finiteNumber(params.height ?? 0.46, 0.46), 0.05, 1.1);
  const amplitude = clamp(finiteNumber(audio?.amplitude, 0), 0, 1);
  const spectrum = Array.isArray(params.spectrum) ? params.spectrum : Array.isArray(audio?.fft) ? audio.fft : [];
  const style = normalizeWaveformStyle(params.style);
  const samples = buildWaveformSamples({ detail, height, amplitude, spectrum, time });
  const points = [];

  appendLineSegments(points, samples);

  if (style === "mirror" || style === "ribbon") {
    const mirrored = samples.map(([x, y]) => [x, -y]);
    appendLineSegments(points, mirrored);
  }

  if (style === "ribbon") {
    const stride = Math.max(4, Math.round(detail / 16));
    for (let index = 0; index < samples.length; index += stride) {
      const [x, y] = samples[index];
      points.push(x, y, x, -y);
    }
  }

  return points;
};

const buildWaveformSamples = ({ detail, height, amplitude, spectrum, time }) => {
  const samples = [];
  const safeTime = finiteNumber(time, 0);

  for (let index = 0; index < detail; index += 1) {
    const progress = detail === 1 ? 0 : index / (detail - 1);
    const x = -0.92 + progress * 1.84;
    const fftValue = sampleSpectrum(spectrum, progress);
    const carrier = Math.sin(index * 0.55 + safeTime * (2.4 + amplitude * 2.0));
    const harmonic = Math.sin(index * 0.13 + safeTime * 1.1);
    const energy = 0.12 + amplitude * 0.35 + fftValue * 0.55;
    const y = clamp((carrier * 0.72 + harmonic * 0.28) * energy * height, -0.92, 0.92);
    samples.push([x, y]);
  }

  return samples;
};

const appendLineSegments = (points, samples) => {
  for (let index = 1; index < samples.length; index += 1) {
    points.push(samples[index - 1][0], samples[index - 1][1], samples[index][0], samples[index][1]);
  }
};

const sampleSpectrum = (spectrum, progress) => {
  if (!spectrum.length) return 0;

  const position = progress * (spectrum.length - 1);
  const left = Math.floor(position);
  const right = Math.min(left + 1, spectrum.length - 1);
  const mix = position - left;
  const from = finiteNumber(spectrum[left], 0);
  const to = finiteNumber(spectrum[right], 0);
  return clamp(from + (to - from) * mix, 0, 1);
};

const appendRadialPoint = (points, index, segments, baseRadius, wobble, bass, mid, pulse, time, fftValue) => {
  const angle = (index / segments) * Math.PI * 2;
  const organic = Math.sin(angle * (3.0 + mid * 5.0) + time * (1.2 + bass * 2.0));
  const radius = baseRadius
    + bass * 0.14
    + pulse * 0.10
    + fftValue * (0.10 + wobble * 0.12)
    + organic * wobble * 0.035;

  points.push(Math.cos(angle) * radius, Math.sin(angle) * radius);
};

const projectVertex = (vertex, angleY, angleX) => {
  const [x, y, z] = vertex;

  const cosY = Math.cos(angleY);
  const sinY = Math.sin(angleY);
  const x1 = x * cosY - z * sinY;
  const z1 = x * sinY + z * cosY;

  const cosX = Math.cos(angleX);
  const sinX = Math.sin(angleX);
  const y1 = y * cosX - z1 * sinX;
  const z2 = y * sinX + z1 * cosX + 4.2;

  const perspectiveScale = 1.6 / z2;
  return [x1 * perspectiveScale, y1 * perspectiveScale];
};

const clampInt = (value, min, max) => {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) return min;
  return Math.round(Math.min(Math.max(numeric, min), max));
};

const finiteNumber = (value, fallback) => {
  const numeric = Number(value);
  return Number.isFinite(numeric) ? numeric : fallback;
};

const clamp = (value, min, max) => Math.min(Math.max(value, min), max);
