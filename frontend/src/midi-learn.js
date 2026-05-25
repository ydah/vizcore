export const MIDI_LEARN_BINDINGS_KEY = "vizcore.midiLearnBindings.v1";

const ACTION_TYPES = new Set(["switch_scene", "live_control", "visual_setting"]);
const LIVE_CONTROLS = new Set(["blackout", "freeze"]);
const VISUAL_SETTING_KEYS = new Set(["visualGain", "bassBoost", "smoothing", "beatHoldMs", "wobbleAmount"]);

export const loadMidiLearnBindings = (storage, {
  key = MIDI_LEARN_BINDINGS_KEY,
} = {}) => {
  if (!storage) {
    return {};
  }

  try {
    return normalizeMidiLearnBindings(JSON.parse(storage.getItem(key) || "{}"));
  } catch {
    return {};
  }
};

export const saveMidiLearnBindings = (storage, bindings, {
  key = MIDI_LEARN_BINDINGS_KEY,
} = {}) => {
  const normalized = normalizeMidiLearnBindings(bindings);
  if (!storage) {
    return normalized;
  }

  try {
    storage.setItem(key, JSON.stringify(normalized));
  } catch {
    // Ignore storage failures; learned bindings still work for this session.
  }
  return normalized;
};

export const normalizeMidiLearnBindings = (bindings) => {
  const input = bindings && typeof bindings === "object" ? bindings : {};
  const normalized = {};

  for (const [signature, action] of Object.entries(input)) {
    const safeSignature = normalizeMidiSignature(signature);
    const safeAction = normalizeMidiAction(action);
    if (!safeSignature || !safeAction) {
      continue;
    }
    normalized[safeSignature] = safeAction;
  }

  return normalized;
};

export const upsertMidiLearnBinding = (bindings, signature, action) => {
  const safeSignature = normalizeMidiSignature(signature);
  const safeAction = normalizeMidiAction(action);
  const next = normalizeMidiLearnBindings(bindings);

  if (safeSignature && safeAction) {
    next[safeSignature] = safeAction;
  }

  return next;
};

export const midiMessageSignature = (data) => {
  const bytes = normalizeMidiBytes(data);
  if (!bytes.length) {
    return null;
  }

  const status = bytes[0];
  const command = status & 0xf0;
  const channel = (status & 0x0f) + 1;
  if (command === 0x80 || command === 0x90) {
    return `note:${channel}:${bytes[1] ?? 0}`;
  }
  if (command === 0xb0) {
    return `cc:${channel}:${bytes[1] ?? 0}`;
  }
  if (command === 0xc0) {
    return `pc:${channel}:${bytes[1] ?? 0}`;
  }
  return `raw:${channel}:${status}:${bytes[1] ?? 0}`;
};

export const midiMessageActive = (data) => {
  const bytes = normalizeMidiBytes(data);
  if (!bytes.length) {
    return false;
  }

  const command = bytes[0] & 0xf0;
  if (command === 0x80) {
    return false;
  }
  if (command === 0x90) {
    return Number(bytes[2] || 0) > 0;
  }
  return true;
};

export const midiMessageUnitValue = (data) => {
  const bytes = normalizeMidiBytes(data);
  if (!bytes.length) {
    return 0;
  }

  const command = bytes[0] & 0xf0;
  if (command === 0xb0 || command === 0x90 || command === 0x80) {
    return clampUnit(Number(bytes[2] || 0) / 127);
  }
  if (command === 0xc0) {
    return clampUnit(Number(bytes[1] || 0) / 127);
  }
  return 1;
};

export const midiLearnActionLabel = (action) => {
  const safeAction = normalizeMidiAction(action);
  if (!safeAction) {
    return "Unknown";
  }

  if (safeAction.type === "switch_scene") {
    return safeAction.effect
      ? `Switch scene: ${safeAction.scene} (${safeAction.effect?.name || "with effect"})`
      : `Switch scene: ${safeAction.scene}`;
  }
  if (safeAction.type === "live_control") {
    return `Toggle ${safeAction.control}`;
  }
  return `Control ${visualSettingLabel(safeAction.key)}`;
};

export const midiSignatureLabel = (signature) => {
  const [kind, channel, value] = String(signature || "").split(":");
  if (kind === "note") return `Note ${value} ch ${channel}`;
  if (kind === "cc") return `CC ${value} ch ${channel}`;
  if (kind === "pc") return `Program ${value} ch ${channel}`;
  return signature || "unknown";
};

const normalizeMidiAction = (action) => {
  if (!action || typeof action !== "object") {
    return null;
  }

  const type = String(action.type || "");
  if (!ACTION_TYPES.has(type)) {
    return null;
  }

  if (type === "switch_scene") {
    const scene = String(action.scene || "").trim();
    if (!scene) {
      return null;
    }
    const effect = normalizeTransitionEffect(action.effect);
    return effect ? { type, scene, effect } : { type, scene };
  }

  if (type === "live_control") {
    const control = String(action.control || "").trim();
    return LIVE_CONTROLS.has(control) ? { type, control } : null;
  }

  const key = String(action.key || "").trim();
  return VISUAL_SETTING_KEYS.has(key) ? { type, key } : null;
};

const normalizeMidiSignature = (signature) => {
  const value = String(signature || "").trim().toLowerCase();
  return value.includes(":") ? value : null;
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

const normalizeMidiBytes = (data) => {
  if (Array.isArray(data) || ArrayBuffer.isView(data)) {
    return Array.from(data).map((value) => Number(value) || 0);
  }
  return [];
};

const visualSettingLabel = (key) => {
  switch (key) {
    case "visualGain":
      return "Visual Gain";
    case "bassBoost":
      return "Bass Boost";
    case "smoothing":
      return "Smoothing";
    case "beatHoldMs":
      return "Beat Hold";
    case "wobbleAmount":
      return "Wobble";
    default:
      return key;
  }
};

const clampUnit = (value) => Math.min(Math.max(Number(value) || 0, 0), 1);
