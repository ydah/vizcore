const SHAPE_KINDS = ["circle", "line", "rect", "polygon", "polyline", "path", "star"];

export const shapeEditorLayerKey = (layer, index) => `${index}:${String(layer?.name || "layer")}`;

export const shapeEditorEntries = (layers, overrides = {}) => {
  const entries = [];
  const layerList = Array.isArray(layers) ? layers : [];

  layerList.forEach((layer, layerIndex) => {
    const shapes = Array.isArray(layer?.params?.shapes) ? layer.params.shapes : [];
    if (!shapes.length) return;

    const layerKey = shapeEditorLayerKey(layer, layerIndex);
    const layerName = String(layer?.name || `layer_${layerIndex + 1}`);
    shapes.forEach((shape, shapeIndex) => {
      const edited = applyShapePatch(shape, overrides?.[layerKey]?.[shapeIndex]);
      const id = String(edited?.id || `shape_${shapeIndex + 1}`);
      const kind = normalizeKind(edited?.kind || edited?.type);
      entries.push({
        key: `${layerKey}:shapes.${shapeIndex}`,
        layerKey,
        layerName,
        shapeIndex,
        shapeId: id,
        label: `${layerName}.${id}`,
        kind,
        values: shapeEditorValues(edited, kind),
      });
    });
  });

  return entries;
};

export const applyShapeEditorOverrides = (layers, overrides = {}) => {
  const layerList = Array.isArray(layers) ? layers : [];

  return layerList.map((layer, layerIndex) => {
    const shapes = Array.isArray(layer?.params?.shapes) ? layer.params.shapes : null;
    if (!shapes) return layer;

    const layerKey = shapeEditorLayerKey(layer, layerIndex);
    const layerOverrides = overrides?.[layerKey];
    if (!layerOverrides || typeof layerOverrides !== "object") return layer;

    return {
      ...layer,
      params: {
        ...(layer?.params || {}),
        shapes: shapes.map((shape, shapeIndex) => applyShapePatch(shape, layerOverrides[shapeIndex])),
      },
    };
  });
};

export const pruneShapeEditorOverrides = (overrides = {}, entries = []) => {
  const validKeys = new Set(entries.map((entry) => `${entry.layerKey}:${entry.shapeIndex}`));
  const next = {};

  Object.entries(overrides || {}).forEach(([layerKey, layerOverrides]) => {
    if (!layerOverrides || typeof layerOverrides !== "object") return;

    Object.entries(layerOverrides).forEach(([shapeIndex, patch]) => {
      if (!validKeys.has(`${layerKey}:${shapeIndex}`) || !patch || typeof patch !== "object") return;

      next[layerKey] ||= {};
      next[layerKey][shapeIndex] = patch;
    });
  });

  return next;
};

export const normalizeShapeEditorPatch = (values = {}) => {
  const kind = normalizeKind(values.kind);
  const output = {
    kind,
    opacity: clamp(finiteNumber(values.opacity, 1), 0, 1),
    stroke_width: Math.max(0, finiteNumber(values.strokeWidth ?? values.stroke_width, 1)),
    transform: {
      translate: {
        x: finiteNumber(values.translateX, 0),
        y: finiteNumber(values.translateY, 0),
      },
      rotate: finiteNumber(values.rotate, 0),
      scale: {
        x: clamp(finiteNumber(values.scaleX, 1), -8, 8),
        y: clamp(finiteNumber(values.scaleY, 1), -8, 8),
      },
    },
  };
  if (values.fillEnabled !== false && validColor(values.fill)) output.fill = values.fill;
  if (values.strokeColorEnabled !== false && validColor(values.strokeColor ?? values.stroke_color)) {
    output.stroke_color = values.strokeColor ?? values.stroke_color;
  }
  return output;
};

const shapeEditorValues = (shape, kind) => {
  const transform = shape?.transform || {};
  const translate = vectorValue(transform.translate ?? shape?.translate, { x: 0, y: 0 });
  const scale = vectorValue(transform.scale ?? shape?.scale, { x: 1, y: 1 });
  return {
    kind,
    translateX: translate.x,
    translateY: translate.y,
    rotate: finiteNumber(transform.rotate ?? shape?.rotate ?? shape?.rotation, 0),
    scaleX: scale.x,
    scaleY: scale.y,
    opacity: clamp(finiteNumber(shape?.opacity, 1), 0, 1),
    fill: validColor(shape?.fill) ? shape.fill : "#000000",
    fillEnabled: validColor(shape?.fill),
    strokeColor: validColor(shape?.stroke_color ?? shape?.strokeColor) ? (shape.stroke_color ?? shape.strokeColor) : "#ffffff",
    strokeColorEnabled: validColor(shape?.stroke_color ?? shape?.strokeColor),
    strokeWidth: Math.max(0, finiteNumber(shape?.stroke_width ?? shape?.strokeWidth ?? shape?.stroke, 1)),
  };
};

const applyShapePatch = (shape, patch) => {
  if (!patch || typeof patch !== "object") return shape;

  return {
    ...(shape || {}),
    ...patch,
    transform: {
      ...((shape || {}).transform || {}),
      ...(patch.transform || {}),
    },
  };
};

const vectorValue = (value, fallback) => {
  if (Array.isArray(value)) {
    return { x: finiteNumber(value[0], fallback.x), y: finiteNumber(value[1], fallback.y) };
  }

  if (value && typeof value === "object") {
    return { x: finiteNumber(value.x, fallback.x), y: finiteNumber(value.y, fallback.y) };
  }

  const numeric = finiteNumber(value, null);
  return numeric === null ? fallback : { x: numeric, y: numeric };
};

const normalizeKind = (value) => {
  const kind = String(value || "circle").trim().toLowerCase();
  return SHAPE_KINDS.includes(kind) ? kind : "circle";
};

const validColor = (value) => /^#[0-9a-f]{6}$/i.test(String(value || ""));

const finiteNumber = (value, fallback) => {
  const numeric = Number(value);
  return Number.isFinite(numeric) ? numeric : fallback;
};

const clamp = (value, min, max) => Math.min(Math.max(value, min), max);
