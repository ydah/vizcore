import test from "node:test";
import assert from "node:assert/strict";

import { applyVisualSettings } from "../src/renderer/engine.js";

test("applyVisualSettings boosts and clamps audio values", () => {
  const audio = {
    amplitude: 0.4,
    bands: { sub: 0.2, low: 0.3, mid: 0.4, high: 0.5 },
    onset: 0.5,
    onsets: { sub: 0.1, low: 0.2, mid: 0.3, high: 0.4 },
    drums: { kick: 0.2, snare: 0.3, hihat: 0.4 },
  };
  const result = applyVisualSettings({
    audio,
    settings: { visualGain: 3, bassBoost: 4, smoothing: 0, wobbleAmount: 1.5 },
  });

  assert.equal(result.amplitude, 1);
  assert.equal(result.bands.low, 1);
  assert.equal(result.bands.mid, 1);
  assert.equal(result.onset, 1);
  assert.equal(result.onsets.low, 0.8);
  assert.equal(result.onsets.high, 1);
  assert.equal(result.drums.kick, 0.8);
  assert.equal(result.drums.hihat, 1);
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

test("applyVisualSettings does not smooth silent frames", () => {
  const previous = { amplitude: 0.8, bands: { sub: 0.7, low: 0.7, mid: 0.7, high: 0.7 }, beat_pulse: 0.5 };
  const audio = {
    amplitude: 0,
    bands: { sub: 0, low: 0, mid: 0, high: 0 },
    beat: false,
    beat_pulse: 0,
  };
  const result = applyVisualSettings({
    audio,
    previous,
    settings: { visualGain: 2.5, bassBoost: 1.4, smoothing: 0.5, wobbleAmount: 1 },
  });

  assert.equal(result.amplitude, 0);
  assert.equal(result.bands.low, 0);
  assert.equal(result.beat_pulse, 0);
});
