import assert from "node:assert/strict";
import test from "node:test";

import {
  buildSpectrogramPixels,
  normalizeSpectrogramBins,
  normalizeSpectrogramGain,
  normalizeSpectrogramHistory,
  normalizeSpectrogramScroll,
  normalizeSpectrogramSpectrum,
  spectrogramColor,
} from "../src/visuals/spectrogram-renderer.js";

test("spectrogram normalizers clamp layer params", () => {
  assert.equal(normalizeSpectrogramScroll("horizontal"), "horizontal");
  assert.equal(normalizeSpectrogramScroll("diagonal"), "vertical");
  assert.equal(normalizeSpectrogramBins(4), 16);
  assert.equal(normalizeSpectrogramBins(999), 256);
  assert.equal(normalizeSpectrogramHistory(4), 16);
  assert.equal(normalizeSpectrogramHistory(999), 512);
  assert.equal(normalizeSpectrogramGain("2.5"), 2.5);
  assert.equal(normalizeSpectrogramGain("bad"), 1);
});

test("normalizeSpectrogramSpectrum interpolates and clamps FFT values", () => {
  const spectrum = normalizeSpectrogramSpectrum([0, 0.5, 2], 16, 2);

  assert.equal(spectrum.length, 16);
  assert.equal(spectrum[0], 0);
  assert.equal(spectrum.at(-1), 1);
  assert.ok(spectrum.every((value) => value >= 0 && value <= 1));
});

test("buildSpectrogramPixels maps vertical history to rows", () => {
  const image = buildSpectrogramPixels({
    history: [
      [0, 0],
      [1, 0],
    ],
    bins: 16,
    historySize: 16,
    scroll: "vertical",
  });

  assert.equal(image.width, 16);
  assert.equal(image.height, 16);
  assert.equal(image.pixels.length, 16 * 16 * 4);
  assert.equal(image.pixels[((14 * 16) + 0) * 4 + 3], 0);
  assert.equal(image.pixels[((15 * 16) + 0) * 4 + 3], 255);
});

test("buildSpectrogramPixels maps horizontal history to columns", () => {
  const image = buildSpectrogramPixels({
    history: [[1, 0]],
    bins: 16,
    historySize: 16,
    scroll: "horizontal",
  });

  assert.equal(image.width, 16);
  assert.equal(image.height, 16);
  assert.equal(image.pixels[((15 * 16) + 15) * 4 + 3], 255);
});

test("spectrogramColor returns RGBA heatmap colors", () => {
  assert.deepEqual(spectrogramColor(0)[3], 0);
  assert.deepEqual(spectrogramColor(1)[3], 255);
  assert.ok(spectrogramColor(1)[0] > spectrogramColor(0)[0]);
});
