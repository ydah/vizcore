import test from "node:test";
import assert from "node:assert/strict";

import {
  coerceUniformNumber,
  normalizeBlendMode,
  normalizePaletteColors,
  normalizeSpectrum,
  parseHexColor,
  resolveLayerResolutionScale,
  resolveLayerCssColor,
  resolveLayerRgbColor,
  shaderCacheKeyForLayer,
  shaderGlobalUniformNames,
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

test("shaderGlobalUniformNames supports global_ keys and plain keys", () => {
  assert.deepEqual(shaderGlobalUniformNames("global_intensity"), ["u_global_intensity"]);
  assert.deepEqual(shaderGlobalUniformNames("color"), ["u_global_color"]);
  assert.deepEqual(shaderGlobalUniformNames("midi-color"), ["u_global_midi_color"]);
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

test("normalizeBlendMode resolves supported compositing aliases", () => {
  assert.equal(normalizeBlendMode("normal"), "alpha");
  assert.equal(normalizeBlendMode("additive"), "add");
  assert.equal(normalizeBlendMode("multiply"), "multiply");
  assert.equal(normalizeBlendMode("screen"), "screen");
  assert.equal(normalizeBlendMode("difference"), "difference");
  assert.equal(normalizeBlendMode("unknown"), "alpha");
});

test("normalizePaletteColors filters blank palette entries", () => {
  assert.deepEqual(normalizePaletteColors(["#ff0055", "", "  #00ffff  "]), ["#ff0055", "#00ffff"]);
  assert.deepEqual(normalizePaletteColors("#ff0055"), []);
});

test("parseHexColor converts short and long CSS hex colors", () => {
  assert.deepEqual(parseHexColor("#0fc"), [0, 1, 0.8]);
  assert.deepEqual(parseHexColor("#ff8000"), [1, 128 / 255, 0]);
  assert.equal(parseHexColor("rgb(255, 0, 0)"), null);
});

test("resolveLayerCssColor prefers explicit color then palette", () => {
  assert.equal(resolveLayerCssColor({ color: "#ffffff", palette: ["#ff0055"] }, "#fallback"), "#ffffff");
  assert.equal(resolveLayerCssColor({ palette: ["#ff0055", "#00ffff"] }, "#fallback", 3), "#00ffff");
  assert.equal(resolveLayerCssColor({}, "#fallback"), "#fallback");
});

test("resolveLayerCssColor interpolates between palette stops", () => {
  assert.equal(resolveLayerCssColor({ palette: ["#000000", "#ffffff"] }, "#fallback", 0), "#000000");
  assert.equal(resolveLayerCssColor({ palette: ["#000000", "#ffffff"] }, "#fallback", 1), "#ffffff");
  assert.equal(resolveLayerCssColor({ palette: ["#000000", "#ffffff"] }, "#fallback", 0.5), "#808080");
  assert.equal(resolveLayerCssColor({ palette: ["#000000", "#ffffff", "#000000"] }, "#fallback", 1.5), "#808080");
});

test("resolveLayerCssColor resolves explicit gradient descriptors", () => {
  assert.equal(
    resolveLayerCssColor({
      color: {
        gradient: {
          type: "linear",
          colors: ["#000000", "#ffffff"],
          position: 0.5,
        },
      },
    },
    "#fallback",
    0,
  ), "#808080");

  assert.equal(
    resolveLayerCssColor({
      color: {
        gradient: {
          type: "linear",
          colors: ["#000000", "#7f7f7f", "#ffffff"],
          stops: [0.0, 0.6, 1.0],
          position: 0.75,
        },
      },
    },
    "#fallback",
    0,
  ), "#afafaf");
});

test("resolveLayerRgbColor parses palette colors and falls back for non-hex colors", () => {
  assert.deepEqual(resolveLayerRgbColor({ palette: ["#000", "#ffffff"] }, null, 1), [1, 1, 1]);
  assert.deepEqual(resolveLayerRgbColor({ color: "red" }, [0.1, 0.2, 0.3]), [0.1, 0.2, 0.3]);
});

test("resolveLayerResolutionScale clamps layer and safe-mode scales", () => {
  assert.equal(resolveLayerResolutionScale({ resolution_scale: 0.5 }), 0.5);
  assert.equal(resolveLayerResolutionScale({ resolutionScale: 3 }), 1);
  assert.equal(resolveLayerResolutionScale({ target_resolution_scale: 0.01 }), 0.1);
  assert.equal(resolveLayerResolutionScale({ resolution_scale: 0.5 }, { safeModeActive: true, safeModeScale: 0.5 }), 0.25);
});

test("shaderCacheKeyForLayer includes source and param schema changes", () => {
  const base = shaderCacheKeyForLayer(
    { glsl: "wave.frag", glsl_source: "void main() {}", param_schema: [{ name: "gain", default: 1 }] },
    "gradient_pulse",
    "void main() {}",
  );
  const changedSchema = shaderCacheKeyForLayer(
    { glsl: "wave.frag", glsl_source: "void main() {}", param_schema: [{ name: "gain", default: 2 }] },
    "gradient_pulse",
    "void main() {}",
  );
  const changedSource = shaderCacheKeyForLayer(
    { glsl: "wave.frag", glsl_source: "void main() { }", param_schema: [{ name: "gain", default: 1 }] },
    "gradient_pulse",
    "void main() { }",
  );

  assert.notEqual(base, changedSchema);
  assert.notEqual(base, changedSource);
});
