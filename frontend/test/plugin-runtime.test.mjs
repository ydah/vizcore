import assert from "node:assert/strict";
import test from "node:test";

import {
  VIZCORE_PLUGIN_API_VERSION,
  installGlobalPluginRuntime,
  normalizePluginLineOutput,
  normalizePluginShaderOutput,
  registerLayerRenderer,
  registerShaderRenderer,
  registeredLayerRendererTypes,
  registeredShaderRendererTypes,
  resolveLayerRenderer,
  resolveShaderRenderer,
  unregisterLayerRenderer,
  unregisterShaderRenderer,
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

test("registerShaderRenderer stores renderers by normalized type", () => {
  const renderer = () => ({ kind: "shader", fragmentShader: "void main() {}" });

  assert.equal(registerShaderRenderer("Laser_Shader", renderer), true);
  assert.equal(resolveShaderRenderer("laser_shader"), renderer);
  assert.ok(registeredShaderRendererTypes().includes("laser_shader"));

  unregisterShaderRenderer("laser_shader");
});

test("normalizePluginShaderOutput accepts shader strings and objects", () => {
  assert.deepEqual(
    normalizePluginShaderOutput("  void main() {}  "),
    { kind: "shader", fragmentShader: "void main() {}", cacheKey: "plugin-shader" },
  );
  assert.deepEqual(
    normalizePluginShaderOutput({ kind: "shader", source: "void mainImage() {}", name: "laser" }),
    { kind: "shader", fragmentShader: "void mainImage() {}", cacheKey: "laser" },
  );
  assert.equal(normalizePluginShaderOutput({ kind: "lines", source: "void main() {}" }), null);
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

  assert.equal(runtime.apiVersion, VIZCORE_PLUGIN_API_VERSION);
  assert.equal(typeof runtime.registerLayerRenderer, "function");
  assert.equal(typeof runtime.resolveLayerRenderer, "function");
  assert.equal(typeof runtime.registerShaderRenderer, "function");
  assert.equal(typeof runtime.resolveShaderRenderer, "function");
  assert.equal(target.VizcorePlugins, runtime);
  assert.equal(dispatched, true);
});
