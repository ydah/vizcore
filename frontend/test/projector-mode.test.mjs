import test from "node:test";
import assert from "node:assert/strict";

import {
  applyProjectorMode,
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

test("projectorModeFromLocation supports query overrides", () => {
  assert.equal(projectorModeFromLocation({ search: "?projector=1" }), true);
  assert.equal(projectorModeFromLocation({ search: "?mode=projector" }), true);
  assert.equal(projectorModeFromLocation({ search: "?projector=0" }), false);
});

test("resolveProjectorMode preserves an active projector state", () => {
  assert.equal(resolveProjectorMode({ current: true, runtime: { projector_mode: false } }), true);
  assert.equal(resolveProjectorMode({ runtime: { projector_mode: true } }), true);
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
