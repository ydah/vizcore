import assert from "node:assert/strict";
import test from "node:test";

import {
  DEFAULT_VISUAL_SETTINGS,
  loadVisualSettingsPreset,
  normalizeVisualSettings,
  saveVisualSettingsPreset
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

const memoryStorage = (initial = {}) => {
  const values = { ...initial };
  return {
    getItem: (key) => values[key] ?? null,
    setItem: (key, value) => {
      values[key] = String(value);
    }
  };
};
