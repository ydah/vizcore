import { describeSvgArc } from "./svg-arc.js";

const SHAPE_VERTEX_SHADER = `#version 300 es
in vec2 a_position;
in vec2 a_uv;
out vec2 v_uv;
void main() {
  v_uv = a_uv;
  gl_Position = vec4(a_position, 0.0, 1.0);
}
`;

const SHAPE_FRAGMENT_SHADER = `#version 300 es
precision mediump float;
in vec2 v_uv;
uniform sampler2D u_texture;
uniform float u_intensity;
out vec4 outColor;

void main() {
  vec4 texel = texture(u_texture, v_uv);
  outColor = vec4(texel.rgb, texel.a * u_intensity);
}
`;

const QUAD_VERTICES = new Float32Array([
  -1.0, -1.0, 0.0, 1.0,
  1.0, -1.0, 1.0, 1.0,
  -1.0, 1.0, 0.0, 0.0,
  1.0, 1.0, 1.0, 0.0
]);

export class ShapeRenderer {
  constructor(gl, shaderManager) {
    this.gl = gl;
    this.shaderManager = shaderManager;
    this.program = this.shaderManager.getProgram("shape-renderer", SHAPE_VERTEX_SHADER, SHAPE_FRAGMENT_SHADER);
    this.positionLocation = this.gl.getAttribLocation(this.program, "a_position");
    this.uvLocation = this.gl.getAttribLocation(this.program, "a_uv");
    this.textureLocation = this.gl.getUniformLocation(this.program, "u_texture");
    this.intensityLocation = this.gl.getUniformLocation(this.program, "u_intensity");

    this.buffer = this.gl.createBuffer();
    this.gl.bindBuffer(this.gl.ARRAY_BUFFER, this.buffer);
    this.gl.bufferData(this.gl.ARRAY_BUFFER, QUAD_VERTICES, this.gl.STATIC_DRAW);

    this.canvas = typeof document === "undefined" ? null : document.createElement("canvas");
    this.ctx = this.canvas?.getContext("2d") || null;

    this.texture = this.gl.createTexture();
    this.gl.bindTexture(this.gl.TEXTURE_2D, this.texture);
    this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_MIN_FILTER, this.gl.LINEAR);
    this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_MAG_FILTER, this.gl.LINEAR);
    this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_S, this.gl.CLAMP_TO_EDGE);
    this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_T, this.gl.CLAMP_TO_EDGE);
  }

  render({ params = {}, color = "#e5f3ff", resolution = [1280, 720], audio = {} } = {}) {
    const shapes = Array.isArray(params.shapes) ? params.shapes : [];
    if (!this.ctx || shapes.length === 0) {
      return false;
    }

    this.syncCanvasSize(resolution);
    this.drawShapesToCanvas({ shapes, params, color });
    this.uploadTexture();
    const pulse = clamp(Number(audio?.beat_pulse || 0), 0, 1);
    this.drawQuad({ intensity: 0.92 + pulse * 0.08 });
    return true;
  }

  syncCanvasSize(resolution) {
    const width = clamp(Math.floor(Number(resolution?.[0] || this.gl.drawingBufferWidth || 1024)), 1, 4096);
    const height = clamp(Math.floor(Number(resolution?.[1] || this.gl.drawingBufferHeight || 1024)), 1, 4096);
    if (this.canvas.width === width && this.canvas.height === height) {
      return;
    }
    this.canvas.width = width;
    this.canvas.height = height;
  }

  drawShapesToCanvas({ shapes, params, color }) {
    const ctx = this.ctx;
    const context = shapeCoordinateContext(params);
    ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);

    shapes.forEach((shape) => {
      const kind = shapeKind(shape);
      if (!kind) return;

      ctx.save();
      applyShapeTransform(ctx, shape, context, this.canvas);
      drawShapePath(ctx, shape, kind, context, this.canvas);
      paintShapePath(ctx, shape, kind, color);
      ctx.restore();
    });
  }

  uploadTexture() {
    this.gl.bindTexture(this.gl.TEXTURE_2D, this.texture);
    this.gl.texImage2D(
      this.gl.TEXTURE_2D,
      0,
      this.gl.RGBA,
      this.gl.RGBA,
      this.gl.UNSIGNED_BYTE,
      this.canvas
    );
  }

  drawQuad({ intensity }) {
    const gl = this.gl;
    gl.useProgram(this.program);
    gl.bindBuffer(gl.ARRAY_BUFFER, this.buffer);
    gl.enableVertexAttribArray(this.positionLocation);
    gl.vertexAttribPointer(this.positionLocation, 2, gl.FLOAT, false, 16, 0);
    gl.enableVertexAttribArray(this.uvLocation);
    gl.vertexAttribPointer(this.uvLocation, 2, gl.FLOAT, false, 16, 8);

    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, this.texture);
    gl.uniform1i(this.textureLocation, 0);
    gl.uniform1f(this.intensityLocation, clamp(Number(intensity || 1), 0, 1));
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
  }

  dispose() {
    if (this.texture) {
      this.gl.deleteTexture(this.texture);
      this.texture = null;
    }
    if (this.buffer) {
      this.gl.deleteBuffer(this.buffer);
      this.buffer = null;
    }
    this.canvas = null;
    this.ctx = null;
  }
}

