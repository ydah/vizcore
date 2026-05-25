export const SHADER_ERROR_EVENT = "vizcore:shader-error";

export const buildShaderErrorDetail = ({ layer, error, phase }) => {
  const name = String(layer?.name || "unnamed");
  const shader = String(layer?.glsl || layer?.shader || layer?.type || "unknown");
  return {
    name,
    shader,
    phase: String(phase || "shader"),
    event: "shader_failed",
    message: normalizeErrorMessage(error),
  };
};

export const formatShaderErrorTitle = (detail) => {
  const name = String(detail?.name || "unnamed");
  const shader = String(detail?.shader || "unknown");
  return `${name} (${shader})`;
};

export const formatShaderErrorMessage = (detail) => {
  const phase = String(detail?.phase || "shader");
  const message = String(detail?.message || "Unknown shader error");
  return `[${phase}] ${message}`;
};

const normalizeErrorMessage = (error) => {
  const message = String(error?.message || error || "Unknown shader error").trim();
  return message || "Unknown shader error";
};
