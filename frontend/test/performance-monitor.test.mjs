import test from "node:test";
import assert from "node:assert/strict";

import {
  createPerformanceMonitorState,
  estimateDroppedFrames,
  formatPerformanceMonitorText,
  recordConnectionStatus,
  recordLatencyProbe,
  recordRenderFrame,
  recordShaderCompile,
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
    { timestamp: 10, metrics: { audio_capture_ms: 0.25, audio_analysis_ms: 1.5 } },
    10_024,
  );

  assert.equal(state.audioLatencyMs, 1.75);
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

test("formatPerformanceMonitorText produces stable HUD copy", () => {
  const state = {
    audioLatencyMs: 1.2,
    droppedFrames: 3,
    fps: 59.94,
    frameMs: 16.72,
    reconnects: 1,
    shaderCompileMs: 3.4,
    rttMs: 8,
    clockOffsetMs: -2,
    wsLatencyMs: 12.4,
  };

  assert.equal(
    formatPerformanceMonitorText(state),
    "Perf: 59.9 FPS | Frame 16.7ms | WS 12ms | RTT 8ms | Clock -2ms | Drop 3 | Audio 1.2ms | Shader 3.4ms | Reconnect 1",
  );
});

test("estimateDroppedFrames ignores normal jitter", () => {
  assert.equal(estimateDroppedFrames(25, 16.7), 0);
  assert.equal(estimateDroppedFrames(70, 16.7), 3);
});
