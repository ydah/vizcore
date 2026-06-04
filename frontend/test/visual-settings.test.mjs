import test from "node:test";
import assert from "node:assert/strict";

import {
  applyVisualSettings,
  collectRendererCapabilities,
  nextSafeModeState,
  resolveEffectiveDevicePixelRatio,
  resolveRenderTiming,
} from "../src/renderer/engine.js";

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

test("resolveEffectiveDevicePixelRatio applies caps and safe-mode scale", () => {
  assert.equal(resolveEffectiveDevicePixelRatio({ devicePixelRatio: 3, maxDevicePixelRatio: 2 }), 2);
  assert.equal(resolveEffectiveDevicePixelRatio({
    devicePixelRatio: 2,
    maxDevicePixelRatio: 2,
    safeModeActive: true,
    safeModeScale: 0.5,
  }), 1);
});

test("resolveRenderTiming keeps wall-clock motion when media is paused", () => {
  const timing = resolveRenderTiming({
    frameTimeMs: 2_500,
    lastFrameTimeMs: 1_000,
    mediaElement: { paused: true, currentTime: 12 },
    lastMediaTime: 11.5,
  });

  assert.equal(timing.deltaSeconds, 1.5);
  assert.equal(timing.visualTimeSeconds, 2.5);
  assert.equal(timing.nextLastMediaTime, null);
});

test("resolveRenderTiming uses media time only while media is playing", () => {
  const first = resolveRenderTiming({
    frameTimeMs: 2_500,
    lastFrameTimeMs: 1_000,
    mediaElement: { paused: false, currentTime: 12 },
    lastMediaTime: null,
  });
  const second = resolveRenderTiming({
    frameTimeMs: 3_000,
    lastFrameTimeMs: 2_500,
    mediaElement: { paused: false, currentTime: 12.25 },
    lastMediaTime: first.nextLastMediaTime,
  });

  assert.equal(first.deltaSeconds, 0);
  assert.equal(first.visualTimeSeconds, 12);
  assert.equal(first.nextLastMediaTime, 12);
  assert.equal(second.deltaSeconds, 0.25);
  assert.equal(second.visualTimeSeconds, 12.25);
  assert.equal(second.nextLastMediaTime, 12.25);
});

test("nextSafeModeState enters after repeated slow frames and exits after sustained fast frames", () => {
  let state = { active: false, slowFrames: 0, fastFrames: 0 };
  for (let index = 0; index < 12; index += 1) {
    state = nextSafeModeState({ state, frameMs: 40, thresholdMs: 34 });
  }
  assert.equal(state.active, true);

  for (let index = 0; index < 120; index += 1) {
    state = nextSafeModeState({ state, frameMs: 10, thresholdMs: 34 });
  }
  assert.equal(state.active, false);
});

test("collectRendererCapabilities returns WebGL limits without throwing", () => {
  const gl = {
    MAX_TEXTURE_SIZE: 1,
    MAX_RENDERBUFFER_SIZE: 2,
    MAX_VIEWPORT_DIMS: 3,
    MAX_DRAW_BUFFERS: 4,
    getParameter(parameter) {
      if (parameter === 1) return 8192;
      if (parameter === 2) return 4096;
      if (parameter === 3) return new Int32Array([8192, 4096]);
      if (parameter === 4) return 8;
      return null;
    },
    getExtension(name) {
      return name === "EXT_color_buffer_float" ? {} : null;
    },
  };

  assert.deepEqual(collectRendererCapabilities(gl, {
    devicePixelRatio: 2,
    effectiveDevicePixelRatio: 1.5,
  }), {
    webgl2: true,
    devicePixelRatio: 2,
    effectiveDevicePixelRatio: 1.5,
    maxTextureSize: 8192,
    maxRenderbufferSize: 4096,
    maxViewportDims: [8192, 4096],
    maxDrawBuffers: 8,
    floatColorBuffer: true,
    textureFloat: false,
  });
});
