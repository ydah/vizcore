import assert from "node:assert/strict";
import test from "node:test";

import {
  DEFAULT_VISUAL_SETTINGS,
  exportVisualSettingsPreset,
  importVisualSettingsPreset,
  loadVisualSettingsPreset,
  normalizeVisualSettings,
  saveVisualSettingsPreset,
  visualSettingFromUnit
} from "../src/visual-settings-preset.js";

test("normalizeVisualSettings clamps values and fills missing defaults", () => {
  assert.deepEqual(
    normalizeVisualSettings({
      visualGain: 99,
      bassBoost: -1,
      smoothing: 0.5,
      beatHoldMs: "bad",
      wobbleAmount: 2
    }),
    {
      visualGain: 8,
      bassBoost: 0,
      smoothing: 0.5,
      beatHoldMs: DEFAULT_VISUAL_SETTINGS.beatHoldMs,
      wobbleAmount: 2
    }
  );
});

test("loadVisualSettingsPreset returns saved settings when present", () => {
  const storage = memoryStorage({
    "vizcore.visualSettings.v1": JSON.stringify({
      visualGain: 3,
      bassBoost: 2,
      smoothing: 0.4,
      beatHoldMs: 200,
      wobbleAmount: 1.5
    })
  });

  assert.deepEqual(loadVisualSettingsPreset(storage), {
    visualGain: 3,
    bassBoost: 2,
    smoothing: 0.4,
    beatHoldMs: 200,
    wobbleAmount: 1.5
  });
});

test("saveVisualSettingsPreset stores normalized settings", () => {
  const storage = memoryStorage();
  const saved = saveVisualSettingsPreset(storage, { visualGain: 9, bassBoost: 2 });

  assert.equal(saved.visualGain, 8);
  assert.equal(JSON.parse(storage.getItem("vizcore.visualSettings.v1")).visualGain, 8);
});

test("exportVisualSettingsPreset serializes portable preset JSON", () => {
  const json = exportVisualSettingsPreset({ visualGain: 3, wobbleAmount: 2 });
  const parsed = JSON.parse(json);

  assert.equal(parsed.version, 1);
  assert.equal(parsed.visual_settings.visualGain, 3);
  assert.equal(parsed.visual_settings.wobbleAmount, 2);
});

test("importVisualSettingsPreset accepts wrapped or raw settings", () => {
  const wrapped = importVisualSettingsPreset(JSON.stringify({
    visual_settings: { visualGain: 4, bassBoost: 2 },
  }));
  const raw = importVisualSettingsPreset(JSON.stringify({ visualGain: 5, bassBoost: 1 }));

  assert.equal(wrapped.visualGain, 4);
  assert.equal(raw.visualGain, 5);
});

test("visualSettingFromUnit maps midi values into setting limits", () => {
  assert.equal(visualSettingFromUnit("visualGain", 0), 1);
  assert.equal(visualSettingFromUnit("visualGain", 1), 8);
  assert.equal(visualSettingFromUnit("wobbleAmount", 0.5), 1.625);
});

const memoryStorage = (initial = {}) => {
  const values = { ...initial };
  return {
    getItem: (key) => values[key] ?? null,
    setItem: (key, value) => {
      values[key] = String(value);
    }
  };
};
