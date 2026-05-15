export const resolveProjectorMode = ({ body, current = false, location, runtime } = {}) => {
  if (controlModeFromBody(body) || controlModeFromLocation(location)) {
    return false;
  }

  return current
    || projectorModeFromBody(body)
    || projectorModeFromLocation(location)
    || projectorModeFromRuntime(runtime);
};

export const applyProjectorMode = (body, enabled) => {
  if (!body) {
    return;
  }

  const active = !!enabled;
  if (body.classList && typeof body.classList.toggle === "function") {
    body.classList.toggle("is-projector", active);
  }

  if (body.dataset) {
    body.dataset.projectorMode = active ? "true" : "false";
  }
};

export const projectorModeFromRuntime = (runtime) => truthyValue(runtime?.projector_mode);

export const projectorModeFromBody = (body) => truthyValue(body?.dataset?.projectorMode);

export const controlModeFromBody = (body) => body?.dataset?.displayMode === "control";

export const projectorModeFromLocation = (location) => {
  const search = String(location?.search || "");
  if (!search) {
    return false;
  }

  const params = new URLSearchParams(search);
  return truthyValue(params.get("projector")) || params.get("mode") === "projector";
};

export const controlModeFromLocation = (location) => {
  const search = String(location?.search || "");
  if (!search) {
    return false;
  }

  const params = new URLSearchParams(search);
  return truthyValue(params.get("control")) || params.get("mode") === "control";
};

const truthyValue = (value) => {
  const normalized = String(value || "").trim().toLowerCase();
  return normalized === "1" || normalized === "true" || normalized === "yes";
};
