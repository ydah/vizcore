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

const clamp = (value, min, max) => Math.min(Math.max(value, min), max);