export const shapeCoordinateContext = (params = {}) => {
  const requestedUnits = String(params.units || "").trim().toLowerCase();
  if (requestedUnits) {
    return { units: requestedUnits };
  }

  const version = Number(params.shape_schema_version ?? params.shapeSchemaVersion ?? 1);
  return { units: version >= 2 ? "logical" : "legacy" };
};

export const resolveShapeCanvasPoint = (x, y, context, canvas) => {
  return [
    resolveShapeCanvasCoordinate(x, context, canvas, "x"),
    resolveShapeCanvasCoordinate(y, context, canvas, "y")
  ];
};

export const resolveShapeCanvasLength = (value, context, canvas, axis = "radius") => {
  const numeric = Math.abs(finiteNumber(value, 0));
  if (context.units === "ndc" || numeric <= 2) {
    return numeric * Math.min(canvas.width, canvas.height) * 0.5;
  }

  return numeric;
};

export const resolveShapeStyle = (shape, layerColor = "#e5f3ff") => {
  const fill = normalizePaint(shape?.fill);
  const strokeColor = normalizePaint(shape?.stroke_color ?? shape?.strokeColor) || layerColor;
  const strokeWidth = normalizeStrokeWidth(shape);
  const opacity = clamp(finiteNumber(shape?.opacity, 1), 0, 1);
  const dash = Array.isArray(shape?.dash) ? shape.dash.map((value) => Math.max(0, finiteNumber(value, 0))) : [];
  return { fill, strokeColor, strokeWidth, opacity, dash };
};

export const shouldStrokeShape = (shape, kind) => {
  if (kind === "line" || kind === "polyline" || kind === "path") {
    return true;
  }
  return !normalizePaint(shape?.fill) || shape?.stroke !== undefined || shape?.stroke_width !== undefined || shape?.stroke_color !== undefined;
};

const drawShapePath = (ctx, shape, kind, context, canvas) => {
  ctx.beginPath();
  if (kind === "circle") {
    appendCirclePath(ctx, shape, context, canvas);
  } else if (kind === "line") {
    appendLinePath(ctx, shape, context, canvas);
  } else if (kind === "rect") {
    appendRectPath(ctx, shape, context, canvas);
  } else if (kind === "polygon" || kind === "polyline") {
    appendPolygonPath(ctx, shape, context, canvas, kind === "polygon");
  } else if (kind === "path") {
    appendCustomPath(ctx, shape, context, canvas);
  } else if (kind === "star") {
    appendStarPath(ctx, shape, context, canvas);
  }
};

