const layerRenderers = new Map();

export const registerLayerRenderer = (type, renderer) => {
  const key = normalizeLayerType(type);
  if (!key || typeof renderer !== "function") {
    return false;
  }

  layerRenderers.set(key, renderer);
  return true;
};

export const unregisterLayerRenderer = (type) => {
  const key = normalizeLayerType(type);
  return key ? layerRenderers.delete(key) : false;
};

export const resolveLayerRenderer = (type) => {
  return layerRenderers.get(normalizeLayerType(type)) || null;
};

export const registeredLayerRendererTypes = () => Array.from(layerRenderers.keys()).sort();

export const normalizePluginLineOutput = (output) => {
  const input = output && typeof output === "object" ? output : {};
  const kind = String(input.kind || "lines").toLowerCase();
  if (kind !== "lines") {
    return null;
  }

  const points = Array.isArray(input.points) || ArrayBuffer.isView(input.points)
    ? Array.from(input.points).map((value) => Number(value)).filter(Number.isFinite)
    : [];
  if (points.length < 4) {
    return null;
  }

  return {
    kind: "lines",
    points: points.length % 2 === 0 ? points : points.slice(0, -1),
    color: normalizeRgb(input.color),
  };
};

export const installGlobalPluginRuntime = (target = globalThis) => {
  if (!target || typeof target !== "object") {
    return null;
  }

  const runtime = {
    registerLayerRenderer,
    unregisterLayerRenderer,
    registeredLayerRendererTypes,
  };
  target.VizcorePlugins = {
    ...(target.VizcorePlugins || {}),
    ...runtime,
  };
  if (typeof target.dispatchEvent === "function" && typeof target.Event === "function") {
    target.dispatchEvent(new target.Event("vizcore:plugins-ready"));
  }
  return target.VizcorePlugins;
};

const normalizeLayerType = (type) => String(type || "").trim().toLowerCase();

const normalizeRgb = (value) => {
  const values = Array.isArray(value) ? value : [];
  if (values.length < 3) {
    return null;
  }

  const rgb = values.slice(0, 3).map((entry) => Number(entry));
  return rgb.every(Number.isFinite)
    ? rgb.map((entry) => Math.min(Math.max(entry, 0), 1))
    : null;
};

installGlobalPluginRuntime();
