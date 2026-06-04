import test from "node:test";
import assert from "node:assert/strict";

import { buildAudioInspectorState, formatMeterValue } from "../src/audio-inspector.js";

test("buildAudioInspectorState clamps audio meters and fft bins", () => {
  const state = buildAudioInspectorState({
    amplitude: 1.4,
    bands: { sub: -0.5, low: 0.25, mid: 0.5, high: 2 },
    band_peaks: { sub: 0.2, low: 1.2, mid: 0.6, high: "bad" },
    fft: [0, 0.4, 1.5, "bad"],
    beat: true,
    beat_pulse: 0.7,
    beat_phase: 0.25,
    bar_phase: 0.5,
    bar_count: 3,
    phrase_count: 1,
    peak_frequency: 440.4,
    japanese_hiragana: {
      text: "か",
      confidence: 0.63,
      vowel: "a",
      vowel_confidence: 0.78,
      consonant: "k",
      consonant_confidence: 0.49,
      stable: true,
      silence: false,
      candidates: [
        { text: "か", confidence: 0.63 },
        { text: "た", confidence: 0.41 },
        { text: "あ", confidence: 1.4 },
      ],
    },
  }, 4);

  assert.equal(state.amplitude, 1);
  assert.deepEqual(state.bands, { sub: 0, low: 0.25, mid: 0.5, high: 1 });
  assert.deepEqual(state.bandPeaks, { sub: 0.2, low: 1, mid: 0.6, high: 0 });
  assert.deepEqual(state.fft, [0, 0.4, 1, 0]);
  assert.equal(state.beat, true);
  assert.equal(state.beatPulse, 0.7);
  assert.equal(state.beatPhase, 0.25);
  assert.equal(state.barPhase, 0.5);
  assert.equal(state.barCount, 3);
  assert.equal(state.phraseCount, 1);
  assert.equal(state.peakFrequency, 440.4);
  assert.deepEqual(state.hiragana, {
    enabled: true,
    text: "か",
    confidence: 0.63,
    vowel: "a",
    vowelConfidence: 0.78,
    consonant: "k",
    consonantConfidence: 0.49,
    stable: true,
    silence: false,
    candidates: [
      { text: "か", confidence: 0.63 },
      { text: "た", confidence: 0.41 },
      { text: "あ", confidence: 1 },
    ],
  });
});

test("formatMeterValue produces stable numeric labels", () => {
  assert.equal(formatMeterValue(0.12345, 3), "0.123");
  assert.equal(formatMeterValue("bad", 2), "0.00");
});