const paintShapePath = (ctx, shape, kind, layerColor) => {
  const style = resolveShapeStyle(shape, layerColor);
  ctx.globalAlpha = style.opacity;
  ctx.lineWidth = style.strokeWidth;
  ctx.strokeStyle = style.strokeColor;
  ctx.fillStyle = style.fill || "rgba(0, 0, 0, 0)";
  ctx.lineCap = normalizeLineCap(shape?.line_cap ?? shape?.lineCap);
  ctx.lineJoin = normalizeLineJoin(shape?.line_join ?? shape?.lineJoin);
  ctx.miterLimit = clamp(finiteNumber(shape?.miter_limit ?? shape?.miterLimit, 10), 1, 64);
  if (typeof ctx.setLineDash === "function") {
    ctx.setLineDash(style.dash);
  }

  if (style.fill) {
    ctx.fill();
  }
  if (shouldStrokeShape(shape, kind) && style.strokeWidth > 0) {
    ctx.stroke();
  }
};

const appendCirclePath = (ctx, shape, context, canvas) => {
  const count = clampInt(shape.count || 1, 1, 64);
  const segments = clampInt(shape.segments || 96, 12, 256);
  const radius = resolveShapeCanvasLength(shape.radius ?? 100, context, canvas, "radius");
  const [x, y] = resolveShapeCanvasPoint(shape.x ?? 0, shape.y ?? 0, context, canvas);

  for (let ring = 0; ring < count; ring += 1) {
    ctx.moveTo(x + radius * ((ring + 1) / count), y);
    ctx.arc(x, y, radius * ((ring + 1) / count), 0, Math.PI * 2, false);
  }
};

const appendLinePath = (ctx, shape, context, canvas) => {
  const defaults = context.units === "legacy" || context.units === "ndc" ? [-0.8, 0, 0.8, 0] : [-100, 0, 100, 0];
  const from = resolveShapeCanvasPoint(shape.x1 ?? defaults[0], shape.y1 ?? defaults[1], context, canvas);
  const to = resolveShapeCanvasPoint(shape.x2 ?? defaults[2], shape.y2 ?? defaults[3], context, canvas);
  ctx.moveTo(from[0], from[1]);
  ctx.lineTo(to[0], to[1]);
};

const appendRectPath = (ctx, shape, context, canvas) => {
  const [x, y] = resolveShapeCanvasPoint(shape.x ?? 0, shape.y ?? 0, context, canvas);
  const width = resolveShapeCanvasLength(shape.width ?? 100, context, canvas, "x");
  const height = resolveShapeCanvasLength(shape.height ?? 100, context, canvas, "y");
  const radius = clamp(resolveShapeCanvasLength(shape.radius ?? 0, context, canvas, "radius"), 0, Math.min(width, height) / 2);
  const left = x - width / 2;
  const top = y - height / 2;

  if (radius <= 0) {
    ctx.rect(left, top, width, height);
    return;
  }

  ctx.moveTo(left + radius, top);
  ctx.lineTo(left + width - radius, top);
  ctx.quadraticCurveTo(left + width, top, left + width, top + radius);
  ctx.lineTo(left + width, top + height - radius);
  ctx.quadraticCurveTo(left + width, top + height, left + width - radius, top + height);
  ctx.lineTo(left + radius, top + height);
  ctx.quadraticCurveTo(left, top + height, left, top + height - radius);
  ctx.lineTo(left, top + radius);
  ctx.quadraticCurveTo(left, top, left + radius, top);
  ctx.closePath();
};

const appendPolygonPath = (ctx, shape, context, canvas, defaultClosed) => {
  const points = normalizeShapePoints(shape.points, context, canvas);
  if (points.length < (defaultClosed ? 3 : 2)) {
    return;
  }
  ctx.moveTo(points[0][0], points[0][1]);
  points.slice(1).forEach((point) => ctx.lineTo(point[0], point[1]));
  if (shape.closed ?? defaultClosed) {
    ctx.closePath();
  }
};

