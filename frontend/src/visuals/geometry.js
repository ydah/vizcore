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

const clamp = (value, min, max) => Math.min(Math.max(value, min), max);
