import test from "node:test";
import assert from "node:assert/strict";

import {
  createPerformanceMonitorState,
  estimateDroppedFrames,
  formatPerformanceMonitorText,
  recordConnectionStatus,
  recordLatencyProbe,
  recordRenderFrame,
  recordRendererCapabilities,
  recordRendererSafeMode,
  recordShaderCompile,
  recordWebSocketBackpressure,
  recordSocketFrame,
} from "../src/performance-monitor.js";

test("recordRenderFrame tracks frame time and rolling fps", () => {
  let state = createPerformanceMonitorState();

  state = recordRenderFrame(state, 0);
  state = recordRenderFrame(state, 16.7);
  state = recordRenderFrame(state, 500);

  assert.equal(state.frameMs, 483.3);
  assert.equal(state.fps, 6);
  assert.equal(state.lastRenderAtMs, 500);
});

test("recordSocketFrame measures websocket latency from server timestamp", () => {
  const state = recordSocketFrame(
    createPerformanceMonitorState(),
    {
      timestamp: 10,
      metrics: {
        audio_capture_ms: 0.25,
        audio_analysis_ms: 1.5,
        scene_build_ms: 6.25,
      },
    },
    10_024,
  );

  assert.equal(state.audioLatencyMs, 1.75);
  assert.equal(state.audioCaptureMs, 0.25);
  assert.equal(state.audioAnalysisMs, 1.5);
  assert.equal(state.sceneBuildMs, 6.25);
  assert.equal(state.wsLatencyMs, 24);
  assert.equal(state.lastSocketTimestampMs, 10_000);
});

test("recordSocketFrame estimates dropped frames from timestamp gaps", () => {
  let state = createPerformanceMonitorState();

  state = recordSocketFrame(state, { timestamp: 1.0 }, 1_010, 20);
  state = recordSocketFrame(state, { timestamp: 1.1 }, 1_120, 20);

  assert.equal(state.droppedFrames, 4);
});

test("recordLatencyProbe estimates round trip time and clock offset", () => {
  const state = recordLatencyProbe(
    createPerformanceMonitorState(),
    {
      client_sent_at_ms: 1_000,
      server_received_at_ms: 1_065,
      server_sent_at_ms: 1_070,
    },
    1_035,
  );

  assert.equal(state.rttMs, 30);
  assert.equal(state.clockOffsetMs, 50);
  assert.equal(state.latencyProbeMaxMs, 30);
  assert.equal(state.latencyProbeP95Ms, 30);
  assert.equal(state.latencyProbeSamples.length, 1);
  assert.equal(state.latencyProbeSamples[0], 30);
});

test("recordSocketFrame corrects websocket latency with measured clock offset", () => {
  let state = createPerformanceMonitorState();
  state = recordLatencyProbe(
    state,
    {
      client_sent_at_ms: 1_000,
      server_received_at_ms: 1_065,
      server_sent_at_ms: 1_070,
    },
    1_035,
  );

  state = recordSocketFrame(state, { timestamp: 2.05 }, 2_020);

  assert.equal(state.wsLatencyMs, 20);
});

test("recordConnectionStatus counts reconnect attempts", () => {
  let state = createPerformanceMonitorState();

  state = recordConnectionStatus(state, "connecting");
  state = recordConnectionStatus(state, "reconnecting");
  state = recordConnectionStatus(state, "reconnecting");

  assert.equal(state.reconnects, 2);
});

test("recordShaderCompile tracks the latest shader compile duration", () => {
  const state = recordShaderCompile(createPerformanceMonitorState(), { compileMs: 3.45 });

  assert.equal(state.shaderCompileMs, 3.45);
});

test("renderer capability and safe mode metrics are tracked", () => {
  let state = createPerformanceMonitorState();

  state = recordRendererCapabilities(state, { effectiveDevicePixelRatio: 1.5, maxTextureSize: 8192 });
  state = recordRendererSafeMode(state, { active: true, effectiveDevicePixelRatio: 1 });

  assert.equal(state.rendererDpr, 1);
  assert.equal(state.rendererMaxTextureSize, 8192);
  assert.equal(state.rendererSafeMode, true);
});

test("formatPerformanceMonitorText produces stable HUD copy", () => {
  const state = {
    audioLatencyMs: 1.2,
    audioCaptureMs: 0.25,
    audioAnalysisMs: 1.5,
    sceneBuildMs: 6.25,
    droppedFrames: 3,
    fps: 59.94,
    frameMs: 16.72,
    reconnects: 1,
    shaderCompileMs: 3.4,
    rttMs: 8,
    clockOffsetMs: -2,
    rendererDpr: 1.5,
    rendererMaxTextureSize: 8192,
    rendererSafeMode: true,
    wsDroppedFrames: 4,
    wsEstimatedLagFrames: 2.5,
    wsAvgPayloadBytes: 1024,
    wsLatencyMs: 12.4,
    latencyProbeSamples: [10, 40, 30, 20, 50],
    latencyProbeMaxMs: 50,
    latencyProbeP95Ms: 50,
  };

  assert.equal(
    formatPerformanceMonitorText(state),
    "Perf: 59.9 FPS | Frame 16.7ms | WS 12ms | RTT 8ms | Probe max 50ms | Probe p95 50ms | Clock -2ms | Drop 3 | BDrop 4 | WSLag 2.5f | Audio 1.2ms | Capture 0.3ms | Analyze 1.5ms | Build 6.3ms | Shader 3.4ms | DPR 1.50x | MaxTex 8192 | Safe on | Backpressure 1024B | Reconnect 1",
  );
});

test("recordWebSocketBackpressure tracks dropped frames and lag estimates", () => {
  const state = recordWebSocketBackpressure(createPerformanceMonitorState(), {
    active_clients: 2,
    clients: [
      { estimated_lag_frames: 2.5 },
      { estimated_lag_frames: 0.5 },
    ],
    total: {
      dropped_frames: 3,
      avg_payload_bytes: 512,
    },
  });

  assert.equal(state.wsDroppedFrames, 3);
  assert.equal(state.wsActiveClients, 2);
  assert.equal(state.wsEstimatedLagFrames, 1.5);
  assert.equal(state.wsAvgPayloadBytes, 512);
});

test("estimateDroppedFrames ignores normal jitter", () => {
  assert.equal(estimateDroppedFrames(25, 16.7), 0);
  assert.equal(estimateDroppedFrames(70, 16.7), 3);
});
