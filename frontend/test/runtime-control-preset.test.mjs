import assert from "node:assert/strict";
import test from "node:test";

import { normalizeRuntimeControlPreset } from "../src/runtime-control-preset.js";

test("normalizeRuntimeControlPreset accepts snake case runtime keys", () => {
  assert.deepEqual(
    normalizeRuntimeControlPreset({
      visual_settings: { visualGain: 3 },
      midi_learn_bindings: { "cc:1:7": { type: "live_control", control: "freeze" } },
    }),
    {
      visualSettings: { visualGain: 3 },
      midiLearnBindings: { "cc:1:7": { type: "live_control", control: "freeze" } },
    },
  );
});

test("normalizeRuntimeControlPreset ignores invalid values", () => {
  assert.deepEqual(
    normalizeRuntimeControlPreset({ visual_settings: [], midiLearnBindings: null }),
    { visualSettings: null, midiLearnBindings: null },
  );
});
