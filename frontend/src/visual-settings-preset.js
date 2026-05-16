export const VISUAL_SETTINGS_PRESET_KEY = "vizcore.visualSettings.v1";
export const VISUAL_SETTINGS_PRESET_VERSION = 1;

export const DEFAULT_VISUAL_SETTINGS = Object.freeze({
  visualGain: 2.5,
  bassBoost: 1.4,
  smoothing: 0.25,
  beatHoldMs: 180,
  wobbleAmount: 1.0,
});

export const VISUAL_SETTING_LIMITS = Object.freeze({
  visualGain: [1, 8],
  bassBoost: [0, 4],
  smoothing: [0, 0.9],
  beatHoldMs: [50, 400],
  wobbleAmount: [0.25, 3],
});

export const normalizeVisualSettings = (value, fallback = DEFAULT_VISUAL_SETTINGS) => {
  const input = value && typeof value === "object" ? value : {};

  return Object.fromEntries(
    Object.entries(DEFAULT_VISUAL_SETTINGS).map(([key, defaultValue]) => {
      const [min, max] = VISUAL_SETTING_LIMITS[key];
      const fallbackValue = Number(fallback?.[key] ?? defaultValue);
      return [key, clampNumber(input[key], min, max, fallbackValue)];
    })
  );
};

export const loadVisualSettingsPreset = (storage, {
  key = VISUAL_SETTINGS_PRESET_KEY,
  fallback = DEFAULT_VISUAL_SETTINGS,
} = {}) => {
  if (!storage) {
    return normalizeVisualSettings(fallback);
  }

  try {
    const rawValue = storage.getItem(key);
    if (!rawValue) {
      return normalizeVisualSettings(fallback);
    }
    return normalizeVisualSettings(JSON.parse(rawValue), fallback);
  } catch {
    return normalizeVisualSettings(fallback);
  }
};

export const saveVisualSettingsPreset = (storage, settings, {
  key = VISUAL_SETTINGS_PRESET_KEY,
} = {}) => {
  const normalized = normalizeVisualSettings(settings);
  if (!storage) {
    return normalized;
  }

  try {
    storage.setItem(key, JSON.stringify(normalized));
  } catch {
    // Ignore storage failures; the active in-memory settings still apply.
  }
  return normalized;
};

export const exportVisualSettingsPreset = (settings) => {
  return JSON.stringify({
    version: VISUAL_SETTINGS_PRESET_VERSION,
    visual_settings: normalizeVisualSettings(settings),
  }, null, 2);
};

export const importVisualSettingsPreset = (rawValue, {
  fallback = DEFAULT_VISUAL_SETTINGS,
} = {}) => {
  try {
    const parsed = typeof rawValue === "string" ? JSON.parse(rawValue) : rawValue;
    const settings = parsed?.visual_settings || parsed?.settings || parsed;
    return normalizeVisualSettings(settings, fallback);
  } catch {
    return normalizeVisualSettings(fallback);
  }
};

export const visualSettingFromUnit = (key, unitValue, fallback = DEFAULT_VISUAL_SETTINGS[key]) => {
  const limits = VISUAL_SETTING_LIMITS[key];
  if (!limits) {
    return Number(fallback ?? 0);
  }

  const [min, max] = limits;
  const amount = clampNumber(unitValue, 0, 1, 0);
  return clampNumber(min + (max - min) * amount, min, max, fallback);
};

const clampNumber = (value, min, max, fallback) => {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) {
    return fallback;
  }
  return Math.min(Math.max(numeric, min), max);
};
