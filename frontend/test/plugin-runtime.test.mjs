import assert from "node:assert/strict";
import test from "node:test";

import {
  installGlobalPluginRuntime,
  normalizePluginLineOutput,
  registerLayerRenderer,
  registeredLayerRendererTypes,
  resolveLayerRenderer,
  unregisterLayerRenderer,
} from "../src/plugin-runtime.js";

test("registerLayerRenderer stores renderers by normalized type", () => {
  const renderer = () => ({ points: [-1, 0, 1, 0] });

  assert.equal(registerLayerRenderer("Laser_Grid", renderer), true);
  assert.equal(resolveLayerRenderer("laser_grid"), renderer);
  assert.ok(registeredLayerRendererTypes().includes("laser_grid"));

  unregisterLayerRenderer("laser_grid");
});

test("normalizePluginLineOutput accepts finite line points and rgb colors", () => {
  assert.deepEqual(
    normalizePluginLineOutput({ points: [-1, 0, 1, 0, Number.NaN], color: [1.2, 0.5, -1] }),
    { kind: "lines", points: [-1, 0, 1, 0], color: [1, 0.5, 0] },
  );
  assert.equal(normalizePluginLineOutput({ kind: "triangles", points: [-1, 0, 1, 0] }), null);
});

test("installGlobalPluginRuntime exposes plugin hooks", () => {
  let dispatched = false;
  class Event {
    constructor(type) {
      this.type = type;
    }
  }
  const target = {
    Event,
    dispatchEvent(event) {
      dispatched = event.type === "vizcore:plugins-ready";
    },
  };
  const runtime = installGlobalPluginRuntime(target);

  assert.equal(typeof runtime.registerLayerRenderer, "function");
  assert.equal(target.VizcorePlugins, runtime);
  assert.equal(dispatched, true);
});
