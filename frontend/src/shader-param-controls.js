export const shaderParamLayerKey = (layer, index) => `${index}:${String(layer?.name || "layer")}`;

export const shaderParamControlEntries = (layers, overrides = {}) => {
  const entries = [];
  const layerList = Array.isArray(layers) ? layers : [];

  layerList.forEach((layer, layerIndex) => {
    const schema = Array.isArray(layer?.param_schema) ? layer.param_schema : [];
    const layerKey = shaderParamLayerKey(layer, layerIndex);
    const layerName = String(layer?.name || `layer_${layerIndex + 1}`);

    schema.forEach((entry) => {
      const paramName = normalizeParamName(entry?.name);
      if (!paramName) {
        return;
      }

      const min = finiteNumber(entry?.min, 0);
      const max = Math.max(min, finiteNumber(entry?.max, min + 1));
      const step = positiveNumber(entry?.step, Math.max((max - min) / 100, 0.01));
      const params = layer?.params || {};
      const baseValue = finiteNumber(
        overrides?.[layerKey]?.[paramName],
        finiteNumber(params[paramName], finiteNumber(entry?.default, min))
      );

      entries.push({
        key: `${layerKey}:${paramName}`,
        layerKey,
        layerName,
        paramName,
        label: `${layerName}.${paramName}`,
        min,
        max,
        step,
        value: clamp(baseValue, min, max),
      });
    });
  });

  return entries;
};

export const applyShaderParamOverrides = (layers, overrides = {}) => {
  const layerList = Array.isArray(layers) ? layers : [];

  return layerList.map((layer, layerIndex) => {
    const layerKey = shaderParamLayerKey(layer, layerIndex);
    const layerOverrides = overrides?.[layerKey];
    if (!layerOverrides || typeof layerOverrides !== "object") {
      return layer;
    }

    return {
      ...layer,
      params: {
        ...(layer?.params || {}),
        ...layerOverrides,
      },
    };
  });
};

export const pruneShaderParamOverrides = (overrides = {}, entries = []) => {
  const next = {};
  for (const entry of entries) {
    const value = overrides?.[entry.layerKey]?.[entry.paramName];
    if (!Number.isFinite(Number(value))) {
      continue;
    }

    next[entry.layerKey] ||= {};
    next[entry.layerKey][entry.paramName] = Number(value);
  }
  return next;
};

const normalizeParamName = (value) => {
  const name = String(value || "").trim();
  return name || null;
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
