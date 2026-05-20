export const customShapeParamControlEntries = (layers, overrides = {}) => {
  const entries = [];
  const layerList = Array.isArray(layers) ? layers : [];

  layerList.forEach((layer, layerIndex) => {
    const controls = Array.isArray(layer?.params?.custom_shape_controls) ? layer.params.custom_shape_controls : [];
    if (!controls.length) return;

    const layerKey = layerControlKey(layer, layerIndex);
    const layerName = String(layer?.name || `layer_${layerIndex + 1}`);
    controls.forEach((control, controlIndex) => {
      const customShapeIndex = finiteIndex(control?.index, controlIndex);
      const customShapeName = String(control?.name || `custom_shape_${customShapeIndex + 1}`);
      const params = control?.params && typeof control.params === "object" ? control.params : {};
      const schemaByName = paramSchemaByName(control?.param_schema);
      const paramNames = [...new Set([...Object.keys(schemaByName), ...Object.keys(params)])].sort();

      paramNames.forEach((paramName) => {
        const schema = schemaByName[paramName] || {};
        const baseValue = finiteNumber(params[paramName], finiteNumber(schema.default, 0));
        const min = finiteNumber(schema.min, Math.min(0, baseValue));
        const fallbackMax = Math.max(min + 1, Math.abs(baseValue) * 2, 1);
        const max = Math.max(min, finiteNumber(schema.max, fallbackMax));
        const step = positiveNumber(schema.step, Math.max((max - min) / 100, 0.01));
        const value = finiteNumber(overrides?.[layerKey]?.[customShapeIndex]?.[paramName], baseValue);

        entries.push({
          key: `${layerKey}:custom_shapes.${customShapeIndex}.params.${paramName}`,
          layerKey,
          layerName,
          customShapeIndex,
          customShapeName,
          paramName,
          label: `${layerName}.${customShapeName}.${paramName}`,
          target: `custom_shapes.${customShapeIndex}.params.${paramName}`,
          min,
          max,
          step,
          value: clamp(value, min, max),
        });
      });
    });
  });

  return entries;
};

export const pruneCustomShapeParamOverrides = (overrides = {}, entries = []) => {
  const validKeys = new Set(entries.map((entry) => `${entry.layerKey}:${entry.customShapeIndex}:${entry.paramName}`));
  const next = {};

  Object.entries(overrides || {}).forEach(([layerKey, controls]) => {
    if (!controls || typeof controls !== "object") return;

    Object.entries(controls).forEach(([customShapeIndex, params]) => {
      if (!params || typeof params !== "object") return;

      Object.entries(params).forEach(([paramName, value]) => {
        if (!validKeys.has(`${layerKey}:${customShapeIndex}:${paramName}`) || !Number.isFinite(Number(value))) return;

        next[layerKey] ||= {};
        next[layerKey][customShapeIndex] ||= {};
        next[layerKey][customShapeIndex][paramName] = Number(value);
      });
    });
  });

  return next;
};

export const customShapeParamMessage = (entry, value) => ({
  layer: entry.layerName,
  custom_shape_index: entry.customShapeIndex,
  param: entry.paramName,
  value: clamp(finiteNumber(value, entry.value), entry.min, entry.max),
});

const layerControlKey = (layer, index) => `${index}:${String(layer?.name || "layer")}`;

const paramSchemaByName = (schema) => {
  const output = {};
  (Array.isArray(schema) ? schema : []).forEach((entry) => {
    const name = String(entry?.name || "").trim();
    if (!name) return;

    output[name] = entry;
  });
  return output;
};

const finiteIndex = (value, fallback) => {
  const numeric = Number(value);
  return Number.isInteger(numeric) && numeric >= 0 ? numeric : fallback;
};

const finiteNumber = (value, fallback) => {
  const numeric = Number(value);
  return Number.isFinite(numeric) ? numeric : fallback;
};

const positiveNumber = (value, fallback) => {
  const numeric = finiteNumber(value, fallback);
  return numeric > 0 ? numeric : fallback;
};

const clamp = (value, min, max) => Math.min(Math.max(value, min), max);
