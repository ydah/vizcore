const layerType = "{{plugin_type}}";

const clamp = (value, min, max) => Math.min(Math.max(value, min), max);

export const {{plugin_renderer}} = ({ audio, time, layer }) => {
  const params = layer?.params || {};
  const amplitude = clamp(Number(audio?.amplitude || 0), 0, 1);
  const intensity = clamp(Number(params.intensity ?? 1), 0, 4);
  const radius = 0.25 + amplitude * intensity * 0.18;
  const phase = Number(time || 0) * 0.8;
  const points = [];

  for (let index = 0; index < 18; index += 1) {
    const angle = phase + index * Math.PI / 9;
    const nextAngle = angle + Math.PI * 0.35;
    points.push(
      Math.cos(angle) * radius,
      Math.sin(angle) * radius,
      Math.cos(nextAngle) * (radius + 0.18),
      Math.sin(nextAngle) * (radius + 0.18),
    );
  }

  return {
    kind: "lines",
    color: [0.45 + amplitude * 0.35, 0.9, 1.0],
    points,
  };
};

const register = () => {
  const runtime = globalThis.VizcorePlugins;
  if (!runtime?.registerLayerRenderer) {
    return false;
  }

  runtime.registerLayerRenderer(layerType, {{plugin_renderer}});
  return true;
};

if (!register() && typeof globalThis.addEventListener === "function") {
  globalThis.addEventListener("vizcore:plugins-ready", register, { once: true });
}
