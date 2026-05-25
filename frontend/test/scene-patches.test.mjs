import test from "node:test";
import assert from "node:assert/strict";

import { applyScenePayload, resolveScenePayload } from "../src/scene-patches.js";

test("applyScenePayload normalizes scene payload shape", () => {
  const scene = applyScenePayload({
    name: "basic",
    version: 4,
    layers: null,
    extra: "kept",
  });

  assert.deepEqual(scene, {
    name: "basic",
    version: 4,
    layers: [],
    extra: "kept",
  });
});

test("resolveScenePayload applies full scene when patch flag is not set", () => {
  const full = {
    name: "basic",
    version: 1,
    layers: [{ name: "wireframe", params: { opacity: 0.3 } }],
  };
  const frame = resolveScenePayload({
    incomingScene: full,
    currentScene: null,
    frameVersion: 1,
  });

  assert.deepEqual(frame, full);
});

test("resolveScenePayload applies param patch to current scene", () => {
  const current = {
    name: "basic",
    version: 2,
    layers: [{ name: "wireframe", params: { opacity: 0.2 } }],
  };
  const patch = {
    patch: true,
    name: "basic",
    version: 2,
    schema_version: "vizcore.scene.v1",
    layers: [{ index: 0, params: { opacity: 0.8 } }],
  };
  const next = resolveScenePayload({
    incomingScene: patch,
    currentScene: current,
    frameVersion: 2,
  });

  assert.deepEqual(next, {
    name: "basic",
    version: 2,
    schema_version: "vizcore.scene.v1",
    layers: [{ name: "wireframe", params: { opacity: 0.8 } }],
  });
});

test("resolveScenePayload ignores patch when scene name changes", () => {
  const current = {
    name: "basic",
    version: 2,
    layers: [{ name: "wireframe", params: { opacity: 0.2 } }],
  };
  const patch = {
    patch: true,
    name: "intro",
    version: 2,
    layers: [{ index: 0, params: { opacity: 0.8 } }],
  };

  assert.deepEqual(
    resolveScenePayload({
      incomingScene: patch,
      currentScene: current,
      frameVersion: 2,
    }),
    current
  );
});

test("resolveScenePayload falls back to current scene when patch version mismatches", () => {
  const current = {
    name: "basic",
    version: 2,
    layers: [{ name: "wireframe", params: { opacity: 0.2 } }],
  };
  const patch = {
    patch: true,
    name: "basic",
    version: 3,
    layers: [{ index: 0, params: { opacity: 0.8 } }],
  };

  const next = resolveScenePayload({
    incomingScene: patch,
    currentScene: current,
    frameVersion: 2,
  });

  assert.deepEqual(next, current);
});
