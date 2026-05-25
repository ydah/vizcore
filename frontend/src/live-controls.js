const finiteFloat = (value) => {
  const numeric = Number(value);
  return Number.isFinite(numeric) ? numeric : null;
};

const createLiveControlEntry = (enabled = false, fade = undefined, release = undefined) => {
  return compactLiveControlEntry({
    enabled: !!enabled,
    fade: finiteFloat(fade),
    release: finiteFloat(release),
  });
};

const compactLiveControlEntry = (entry) => {
  const output = { ...entry };
  if (!Object.prototype.hasOwnProperty.call(output, "fade")) {
    return output;
  }
  if (output.fade === null || output.fade === undefined) {
    delete output.fade;
  }
  if (output.release === null || output.release === undefined) {
    delete output.release;
  }
  return output;
};

const normalizeLiveControlState = (value) => {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    if (Object.prototype.hasOwnProperty.call(value, "value")) {
      return compactLiveControlEntry(createLiveControlEntry(
        !!value.value,
        value.fade,
        value.release
      ));
    }

    return compactLiveControlEntry(createLiveControlEntry(
      Object.prototype.hasOwnProperty.call(value, "enabled") ? !!value.enabled : false,
      value.fade,
      value.release
    ));
  }

  return compactLiveControlEntry(createLiveControlEntry(!!value));
};

export const createLiveControlState = () => ({
  blackout: createLiveControlEntry(false),
  freeze: createLiveControlEntry(false),
});

export const isLiveControlEnabled = (state) => {
  if (!state) {
    return false;
  }

  if (typeof state === "object") {
    return !!state.enabled;
  }

  return !!state;
};

export const isLiveControlActive = (state) => {
  if (!state || typeof state !== "object" || Array.isArray(state)) {
    return isLiveControlEnabled(state);
  }

  return !!state.enabled;
};

export const toggleLiveControl = (state, key) => {
  const control = String(key || "");
  if (control !== "blackout" && control !== "freeze") {
    return { ...state };
  }

  const current = normalizeLiveControlState(state?.[control]);
  return {
    ...state,
    [control]: {
      ...current,
      enabled: !current.enabled,
    },
  };
};

export const normalizeLiveControlPayload = (state) => normalizeLiveControlState(state);

export const liveControlStatusText = (state) => {
  const values = [];
  if (isLiveControlActive(state?.blackout)) values.push("Blackout");
  if (isLiveControlActive(state?.freeze)) values.push("Freeze");
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
    if (control !== "blackout" && control !== "freeze") {
      return null;
    }

    const payload = { type, control };
    if (Object.prototype.hasOwnProperty.call(action, "value")) {
      payload.value = action.value;
    }

    const fade = finiteFloat(action?.fade);
    if (fade !== null) {
      payload.fade = fade;
    }

    const release = finiteFloat(action?.release);
    if (release !== null) {
      payload.release = release;
    }

    return payload;
  }

  return null;
};

const normalizeTransitionEffect = (effect) => {
  if (!effect) {
    return null;
  }
  if (typeof effect === "string" || typeof effect === "number" || typeof effect === "symbol") {
    return { name: String(effect) };
  }
  if (typeof effect !== "object" || Array.isArray(effect)) {
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
