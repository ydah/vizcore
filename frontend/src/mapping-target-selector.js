const SHAPE_TARGETS = {
  circle: ["x", "y", "radius", "segments", "count"],
  line: ["x1", "y1", "x2", "y2"],
  rect: ["x", "y", "width", "height", "radius"],
  polygon: [],
  polyline: [],
  path: ["detail", "tolerance", "max_segments"],
  star: ["x", "y", "points", "radius", "inner_radius", "rotation"],
};

const COMMON_SHAPE_TARGETS = [
  "opacity",
  "stroke_width",
  "transform.translate.x",
  "transform.translate.y",
  "transform.rotate",
  "transform.scale",
  "transform.scale.x",
  "transform.scale.y",
  "transform.origin.x",
  "transform.origin.y",
];

export const mappingTargetOptions = (layers) => {
  const options = [];
  const seen = new Set();
  const layerList = Array.isArray(layers) ? layers : [];

  layerList.forEach((layer, layerIndex) => {
    const layerName = String(layer?.name || `layer_${layerIndex + 1}`);
    appendLayerParamTargets(options, seen, layer, layerName);
    appendShapeTargets(options, seen, layer, layerName);
    appendCustomShapeTargets(options, seen, layer, layerName);
  });

  return options;
};

export const mappingTargetSignature = (options) => (
  (Array.isArray(options) ? options : []).map((option) => `${option.layerName}:${option.target}`).join("|")
);

const appendLayerParamTargets = (options, seen, layer, layerName) => {
  const schema = Array.isArray(layer?.param_schema) ? layer.param_schema : [];
  schema.forEach((entry) => {
    const paramName = normalizeName(entry?.name);
    if (!paramName) return;

    appendOption(options, seen, {
      layerName,
      target: paramName,
      label: `${layerName}.${paramName}`,
      scope: "layer",
    });
  });
};

const appendShapeTargets = (options, seen, layer, layerName) => {
  const shapes = Array.isArray(layer?.params?.shapes) ? layer.params.shapes : [];
  shapes.forEach((shape, shapeIndex) => {
    const kind = String(shape?.kind || shape?.type || "").toLowerCase();
    const shapeName = normalizeName(shape?.id) || `shape_${shapeIndex + 1}`;
    const targets = [...COMMON_SHAPE_TARGETS, ...(SHAPE_TARGETS[kind] || [])];
    targets.forEach((target) => {
      appendOption(options, seen, {
        layerName,
        target: `shapes.${shapeIndex}.${target}`,
        label: `${layerName}.${shapeName}.${target}`,
        scope: "shape",
      });
    });
  });
};

const appendCustomShapeTargets = (options, seen, layer, layerName) => {
  const controls = Array.isArray(layer?.params?.custom_shape_controls) ? layer.params.custom_shape_controls : [];
  controls.forEach((control, fallbackIndex) => {
    const index = finiteIndex(control?.index, fallbackIndex);
    const customShapeName = normalizeName(control?.name) || `custom_shape_${index + 1}`;
    const params = control?.params && typeof control.params === "object" ? Object.keys(control.params) : [];
    const schemaNames = (Array.isArray(control?.param_schema) ? control.param_schema : []).map((entry) => normalizeName(entry?.name)).filter(Boolean);
    [...new Set([...schemaNames, ...params])].sort().forEach((paramName) => {
      appendOption(options, seen, {
        layerName,
        target: `custom_shapes.${index}.params.${paramName}`,
        label: `${layerName}.${customShapeName}.${paramName}`,
        scope: "custom_shape",
      });
    });
  });
};

const appendOption = (options, seen, option) => {
  const key = `${option.layerName}:${option.target}`;
  if (seen.has(key)) return;

  seen.add(key);
  options.push({ ...option, key });
};

const normalizeName = (value) => {
  const name = String(value || "").trim();
  return name || null;
};

const finiteIndex = (value, fallback) => {
  const numeric = Number(value);
  return Number.isInteger(numeric) && numeric >= 0 ? numeric : fallback;
};
