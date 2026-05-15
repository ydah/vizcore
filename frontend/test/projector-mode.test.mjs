import test from "node:test";
import assert from "node:assert/strict";

import {
  applyProjectorMode,
  controlModeFromBody,
  controlModeFromLocation,
  projectorModeFromBody,
  projectorModeFromLocation,
  projectorModeFromRuntime,
  resolveProjectorMode,
} from "../src/projector-mode.js";

test("projectorModeFromRuntime reads runtime metadata", () => {
  assert.equal(projectorModeFromRuntime({ projector_mode: true }), true);
  assert.equal(projectorModeFromRuntime({ projector_mode: false }), false);
});

test("projectorModeFromBody reads server-rendered body state", () => {
  assert.equal(projectorModeFromBody({ dataset: { projectorMode: "true" } }), true);
  assert.equal(projectorModeFromBody({ dataset: { projectorMode: "false" } }), false);
});

test("controlModeFromBody reads forced control display state", () => {
  assert.equal(controlModeFromBody({ dataset: { displayMode: "control" } }), true);
  assert.equal(controlModeFromBody({ dataset: { displayMode: "projector" } }), false);
});

test("projectorModeFromLocation supports query overrides", () => {
  assert.equal(projectorModeFromLocation({ search: "?projector=1" }), true);
  assert.equal(projectorModeFromLocation({ search: "?mode=projector" }), true);
  assert.equal(projectorModeFromLocation({ search: "?projector=0" }), false);
});

test("controlModeFromLocation supports query overrides", () => {
  assert.equal(controlModeFromLocation({ search: "?control=1" }), true);
  assert.equal(controlModeFromLocation({ search: "?mode=control" }), true);
  assert.equal(controlModeFromLocation({ search: "?control=0" }), false);
});

test("resolveProjectorMode preserves an active projector state", () => {
  assert.equal(resolveProjectorMode({ current: true, runtime: { projector_mode: false } }), true);
  assert.equal(resolveProjectorMode({ runtime: { projector_mode: true } }), true);
});

test("resolveProjectorMode lets control mode override runtime projector mode", () => {
  assert.equal(
    resolveProjectorMode({
      body: { dataset: { displayMode: "control", projectorMode: "false" } },
      current: true,
      runtime: { projector_mode: true },
    }),
    false,
  );
});

test("applyProjectorMode toggles class and body dataset", () => {
  const toggles = [];
  const body = {
    classList: {
      toggle(name, enabled) {
        toggles.push([name, enabled]);
      },
    },
    dataset: {},
  };

  applyProjectorMode(body, true);

  assert.deepEqual(toggles, [["is-projector", true]]);
  assert.equal(body.dataset.projectorMode, "true");
});
