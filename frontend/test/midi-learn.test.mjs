import assert from "node:assert/strict";
import test from "node:test";

import {
  loadMidiLearnBindings,
  midiLearnActionLabel,
  midiMessageActive,
  midiMessageSignature,
  midiMessageUnitValue,
  midiSignatureLabel,
  saveMidiLearnBindings,
  upsertMidiLearnBinding,
} from "../src/midi-learn.js";

test("midiMessageSignature normalizes note cc and program change messages", () => {
  assert.equal(midiMessageSignature([0x90, 60, 127]), "note:1:60");
  assert.equal(midiMessageSignature([0x81, 61, 0]), "note:2:61");
  assert.equal(midiMessageSignature([0xb2, 7, 64]), "cc:3:7");
  assert.equal(midiMessageSignature([0xc3, 9]), "pc:4:9");
});

test("midiMessageActive ignores note off and zero velocity note on", () => {
  assert.equal(midiMessageActive([0x90, 60, 0]), false);
  assert.equal(midiMessageActive([0x80, 60, 127]), false);
  assert.equal(midiMessageActive([0x90, 60, 127]), true);
  assert.equal(midiMessageActive([0xb0, 1, 0]), true);
});

test("midiMessageUnitValue maps velocity and cc values", () => {
  assert.equal(midiMessageUnitValue([0x90, 60, 127]), 1);
  assert.equal(midiMessageUnitValue([0xb0, 1, 64]), 64 / 127);
});

test("upsertMidiLearnBinding normalizes actions and keeps existing bindings", () => {
  const bindings = upsertMidiLearnBinding(
    { "cc:1:2": { type: "visual_setting", key: "visualGain" } },
    "note:1:60",
    { type: "switch_scene", scene: "drop" },
  );

  assert.deepEqual(bindings, {
    "cc:1:2": { type: "visual_setting", key: "visualGain" },
    "note:1:60": { type: "switch_scene", scene: "drop" },
  });
});

test("loadMidiLearnBindings and saveMidiLearnBindings round trip valid bindings", () => {
  const storage = memoryStorage();
  const saved = saveMidiLearnBindings(storage, {
    "cc:1:1": { type: "visual_setting", key: "bassBoost" },
    "bad": { type: "switch_scene", scene: "" },
  });

  assert.deepEqual(saved, {
    "cc:1:1": { type: "visual_setting", key: "bassBoost" },
  });
  assert.deepEqual(loadMidiLearnBindings(storage), saved);
});

test("midi labels summarize bindings for HUD text", () => {
  assert.equal(midiSignatureLabel("cc:2:7"), "CC 7 ch 2");
  assert.equal(midiLearnActionLabel({ type: "live_control", control: "freeze" }), "Toggle freeze");
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
