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

test("getBuiltinShader resolves liquid_wobble shader", () => {
  const shader = getBuiltinShader("liquid_wobble");

  assert.equal(shader, BUILTIN_FRAGMENT_SHADERS.liquid_wobble);
  assert.match(shader, /u_beat_pulse/);
  assert.match(shader, /u_fft\[32\]/);
  assert.match(shader, /outColor/);
});

test("getBuiltinShader resolves unyo_geometry shader", () => {
  const shader = getBuiltinShader("unyo_geometry");

  assert.equal(shader, BUILTIN_FRAGMENT_SHADERS.unyo_geometry);
  assert.match(shader, /u_param_seed/);
  assert.match(shader, /u_param_kick/);
  assert.match(shader, /u_beat_pulse/);
  assert.match(shader, /smoothstep\(0\.006, 0\.035, soundEnergy\)/);
  assert.match(shader, /motionTime/);
  assert.match(shader, /sdRegularPolygon/);
});

test("getBuiltinShader resolves added visual preset shaders", () => {
  assert.equal(getBuiltinShader("ruby_crystal"), BUILTIN_FRAGMENT_SHADERS.ruby_crystal);
  assert.match(getBuiltinShader("ruby_crystal"), /rubyPalette/);
  assert.match(getBuiltinShader("ruby_crystal"), /u_global_color/);
  assert.equal(getBuiltinShader("starfield"), BUILTIN_FRAGMENT_SHADERS.starfield);
  assert.match(getBuiltinShader("starfield"), /star/);
  assert.match(getBuiltinShader("starfield"), /u_global_intensity/);
  assert.equal(getBuiltinShader("waveform_ribbon"), BUILTIN_FRAGMENT_SHADERS.waveform_ribbon);
  assert.match(getBuiltinShader("waveform_ribbon"), /u_fft\[32\]/);
  assert.match(getBuiltinShader("waveform_ribbon"), /u_global_intensity/);
  assert.match(getBuiltinShader("waveform_ribbon"), /u_global_color/);
});

test("all builtin shader fixtures satisfy the WebGL2 fragment contract", () => {
  for (const [name, shader] of Object.entries(BUILTIN_FRAGMENT_SHADERS)) {
    assert.match(shader, /#version 300 es/, `${name} declares GLSL ES 3.00`);
    assert.match(shader, /precision mediump float;/, `${name} declares float precision`);
    assert.match(shader, /out vec4 outColor;/, `${name} declares fragment output`);
    assert.match(shader, /void main\(\)/, `${name} declares main`);
    assert.doesNotMatch(shader, /gl_FragColor/, `${name} avoids WebGL1 fragment output`);
  }
});

test("getPostEffectShader resolves known effects and returns null for unknown", () => {
  assert.equal(getPostEffectShader("bloom"), POST_EFFECT_SHADERS.bloom);
  assert.equal(getPostEffectShader("chromatic"), POST_EFFECT_SHADERS.chromatic);
  assert.equal(getPostEffectShader("motion_blur"), POST_EFFECT_SHADERS.motion_blur);
  assert.equal(getPostEffectShader("crt"), POST_EFFECT_SHADERS.crt);
  assert.equal(getPostEffectShader("unknown"), null);
});

test("all post-effect shader fixtures satisfy the WebGL2 fragment contract", () => {
  for (const [name, shader] of Object.entries(POST_EFFECT_SHADERS)) {
    assert.match(shader, /#version 300 es/, `${name} declares GLSL ES 3.00`);
    assert.match(shader, /precision mediump float;/, `${name} declares float precision`);
    assert.match(shader, /in vec2 v_uv;/, `${name} accepts fullscreen UV input`);
    assert.match(shader, /uniform sampler2D u_texture;/, `${name} samples the layer texture`);
    assert.match(shader, /out vec4 outColor;/, `${name} declares fragment output`);
    assert.match(shader, /void main\(\)/, `${name} declares main`);
    assert.doesNotMatch(shader, /gl_FragColor/, `${name} avoids WebGL1 fragment output`);
  }
});