const appendStarPath = (ctx, shape, context, canvas) => {
  const tips = clampInt(shape.points || 5, 3, 128);
  const radius = resolveShapeCanvasLength(shape.radius ?? 100, context, canvas, "radius");
  const innerRadius = resolveShapeCanvasLength(shape.inner_radius ?? finiteNumber(shape.radius, 100) * 0.5, context, canvas, "radius");
  const [cx, cy] = resolveShapeCanvasPoint(shape.x ?? 0, shape.y ?? 0, context, canvas);
  const rotation = (finiteNumber(shape.rotation, -90) / 180) * Math.PI;

  for (let index = 0; index < tips * 2; index += 1) {
    const angle = rotation + (index / (tips * 2)) * Math.PI * 2;
    const pointRadius = index % 2 === 0 ? radius : innerRadius;
    const x = cx + Math.cos(angle) * pointRadius;
    const y = cy - Math.sin(angle) * pointRadius;
    if (index === 0) {
      ctx.moveTo(x, y);
    } else {
      ctx.lineTo(x, y);
    }
  }
  ctx.closePath();
};

const appendCustomPath = (ctx, shape, context, canvas) => {
  let current = null;
  (Array.isArray(shape.commands) ? shape.commands : []).forEach((entry) => {
    const command = Array.isArray(entry) ? String(entry[0] || "").toUpperCase() : "";
    const values = Array.isArray(entry) ? entry.slice(1).map((value) => finiteNumber(value, 0)) : [];
    if (command === "M" && values.length >= 2) {
      current = resolveShapeCanvasPoint(values[0], values[1], context, canvas);
      ctx.moveTo(current[0], current[1]);
    } else if (command === "L" && values.length >= 2) {
      current = resolveShapeCanvasPoint(values[0], values[1], context, canvas);
      ctx.lineTo(current[0], current[1]);
    } else if (command === "H" && current && values.length >= 1) {
      current = [resolveShapeCanvasCoordinate(values[0], context, canvas, "x"), current[1]];
      ctx.lineTo(current[0], current[1]);
    } else if (command === "V" && current && values.length >= 1) {
      current = [current[0], resolveShapeCanvasCoordinate(values[0], context, canvas, "y")];
      ctx.lineTo(current[0], current[1]);
    } else if (command === "Q" && values.length >= 4) {
      const control = resolveShapeCanvasPoint(values[0], values[1], context, canvas);
      current = resolveShapeCanvasPoint(values[2], values[3], context, canvas);
      ctx.quadraticCurveTo(control[0], control[1], current[0], current[1]);
    } else if (command === "C" && values.length >= 6) {
      const c1 = resolveShapeCanvasPoint(values[0], values[1], context, canvas);
      const c2 = resolveShapeCanvasPoint(values[2], values[3], context, canvas);
      current = resolveShapeCanvasPoint(values[4], values[5], context, canvas);
      ctx.bezierCurveTo(c1[0], c1[1], c2[0], c2[1], current[0], current[1]);
    } else if (command === "A" && current && values.length >= 7) {
      current = appendSvgArcPath(ctx, current, values, context, canvas);
    } else if (command === "Z") {
      ctx.closePath();
    }
  });
};

const appendSvgArcPath = (ctx, current, values, context, canvas) => {
  const endpoint = resolveShapeCanvasPoint(values[5], values[6], context, canvas);
  const arc = describeSvgArc({
    from: current,
    to: endpoint,
    rx: resolveShapeCanvasLength(values[0], context, canvas, "x"),
    ry: resolveShapeCanvasLength(values[1], context, canvas, "y"),
    xAxisRotation: -finiteNumber(values[2], 0),
    largeArc: !!values[3],
    sweep: !!values[4]
  });

  if (arc && typeof ctx.ellipse === "function") {
    ctx.ellipse(
      arc.cx,
      arc.cy,
      arc.rx,
      arc.ry,
      arc.rotation,
      arc.startAngle,
      arc.startAngle + arc.deltaAngle,
      arc.deltaAngle < 0
    );
  } else {
    ctx.lineTo(endpoint[0], endpoint[1]);
  }

  return endpoint;
};

