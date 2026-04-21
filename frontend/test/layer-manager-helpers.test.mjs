import test from "node:test";
import assert from "node:assert/strict";

import {
  coerceUniformNumber,
  normalizeSpectrum,
  shaderParamUniformNames,
} from "../src/renderer/layer-manager.js";

test("coerceUniformNumber converts numbers, numeric strings and booleans", () => {
  assert.equal(coerceUniformNumber(0.4), 0.4);
  assert.equal(coerceUniformNumber("0.75"), 0.75);
  assert.equal(coerceUniformNumber(true), 1);
  assert.equal(coerceUniformNumber(false), 0);
});

test("coerceUniformNumber rejects non-finite and non-numeric values", () => {
  assert.equal(coerceUniformNumber(Number.NaN), null);
  assert.equal(coerceUniformNumber(Infinity), null);
  assert.equal(coerceUniformNumber({}), null);
  assert.equal(coerceUniformNumber([]), null);
});

test("shaderParamUniformNames supports plain and legacy param_ targets", () => {
  assert.deepEqual(shaderParamUniformNames("intensity"), ["u_param_intensity"]);
  assert.deepEqual(shaderParamUniformNames("param_intensity"), [
    "u_param_param_intensity",
    "u_param_intensity",
  ]);
  assert.deepEqual(shaderParamUniformNames("bass-gain"), ["u_param_bass_gain"]);
});

test("normalizeSpectrum returns a clamped Float32Array with fixed length", () => {
  const spectrum = normalizeSpectrum([0.2, 2, -1, Number.NaN], 6);

  assert.equal(spectrum.length, 6);
  assert.ok(Math.abs(spectrum[0] - 0.2) < 0.00001);
  assert.equal(spectrum[1], 1);
  assert.equal(spectrum[2], 0);
  assert.equal(spectrum[3], 0);
  assert.equal(spectrum[4], 0);
  assert.equal(spectrum[5], 0);
});
