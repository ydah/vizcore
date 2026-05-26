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
      sceneOverrides: {},
    },
  );
});

test("normalizeRuntimeControlPreset ignores invalid values", () => {
  assert.deepEqual(
    normalizeRuntimeControlPreset({ visual_settings: [], midiLearnBindings: null }),
    { visualSettings: null, midiLearnBindings: null, sceneOverrides: {} },
  );
});

test("normalizeRuntimeControlPreset parses scene overrides", () => {
  assert.deepEqual(
    normalizeRuntimeControlPreset({
      sceneOverrides: {
        build: {
          visualSettings: { visualGain: 5 },
          midiLearnBindings: { "cc:1:5": { type: "live_control", control: "blackout" } },
        },
        drop: {
          midiLearnBindings: { "note:1:36": { type: "switch_scene", scene: "drop" } },
        },
      },
    }),
    {
      visualSettings: null,
      midiLearnBindings: null,
      sceneOverrides: {
        build: {
          visualSettings: { visualGain: 5 },
          midiLearnBindings: { "cc:1:5": { type: "live_control", control: "blackout" } },
        },
        drop: {
          midiLearnBindings: { "note:1:36": { type: "switch_scene", scene: "drop" } },
        },
      },
    },
  );
});

test("normalizeRuntimeControlPreset accepts camelCase scene override keys", () => {
  assert.deepEqual(
    normalizeRuntimeControlPreset({
      scene_overrides: {
        Build: {
          visual_settings: { bassBoost: 2 },
          midiLearnBindings: {},
          midi_learn_bindings: { "cc:2:5": { type: "live_control", control: "freeze" } },
        },
        drop: {
          midiLearnBindings: null,
        },
      },
    }),
    {
      visualSettings: null,
      midiLearnBindings: null,
      sceneOverrides: {
        Build: {
          visualSettings: { bassBoost: 2 },
          midiLearnBindings: { "cc:2:5": { type: "live_control", control: "freeze" } },
        },
      },
    },
  );
});
