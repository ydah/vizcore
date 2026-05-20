export const describeSvgArc = ({ from, to, rx, ry, xAxisRotation = 0, largeArc = false, sweep = false }) => {
  const start = pointPair(from);
  const end = pointPair(to);
  if (!start || !end) return null;
  if (samePoint(start, end)) return null;

  let radiusX = Math.abs(finiteNumber(rx, 0));
  let radiusY = Math.abs(finiteNumber(ry, 0));
  if (radiusX <= 0 || radiusY <= 0) return null;

  const rotation = (finiteNumber(xAxisRotation, 0) / 180) * Math.PI;
  const cos = Math.cos(rotation);
  const sin = Math.sin(rotation);
  const dx = (start[0] - end[0]) / 2;
  const dy = (start[1] - end[1]) / 2;
  const x1p = cos * dx + sin * dy;
  const y1p = -sin * dx + cos * dy;

  const radiusScale = ((x1p * x1p) / (radiusX * radiusX)) + ((y1p * y1p) / (radiusY * radiusY));
  if (radiusScale > 1) {
    const scale = Math.sqrt(radiusScale);
    radiusX *= scale;
    radiusY *= scale;
  }

  const rx2 = radiusX * radiusX;
  const ry2 = radiusY * radiusY;
  const x1p2 = x1p * x1p;
  const y1p2 = y1p * y1p;
  const denominator = (rx2 * y1p2) + (ry2 * x1p2);
  if (denominator === 0) return null;

  const numerator = Math.max(0, (rx2 * ry2) - (rx2 * y1p2) - (ry2 * x1p2));
  const sign = Boolean(largeArc) === Boolean(sweep) ? -1 : 1;
  const coefficient = sign * Math.sqrt(numerator / denominator);
  const cxp = coefficient * ((radiusX * y1p) / radiusY);
  const cyp = coefficient * (-(radiusY * x1p) / radiusX);
  const cx = (cos * cxp) - (sin * cyp) + ((start[0] + end[0]) / 2);
  const cy = (sin * cxp) + (cos * cyp) + ((start[1] + end[1]) / 2);

  const startVector = [(x1p - cxp) / radiusX, (y1p - cyp) / radiusY];
  const endVector = [(-x1p - cxp) / radiusX, (-y1p - cyp) / radiusY];
  const startAngle = vectorAngle([1, 0], startVector);
  let deltaAngle = vectorAngle(startVector, endVector);

  if (!sweep && deltaAngle > 0) {
    deltaAngle -= Math.PI * 2;
  } else if (sweep && deltaAngle < 0) {
    deltaAngle += Math.PI * 2;
  }

  return {
    cx,
    cy,
    rx: radiusX,
    ry: radiusY,
    rotation,
    startAngle,
    deltaAngle
  };
};

export const svgArcPoint = (arc, progress) => {
  const angle = arc.startAngle + (arc.deltaAngle * progress);
  const cosRotation = Math.cos(arc.rotation);
  const sinRotation = Math.sin(arc.rotation);
  const x = Math.cos(angle) * arc.rx;
  const y = Math.sin(angle) * arc.ry;

  return [
    arc.cx + (cosRotation * x) - (sinRotation * y),
    arc.cy + (sinRotation * x) + (cosRotation * y)
  ];
};

export const svgArcSegmentCount = (arc, detail = 32) => {
  const safeDetail = clampInt(detail, 4, 128);
  return Math.max(1, Math.ceil((Math.abs(arc.deltaAngle) / (Math.PI * 2)) * safeDetail));
};

const pointPair = (value) => {
  if (!Array.isArray(value) || value.length < 2) return null;

  return [finiteNumber(value[0], 0), finiteNumber(value[1], 0)];
};

const samePoint = (a, b) => Math.abs(a[0] - b[0]) < 1e-9 && Math.abs(a[1] - b[1]) < 1e-9;

const vectorAngle = (from, to) => {
  const cross = (from[0] * to[1]) - (from[1] * to[0]);
  const dot = (from[0] * to[0]) + (from[1] * to[1]);
  return Math.atan2(cross, dot);
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
