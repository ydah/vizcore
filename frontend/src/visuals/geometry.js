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

const TETRAHEDRON_VERTICES = [
  [1, 1, 1],
  [-1, -1, 1],
  [-1, 1, -1],
  [1, -1, -1]
].map(([x, y, z]) => [x / Math.sqrt(3), y / Math.sqrt(3), z / Math.sqrt(3)]);

const TETRAHEDRON_EDGES = [
  [0, 1], [0, 2], [0, 3],
  [1, 2], [1, 3], [2, 3]
];

const OCTAHEDRON_VERTICES = [
  [1, 0, 0], [-1, 0, 0],
  [0, 1, 0], [0, -1, 0],
  [0, 0, 1], [0, 0, -1]
];

const OCTAHEDRON_EDGES = [
  [0, 2], [0, 3], [0, 4], [0, 5],
  [1, 2], [1, 3], [1, 4], [1, 5],
  [2, 4], [2, 5], [3, 4], [3, 5]
];

const PHI = (1 + Math.sqrt(5)) / 2;
const ICOSAHEDRON_SCALE = 1 / Math.sqrt(1 + PHI * PHI);
const ICOSAHEDRON_VERTICES = [
  [-1, PHI, 0], [1, PHI, 0], [-1, -PHI, 0], [1, -PHI, 0],
  [0, -1, PHI], [0, 1, PHI], [0, -1, -PHI], [0, 1, -PHI],
  [PHI, 0, -1], [PHI, 0, 1], [-PHI, 0, -1], [-PHI, 0, 1]
].map(([x, y, z]) => [x * ICOSAHEDRON_SCALE, y * ICOSAHEDRON_SCALE, z * ICOSAHEDRON_SCALE]);

const ICOSAHEDRON_EDGES = [
  [0, 1], [0, 5], [0, 7], [0, 10], [0, 11],
  [1, 5], [1, 7], [1, 8], [1, 9],
  [2, 3], [2, 4], [2, 6], [2, 10], [2, 11],
  [3, 4], [3, 6], [3, 8], [3, 9],
  [4, 5], [4, 9], [4, 11],
  [5, 9], [5, 11],
  [6, 7], [6, 8], [6, 10],
  [7, 8], [7, 10],
  [8, 9],
  [10, 11]
];

const MESH_PRESETS = {
  cube: { vertices: BASE_VERTICES.map(([x, y, z]) => [x * 0.62, y * 0.62, z * 0.62]), edges: EDGES },
  tetrahedron: { vertices: TETRAHEDRON_VERTICES, edges: TETRAHEDRON_EDGES },
  octahedron: { vertices: OCTAHEDRON_VERTICES, edges: OCTAHEDRON_EDGES },
  icosahedron: { vertices: ICOSAHEDRON_VERTICES, edges: ICOSAHEDRON_EDGES }
};

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

export const buildPresetMeshLines = ({ rotationY = 0, rotationX = 0, deform = 0, params = {} } = {}) => {
  const geometry = normalizeMeshGeometry(params.geometry);
  const mesh = MESH_PRESETS[geometry] || MESH_PRESETS.icosahedron;
  const scale = clamp(finiteNumber(params.scale, 1), 0.1, 3.0);
  const amount = clamp(finiteNumber(deform, 0), 0, 1);

  const projected = mesh.vertices.map((vertex, index) => {
    const radialPulse = 1 + amount * (0.12 + (index % 3) * 0.05);
    const twist = Math.sin(index * 1.618 + amount * Math.PI) * amount * 0.08;
    return projectVertex(
      [
        (vertex[0] + vertex[1] * twist) * scale * radialPulse,
        (vertex[1] + vertex[2] * twist) * scale * (1 + amount * 0.08),
        (vertex[2] + vertex[0] * twist) * scale * radialPulse
      ],
      rotationY,
      rotationX
    );
  });

  const lines = [];
  for (const [start, end] of mesh.edges) {
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

export const buildShapeLines = ({ params = {} } = {}) => {
  const shapes = Array.isArray(params.shapes) ? params.shapes : [];
  const points = [];

  shapes.forEach((shape) => {
    const kind = String(shape?.kind || shape?.type || "").toLowerCase();
    if (kind === "circle") {
      appendCircleShape(points, shape);
    } else if (kind === "line") {
      appendLineShape(points, shape);
    }
  });

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

const appendCircleShape = (points, shape) => {
  const count = clampInt(shape.count || 1, 1, 64);
  const segments = clampInt(shape.segments || 96, 12, 256);
  const radius = normalizeShapeRadius(shape.radius ?? 100);
  const x = normalizeShapeCoordinate(shape.x ?? 0, "x");
  const y = normalizeShapeCoordinate(shape.y ?? 0, "y");

  for (let ring = 0; ring < count; ring += 1) {
    const ringRadius = radius * ((ring + 1) / count);
    for (let index = 0; index < segments; index += 1) {
      appendCirclePoint(points, x, y, ringRadius, index, segments);
      appendCirclePoint(points, x, y, ringRadius, index + 1, segments);
    }
  }
};

const appendCirclePoint = (points, x, y, radius, index, segments) => {
  const angle = (index / segments) * Math.PI * 2;
  points.push(
    clamp(x + Math.cos(angle) * radius, -1.2, 1.2),
    clamp(y + Math.sin(angle) * radius, -1.2, 1.2)
  );
};

const appendLineShape = (points, shape) => {
  points.push(
    normalizeShapeCoordinate(shape.x1 ?? -0.8, "x"),
    normalizeShapeCoordinate(shape.y1 ?? 0, "y"),
    normalizeShapeCoordinate(shape.x2 ?? 0.8, "x"),
    normalizeShapeCoordinate(shape.y2 ?? 0, "y")
  );
};

const normalizeShapeRadius = (value) => {
  const numeric = finiteNumber(value, 100);
  const radius = Math.abs(numeric) <= 2 ? Math.abs(numeric) : Math.abs(numeric) / 360;
  return clamp(radius, 0.005, 1.4);
};

const normalizeShapeCoordinate = (value, axis) => {
  const numeric = finiteNumber(value, 0);
  if (Math.abs(numeric) <= 1.5) {
    return clamp(numeric, -1.2, 1.2);
  }

  if (axis === "y") {
    return clamp(1 - numeric / 360, -1.2, 1.2);
  }

  return clamp(numeric / 640 - 1, -1.2, 1.2);
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

const normalizeMeshGeometry = (value) => {
  return String(value || "icosahedron").trim().toLowerCase();
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
