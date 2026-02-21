import test from "node:test";
import assert from "node:assert/strict";

import { BUILTIN_FRAGMENT_SHADERS, getBuiltinShader } from "../src/shaders/builtins.js";
import { POST_EFFECT_SHADERS, getPostEffectShader } from "../src/shaders/post-effects.js";

test("getBuiltinShader falls back to default shader", () => {
  assert.equal(getBuiltinShader(), BUILTIN_FRAGMENT_SHADERS.default);
  assert.equal(getBuiltinShader("missing_shader"), BUILTIN_FRAGMENT_SHADERS.default);
});

test("getBuiltinShader resolves known shader keys", () => {
  const shader = getBuiltinShader("gradient_pulse");
  assert.equal(shader, BUILTIN_FRAGMENT_SHADERS.gradient_pulse);
  assert.match(shader, /outColor/);
});

test("getPostEffectShader resolves known effects and returns null for unknown", () => {
  assert.equal(getPostEffectShader("bloom"), POST_EFFECT_SHADERS.bloom);
  assert.equal(getPostEffectShader("chromatic"), POST_EFFECT_SHADERS.chromatic);
  assert.equal(getPostEffectShader("unknown"), null);
});
