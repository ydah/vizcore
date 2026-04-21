import test from "node:test";
import assert from "node:assert/strict";

import { applyVisualSettings } from "../src/renderer/engine.js";

test("applyVisualSettings boosts and clamps audio values", () => {
  const audio = { amplitude: 0.4, bands: { sub: 0.2, low: 0.3, mid: 0.4, high: 0.5 } };
  const result = applyVisualSettings({
    audio,
    settings: { visualGain: 3, bassBoost: 4, smoothing: 0, wobbleAmount: 1.5 },
  });

  assert.equal(result.amplitude, 1);
  assert.equal(result.bands.low, 1);
  assert.equal(result.bands.mid, 1);
  assert.equal(result.visual_gain, 3);
  assert.equal(result.wobble_amount, 1.5);
});

test("applyVisualSettings smooths amplitude and bands", () => {
  const previous = { amplitude: 0, bands: { sub: 0, low: 0, mid: 0, high: 0 } };
  const audio = { amplitude: 1, bands: { sub: 1, low: 1, mid: 1, high: 1 } };
  const result = applyVisualSettings({
    audio,
    previous,
    settings: { visualGain: 1, bassBoost: 1, smoothing: 0.5, wobbleAmount: 1 },
  });

  assert.equal(result.amplitude, 0.5);
  assert.equal(result.bands.low, 0.5);
});
