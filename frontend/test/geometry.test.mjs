import test from "node:test";
import assert from "node:assert/strict";

import { buildRadialBlobLines, estimateDeformFromSpectrum } from "../src/visuals/geometry.js";

test("buildRadialBlobLines returns line segment coordinates", () => {
  const points = buildRadialBlobLines({
    time: 1.0,
    params: { segments: 32, radius: 0.4, wobble: 0.2 },
    audio: {
      amplitude: 0.5,
      bands: { low: 0.7, mid: 0.2, high: 0.1 },
      fft: Array.from({ length: 32 }, () => 0.2),
    },
  });

  assert.equal(points.length, 32 * 4);
  assert.ok(points.every((value) => Number.isFinite(value)));
});

test("estimateDeformFromSpectrum averages numeric spectrum values", () => {
  const deform = estimateDeformFromSpectrum([0.2, 0.4]);

  assert.ok(Math.abs(deform - 0.3) < 0.00001);
});
