export const createLiveControlState = () => ({
  blackout: false,
  freeze: false,
});

export const toggleLiveControl = (state, key) => {
  const control = String(key || "");
  if (control !== "blackout" && control !== "freeze") {
    return { ...state };
  }

  return {
    ...state,
    [control]: !state?.[control],
  };
};

export const liveControlStatusText = (state) => {
  const values = [];
  if (state?.blackout) values.push("Blackout");
  if (state?.freeze) values.push("Freeze");
  return values.length ? `Live: ${values.join(" + ")}` : "Live: output";
};

export const shortcutActionForKey = (event) => {
  if (isEditableShortcutTarget(event?.target)) {
    return null;
  }

  const key = String(event?.key || "").toLowerCase();
  if (key === "b") return "blackout";
  if (key === "f") return "freeze";
  return null;
};

export const shortcutSceneIndexForKey = (event, sceneCount) => {
  if (isEditableShortcutTarget(event?.target)) {
    return null;
  }

  const index = Number.parseInt(String(event?.key || ""), 10) - 1;
  if (!Number.isInteger(index) || index < 0 || index >= 9 || index >= sceneCount) {
    return null;
  }

  return index;
};

export const keyboardActionForKey = (event, mappings) => {
  if (isEditableShortcutTarget(event?.target)) {
    return null;
  }

  const key = normalizeShortcutKey(event?.key);
  if (!key) {
    return null;
  }

  const mapping = normalizeKeyboardMappings(mappings).find((entry) => entry.key === key);
  return mapping?.action || null;
};

export const normalizeKeyboardMappings = (mappings) => {
  if (!Array.isArray(mappings)) {
    return [];
  }

  return mappings.flatMap((entry) => {
    const key = normalizeShortcutKey(entry?.key);
    const action = normalizeKeyboardAction(entry?.action);
    if (!key || !action) {
      return [];
    }

    return [{ key, action }];
  });
};

export const isTapTempoShortcut = (event, configuredKey) => {
  if (isEditableShortcutTarget(event?.target)) {
    return false;
  }

  const key = normalizeShortcutKey(configuredKey);
  if (!key) {
    return false;
  }

  return normalizeShortcutKey(event?.key) === key;
};

export const normalizeShortcutKey = (value) => {
  const raw = String(value || "");
  if (raw === " ") {
    return "space";
  }

  const key = raw.trim().toLowerCase();
  if (key === "spacebar") {
    return "space";
  }

  return key;
};

const normalizeKeyboardAction = (action) => {
  const type = String(action?.type || "").trim();
  if (type === "switch_scene") {
    const scene = String(action?.scene || "").trim();
    if (!scene) {
      return null;
    }
    const effect = normalizeTransitionEffect(action?.effect);
    return effect ? { type, scene, effect } : { type, scene };
  }

  if (type === "live_control") {
    const control = String(action?.control || "").trim();
    return control === "blackout" || control === "freeze" ? { type, control } : null;
  }

  return null;
};

const normalizeTransitionEffect = (effect) => {
  if (!effect || typeof effect !== "object" || Array.isArray(effect)) {
    return null;
  }

  return effect;
};

export const isEditableShortcutTarget = (target) => {
  if (!target) {
    return false;
  }

  const tagName = String(target.tagName || "").toLowerCase();
  return tagName === "input"
    || tagName === "textarea"
    || tagName === "select"
    || target.isContentEditable === true;
};
