const REMOVED_LAYER = Symbol("vizcore.scene.removed_layer");

const isObject = (value) => value !== null && typeof value === "object";

const clonePayload = (value) => {
  if (!isObject(value) && !Array.isArray(value)) {
    return value;
  }

  if (typeof structuredClone === "function") {
    try {
      return structuredClone(value);
    } catch {
      // Fall back to JSON clone below.
    }
  }

  try {
    return JSON.parse(JSON.stringify(value));
  } catch {
    return null;
  }
};

const sceneVersion = (value) => {
  const numeric = Number(value);
  return Number.isFinite(numeric) ? numeric : null;
};

const normalizeIndex = (value) => {
  const numeric = Number(value);
  return Number.isInteger(numeric) && numeric >= 0 ? numeric : null;
};

export const applyScenePayload = (payload) => {
  if (!isObject(payload)) {
    return null;
  }

  const scene = clonePayload(payload);
  if (!isObject(scene)) {
    return null;
  }

  if (!Array.isArray(scene.layers)) {
    scene.layers = [];
  } else {
    scene.layers = scene.layers.map((entry) => clonePayload(entry)).filter(Boolean);
  }

  return scene;
};

export const applyScenePatch = (currentScene, patch) => {
  if (!isObject(currentScene) || !isObject(patch) || !Array.isArray(Array.isArray(patch.layers) ? patch.layers : null)) {
    return null;
  }

  const currentName = String(currentScene.name || "");
  if (String(patch.name || "") !== currentName) {
    return null;
  }

  const currentVersion = sceneVersion(currentScene.version);
  const patchVersion = sceneVersion(patch.version);
  if (currentVersion !== null && patchVersion !== null && patchVersion !== currentVersion) {
    return null;
  }

  const next = applyScenePayload(currentScene);
  if (!isObject(next)) {
    return null;
  }

  const layers = next.layers;
  for (const entry of patch.layers) {
    if (!isObject(entry)) {
      continue;
    }

    const index = normalizeIndex(entry.index);
    if (index === null) {
      continue;
    }

    if (entry.remove) {
      if (index < layers.length) {
        layers[index] = REMOVED_LAYER;
      }
      continue;
    }

    if (Object.prototype.hasOwnProperty.call(entry, "layer")) {
      if (!isObject(entry.layer)) {
        continue;
      }
      while (layers.length <= index) {
        layers.push(REMOVED_LAYER);
      }
      layers[index] = applyScenePayload(entry.layer);
      continue;
    }

    if (!Object.prototype.hasOwnProperty.call(entry, "params")) {
      continue;
    }
    if (!isObject(entry.params)) {
      continue;
    }

    const layer = layers[index];
    if (!isObject(layer) || layer === REMOVED_LAYER) {
      continue;
    }

    const params = isObject(layer.params) ? clonePayload(layer.params) : {};
    layers[index] = {
      ...layer,
      params: {
        ...params,
        ...clonePayload(entry.params)
      }
    };
  }

  next.version = patchVersion !== null ? patchVersion : next.version;
  if (Object.prototype.hasOwnProperty.call(patch, "schema_version")) {
    next.schema_version = patch.schema_version;
  }
  next.layers = layers.filter((layer) => layer !== REMOVED_LAYER);

  return next;
};

export const resolveScenePayload = ({ incomingScene = null, currentScene = null, frameVersion = null } = {}) => {
  if (!isObject(incomingScene) && !isObject(currentScene)) {
    return null;
  }

  if (incomingScene.patch) {
    if (!isObject(currentScene)) {
      return null;
    }

    const expectedVersion = sceneVersion(frameVersion);
    const currentVersion = sceneVersion(currentScene.version);
    if (expectedVersion !== null && currentVersion !== null && expectedVersion !== currentVersion) {
      return applyScenePayload(currentScene);
    }

    return applyScenePatch(currentScene, incomingScene) || applyScenePayload(currentScene);
  }

  if (!isObject(incomingScene)) {
    return applyScenePayload(currentScene);
  }

  return applyScenePayload(incomingScene);
};