const applyShapeTransform = (ctx, shape, context, canvas) => {
  const transform = shape?.transform || {};
  const origin = resolveShapeCanvasPoint(
    transform.origin?.x ?? transform.origin?.[0] ?? 0,
    transform.origin?.y ?? transform.origin?.[1] ?? 0,
    context,
    canvas
  );
  const translate = resolveShapeCanvasVector(transform.translate || shape?.translate, context, canvas);
  const rotation = finiteNumber(transform.rotate ?? shape?.rotate ?? shape?.rotation, 0);
  const scale = normalizeShapeScale(transform.scale ?? shape?.scale);

  ctx.translate(origin[0], origin[1]);
  ctx.translate(translate.x, translate.y);
  ctx.rotate((-rotation / 180) * Math.PI);
  ctx.scale(scale.x, scale.y);
  ctx.translate(-origin[0], -origin[1]);
};

const resolveShapeCanvasCoordinate = (value, context, canvas, axis) => {
  const numeric = finiteNumber(value, 0);
  if (context.units === "ndc") {
    return axis === "x"
      ? canvas.width * 0.5 + numeric * canvas.width * 0.5
      : canvas.height * 0.5 - numeric * canvas.height * 0.5;
  }

  if (logicalShapeUnits(context.units)) {
    return axis === "x" ? canvas.width * 0.5 + numeric : canvas.height * 0.5 - numeric;
  }

  if (screenShapeUnits(context.units)) {
    return numeric;
  }

  return legacyShapeCoordinate(numeric, axis, canvas);
};

const legacyShapeCoordinate = (numeric, axis, canvas) => {
  if (Math.abs(numeric) <= 1.5) {
    return axis === "x"
      ? canvas.width * 0.5 + numeric * canvas.width * 0.5
      : canvas.height * 0.5 - numeric * canvas.height * 0.5;
  }
  return numeric;
};

const resolveShapeCanvasVector = (value, context, canvas) => {
  if (!value || typeof value !== "object") {
    return { x: 0, y: 0 };
  }
  const x = Array.isArray(value) ? value[0] : value.x;
  const y = Array.isArray(value) ? value[1] : value.y;
  if (context.units === "ndc") {
    return {
      x: finiteNumber(x, 0) * canvas.width * 0.5,
      y: -finiteNumber(y, 0) * canvas.height * 0.5
    };
  }
  return { x: finiteNumber(x, 0), y: -finiteNumber(y, 0) };
};

const normalizeShapePoints = (value, context, canvas) => {
  if (!Array.isArray(value)) {
    return [];
  }
  return value
    .filter((point) => Array.isArray(point) && point.length >= 2)
    .map((point) => resolveShapeCanvasPoint(point[0], point[1], context, canvas));
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

const normalizeStrokeWidth = (shape) => {
  const width = shape?.stroke_width ?? shape?.strokeWidth ?? (typeof shape?.stroke === "number" ? shape.stroke : 1);
  return clamp(finiteNumber(width, 1), 0, 512);
};

const normalizePaint = (value) => {
  const paint = String(value ?? "").trim();
  if (!paint || paint === "none" || paint === "transparent") {
    return null;
  }
  return paint;
};

const normalizeLineCap = (value) => {
  const cap = String(value || "butt").trim().toLowerCase();
  return cap === "round" || cap === "square" ? cap : "butt";
};

const normalizeLineJoin = (value) => {
  const join = String(value || "miter").trim().toLowerCase();
  return join === "round" || join === "bevel" ? join : "miter";
};

const shapeKind = (shape) => {
  const kind = String(shape?.kind || shape?.type || "").toLowerCase();
  return ["circle", "line", "rect", "polygon", "polyline", "path", "star"].includes(kind) ? kind : null;
};

const logicalShapeUnits = (value) => ["logical", "center", "center_origin", "px"].includes(value);

const screenShapeUnits = (value) => ["screen", "canvas", "viewport"].includes(value);

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
