import test from "node:test";
import assert from "node:assert/strict";

import {
  coerceUniformNumber,
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
