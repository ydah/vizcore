import { describeSvgArc, svgArcPoint, svgArcSegmentCount } from "./svg-arc.js";

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
const SHAPE_HALF_WIDTH = 640;
const SHAPE_HALF_HEIGHT = 360;

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
  const context = shapeCoordinateContext(params);
  const points = [];

  shapes.forEach((shape) => {
    const kind = String(shape?.kind || shape?.type || "").toLowerCase();
    if (kind === "circle") {
      appendCircleShape(points, shape, context);
    } else if (kind === "line") {
      appendLineShape(points, shape, context);
    } else if (kind === "rect") {
      appendRectShape(points, shape, context);
    } else if (kind === "polygon" || kind === "polyline") {
      appendPolygonShape(points, shape, context, kind === "polygon");
    } else if (kind === "path") {
      appendPathShape(points, shape, context);
    } else if (kind === "star") {
      appendStarShape(points, shape, context);
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

const appendCircleShape = (points, shape, context) => {
  const count = clampInt(shape.count || 1, 1, 64);
  const segments = clampInt(shape.segments || 96, 12, 256);
  const radius = normalizeShapeLength(shape.radius ?? 100, context, "radius");
  const center = normalizeShapePoint(shape.x ?? 0, shape.y ?? 0, context);

  for (let ring = 0; ring < count; ring += 1) {
    const ringRadius = radius * ((ring + 1) / count);
    for (let index = 0; index < segments; index += 1) {
      appendSegment(
        points,
        circlePoint(center, ringRadius, index, segments),
        circlePoint(center, ringRadius, index + 1, segments),
        shape,
        context
      );
    }
  }
};

const circlePoint = (center, radius, index, segments) => {
  const angle = (index / segments) * Math.PI * 2;
  return [center[0] + Math.cos(angle) * radius, center[1] + Math.sin(angle) * radius];
};

const appendLineShape = (points, shape, context) => {
  const [x1, y1, x2, y2] = lineDefaults(context);
  appendSegment(
    points,
    normalizeShapePoint(shape.x1 ?? x1, shape.y1 ?? y1, context),
    normalizeShapePoint(shape.x2 ?? x2, shape.y2 ?? y2, context),
    shape,
    context
  );
};

const appendRectShape = (points, shape, context) => {
  const center = normalizeShapePoint(shape.x ?? 0, shape.y ?? 0, context);
  const halfWidth = normalizeShapeLength(shape.width ?? 100, context, "x") / 2;
  const halfHeight = normalizeShapeLength(shape.height ?? 100, context, "y") / 2;
  const vertices = [
    [center[0] - halfWidth, center[1] - halfHeight],
    [center[0] + halfWidth, center[1] - halfHeight],
    [center[0] + halfWidth, center[1] + halfHeight],
    [center[0] - halfWidth, center[1] + halfHeight]
  ];

  appendPolylineSegments(points, vertices, shape, context, true);
};

const appendPolygonShape = (points, shape, context, defaultClosed) => {
  const vertices = normalizeShapePoints(shape.points, context);
  if (vertices.length < (defaultClosed ? 3 : 2)) {
    return;
  }

  appendPolylineSegments(points, vertices, shape, context, shape.closed ?? defaultClosed);
};

const appendStarShape = (points, shape, context) => {
  const tips = clampInt(shape.points || 5, 3, 128);
  const center = normalizeShapePoint(shape.x ?? 0, shape.y ?? 0, context);
  const radius = normalizeShapeLength(shape.radius ?? 100, context, "radius");
  const innerRadius = normalizeShapeLength(shape.inner_radius ?? radiusToRawHalf(shape.radius ?? 100), context, "radius");
  const rotation = (finiteNumber(shape.rotation, -90) / 180) * Math.PI;
  const vertices = [];

  for (let index = 0; index < tips * 2; index += 1) {
    const angle = rotation + (index / (tips * 2)) * Math.PI * 2;
    const pointRadius = index % 2 === 0 ? radius : innerRadius;
    vertices.push([center[0] + Math.cos(angle) * pointRadius, center[1] + Math.sin(angle) * pointRadius]);
  }

  appendPolylineSegments(points, vertices, shape, context, true);
};

const appendPathShape = (points, shape, context) => {
  const commands = Array.isArray(shape.commands) ? shape.commands : [];
  const detail = clampInt(shape.detail || 32, 4, 128);
  let current = null;
  let subpathStart = null;

  commands.forEach((entry) => {
    const command = Array.isArray(entry) ? String(entry[0] || "").toUpperCase() : "";
    const values = Array.isArray(entry) ? entry.slice(1).map((value) => finiteNumber(value, 0)) : [];

    if (command === "M" && values.length >= 2) {
      current = [values[0], values[1]];
      subpathStart = current;
    } else if (command === "L" && current && values.length >= 2) {
      const next = [values[0], values[1]];
      appendRawSegment(points, current, next, shape, context);
      current = next;
    } else if (command === "H" && current && values.length >= 1) {
      const next = [values[0], current[1]];
      appendRawSegment(points, current, next, shape, context);
      current = next;
    } else if (command === "V" && current && values.length >= 1) {
      const next = [current[0], values[0]];
      appendRawSegment(points, current, next, shape, context);
      current = next;
    } else if (command === "Q" && current && values.length >= 4) {
      current = appendQuadraticPath(points, current, values, detail, shape, context);
    } else if (command === "C" && current && values.length >= 6) {
      current = appendCubicPath(points, current, values, detail, shape, context);
    } else if (command === "A" && current && values.length >= 7) {
      current = appendArcPath(points, current, values, detail, shape, context);
    } else if (command === "Z" && current && subpathStart) {
      appendRawSegment(points, current, subpathStart, shape, context);
      current = subpathStart;
    }
  });
};

const appendQuadraticPath = (points, current, values, detail, shape, context) => {
  let previous = current;
  const control = [values[0], values[1]];
  const end = [values[2], values[3]];

  for (let step = 1; step <= detail; step += 1) {
    const t = step / detail;
    const next = [
      quadraticPoint(current[0], control[0], end[0], t),
      quadraticPoint(current[1], control[1], end[1], t)
    ];
    appendRawSegment(points, previous, next, shape, context);
    previous = next;
  }

  return end;
};

const appendCubicPath = (points, current, values, detail, shape, context) => {
  let previous = current;
  const c1 = [values[0], values[1]];
  const c2 = [values[2], values[3]];
  const end = [values[4], values[5]];

  for (let step = 1; step <= detail; step += 1) {
    const t = step / detail;
    const next = [
      cubicPoint(current[0], c1[0], c2[0], end[0], t),
      cubicPoint(current[1], c1[1], c2[1], end[1], t)
    ];
    appendRawSegment(points, previous, next, shape, context);
    previous = next;
  }

  return end;
};

const appendArcPath = (points, current, values, detail, shape, context) => {
  const end = [values[5], values[6]];
  const arc = describeSvgArc({
    from: current,
    to: end,
    rx: values[0],
    ry: values[1],
    xAxisRotation: values[2],
    largeArc: !!values[3],
    sweep: !!values[4]
  });

  if (!arc) {
    appendRawSegment(points, current, end, shape, context);
    return end;
  }

  let previous = current;
  const segments = svgArcSegmentCount(arc, detail);
  for (let step = 1; step <= segments; step += 1) {
    const next = svgArcPoint(arc, step / segments);
    appendRawSegment(points, previous, next, shape, context);
    previous = next;
  }

  return end;
};

const appendRawSegment = (points, from, to, shape, context) => {
  appendSegment(points, normalizeShapePoint(from[0], from[1], context), normalizeShapePoint(to[0], to[1], context), shape, context);
};

const appendPolylineSegments = (points, vertices, shape, context, closed) => {
  for (let index = 1; index < vertices.length; index += 1) {
    appendSegment(points, vertices[index - 1], vertices[index], shape, context);
  }

  if (closed && vertices.length > 2) {
    appendSegment(points, vertices[vertices.length - 1], vertices[0], shape, context);
  }
};

const appendSegment = (points, from, to, shape, context) => {
  const start = applyShapeTransform(from, shape, context);
  const end = applyShapeTransform(to, shape, context);
  points.push(start[0], start[1], end[0], end[1]);
};

const normalizeShapePoints = (value, context) => {
  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .filter((point) => Array.isArray(point) && point.length >= 2)
    .map((point) => normalizeShapePoint(point[0], point[1], context));
};

const shapeCoordinateContext = (params) => {
  const requestedUnits = String(params.units || "").trim().toLowerCase();
  if (requestedUnits) {
    return { units: requestedUnits };
  }

  const version = Number(params.shape_schema_version ?? params.shapeSchemaVersion ?? 1);
  return { units: version >= 2 ? "logical" : "legacy" };
};

const normalizeShapePoint = (x, y, context) => {
  return [
    normalizeShapeCoordinate(x, context, "x"),
    normalizeShapeCoordinate(y, context, "y")
  ];
};

const normalizeShapeCoordinate = (value, context, axis) => {
  const numeric = finiteNumber(value, 0);
  if (context.units === "ndc") {
    return clamp(numeric, -1.2, 1.2);
  }

  if (logicalShapeUnits(context.units)) {
    return clamp(numeric / shapeAxisHalf(axis), -1.2, 1.2);
  }

  if (screenShapeUnits(context.units)) {
    return axis === "y"
      ? clamp(1 - numeric / SHAPE_HALF_HEIGHT, -1.2, 1.2)
      : clamp(numeric / SHAPE_HALF_WIDTH - 1, -1.2, 1.2);
  }

  return normalizeLegacyShapeCoordinate(numeric, axis);
};

const normalizeLegacyShapeCoordinate = (numeric, axis) => {
  if (Math.abs(numeric) <= 1.5) {
    return clamp(numeric, -1.2, 1.2);
  }

  return axis === "y"
    ? clamp(1 - numeric / SHAPE_HALF_HEIGHT, -1.2, 1.2)
    : clamp(numeric / SHAPE_HALF_WIDTH - 1, -1.2, 1.2);
};

const normalizeShapeLength = (value, context, axis) => {
  const numeric = Math.abs(finiteNumber(value, 0));
  if (context.units === "ndc" || Math.abs(numeric) <= 2) {
    return clamp(numeric, 0.005, 1.4);
  }

  return clamp(numeric / shapeAxisHalf(axis === "radius" ? "y" : axis), 0.005, 1.4);
};

const normalizeShapeVector = (value, context, axis) => {
  const numeric = finiteNumber(value, 0);
  if (context.units === "ndc") {
    return clamp(numeric, -2.0, 2.0);
  }

  return clamp(numeric / shapeAxisHalf(axis), -2.0, 2.0);
};

const applyShapeTransform = (point, shape, context) => {
  const transform = shapeTransform(shape, context);
  const shiftedX = (point[0] - transform.origin.x) * transform.scale.x;
  const shiftedY = (point[1] - transform.origin.y) * transform.scale.y;
  const radians = (transform.rotate / 180) * Math.PI;
  const cos = Math.cos(radians);
  const sin = Math.sin(radians);
  const rotatedX = shiftedX * cos - shiftedY * sin;
  const rotatedY = shiftedX * sin + shiftedY * cos;

  return [
    clamp(rotatedX + transform.origin.x + transform.translate.x, -1.2, 1.2),
    clamp(rotatedY + transform.origin.y + transform.translate.y, -1.2, 1.2)
  ];
};

const shapeTransform = (shape, context) => {
  const transform = shape?.transform || {};
  return {
    translate: normalizeShapeVectorObject(transform.translate || shape.translate, context, { x: 0, y: 0 }),
    origin: normalizeShapeVectorObject(transform.origin || shape.origin, context, { x: 0, y: 0 }),
    rotate: finiteNumber(transform.rotate ?? shape.rotate ?? shape.rotation, 0),
    scale: normalizeShapeScale(transform.scale ?? shape.scale)
  };
};

const normalizeShapeVectorObject = (value, context, fallback) => {
  if (Array.isArray(value)) {
    return {
      x: normalizeShapeVector(value[0] ?? fallback.x, context, "x"),
      y: normalizeShapeVector(value[1] ?? fallback.y, context, "y")
    };
  }

  if (value && typeof value === "object") {
    return {
      x: normalizeShapeVector(value.x ?? fallback.x, context, "x"),
      y: normalizeShapeVector(value.y ?? fallback.y, context, "y")
    };
  }

  return fallback;
};

const normalizeShapeScale = (value) => {
  if (value && typeof value === "object") {
    return {
      x: clamp(finiteNumber(value.x, 1), -8, 8),
      y: clamp(finiteNumber(value.y, 1), -8, 8)
    };
  }

  const scale = clamp(finiteNumber(value, 1), -8, 8);
  return { x: scale, y: scale };
};

const lineDefaults = (context) => {
  if (context.units === "legacy" || context.units === "ndc") {
    return [-0.8, 0, 0.8, 0];
  }

  return [-100, 0, 100, 0];
};

const shapeAxisHalf = (axis) => axis === "x" ? SHAPE_HALF_WIDTH : SHAPE_HALF_HEIGHT;

const logicalShapeUnits = (value) => ["logical", "center", "center_origin", "px"].includes(value);

const screenShapeUnits = (value) => ["screen", "canvas", "viewport"].includes(value);

const radiusToRawHalf = (value) => finiteNumber(value, 100) * 0.5;

const quadraticPoint = (from, control, to, t) => {
  const inv = 1 - t;
  return inv * inv * from + 2 * inv * t * control + t * t * to;
};

const cubicPoint = (from, c1, c2, to, t) => {
  const inv = 1 - t;
  return inv * inv * inv * from + 3 * inv * inv * t * c1 + 3 * inv * t * t * c2 + t * t * t * to;
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
