const DEFAULT_EXPECTED_FRAME_MS = 1000 / 60;
const FPS_WINDOW_MS = 500;

export const createPerformanceMonitorState = () => ({
  audioLatencyMs: null,
  droppedFrames: 0,
  fps: 0,
  frameMs: 0,
  lastRenderAtMs: null,
  lastSocketTimestampMs: null,
  reconnects: 0,
  renderWindowFrames: 0,
  renderWindowStartedAtMs: null,
  shaderCompileMs: null,
  wsLatencyMs: null,
});

export const recordRenderFrame = (state, nowMs) => {
  const now = Number(nowMs);
  if (!Number.isFinite(now)) {
    return { ...state };
  }

  const previousRenderAt = Number.isFinite(state?.lastRenderAtMs) ? state.lastRenderAtMs : null;
  const frameMs = previousRenderAt === null ? 0 : Math.max(0, now - previousRenderAt);
  const windowStartedAt = Number.isFinite(state?.renderWindowStartedAtMs)
    ? state.renderWindowStartedAtMs
    : now;
  const windowFrames = Number(state?.renderWindowFrames || 0) + 1;
  const windowMs = now - windowStartedAt;

  if (windowMs >= FPS_WINDOW_MS) {
    return {
      ...state,
      fps: roundOneDecimal((windowFrames * 1000) / windowMs),
      frameMs: roundOneDecimal(frameMs),
      lastRenderAtMs: now,
      renderWindowFrames: 0,
      renderWindowStartedAtMs: now,
    };
  }

  return {
    ...state,
    frameMs: roundOneDecimal(frameMs),
    lastRenderAtMs: now,
    renderWindowFrames: windowFrames,
    renderWindowStartedAtMs: windowStartedAt,
  };
};

export const recordSocketFrame = (
  state,
  frame,
  receivedAtMs,
  expectedFrameMs = DEFAULT_EXPECTED_FRAME_MS,
) => {
  const timestampMs = Number(frame?.timestamp) * 1000;
  const receivedAt = Number(receivedAtMs);
  if (!Number.isFinite(timestampMs) || timestampMs <= 0 || !Number.isFinite(receivedAt)) {
    return { ...state };
  }

  const previousTimestamp = Number.isFinite(state?.lastSocketTimestampMs)
    ? state.lastSocketTimestampMs
    : null;
  const frameGapMs = previousTimestamp === null ? 0 : Math.max(0, timestampMs - previousTimestamp);
  const droppedFrames = Number(state?.droppedFrames || 0) + estimateDroppedFrames(frameGapMs, expectedFrameMs);
  const audioLatencyMs = audioLatencyFromMetrics(frame?.metrics, state?.audioLatencyMs);

  return {
    ...state,
    audioLatencyMs,
    droppedFrames,
    lastSocketTimestampMs: timestampMs,
    wsLatencyMs: Math.max(0, Math.round(receivedAt - timestampMs)),
  };
};

export const recordConnectionStatus = (state, status) => {
  if (status !== "reconnecting") {
    return { ...state };
  }

  return {
    ...state,
    reconnects: Number(state?.reconnects || 0) + 1,
  };
};

export const recordShaderCompile = (state, detail) => {
  const compileMs = coerceMetric(detail?.compileMs);
  if (compileMs === null) {
    return { ...state };
  }

  return {
    ...state,
    shaderCompileMs: compileMs,
  };
};

export const formatPerformanceMonitorText = (state) => {
  const fps = Number(state?.fps || 0) > 0 ? Number(state.fps).toFixed(1) : "--";
  const frameMs = Number(state?.frameMs || 0) > 0 ? `${Number(state.frameMs).toFixed(1)}ms` : "--";
  const wsLatency = Number.isFinite(state?.wsLatencyMs) ? `${Math.round(state.wsLatencyMs)}ms` : "--";
  const audioLatency = Number.isFinite(state?.audioLatencyMs) ? `${Number(state.audioLatencyMs).toFixed(1)}ms` : "--";
  const shaderCompile = Number.isFinite(state?.shaderCompileMs) ? `${Number(state.shaderCompileMs).toFixed(1)}ms` : "--";
  const droppedFrames = Math.max(0, Number(state?.droppedFrames || 0));
  const reconnects = Math.max(0, Number(state?.reconnects || 0));

  return `Perf: ${fps} FPS | Frame ${frameMs} | WS ${wsLatency} | Drop ${droppedFrames} | Audio ${audioLatency} | Shader ${shaderCompile} | Reconnect ${reconnects}`;
};

export const estimateDroppedFrames = (frameGapMs, expectedFrameMs = DEFAULT_EXPECTED_FRAME_MS) => {
  const gap = Number(frameGapMs);
  const expected = Number(expectedFrameMs);
  if (!Number.isFinite(gap) || !Number.isFinite(expected) || gap <= expected * 1.75) {
    return 0;
  }

  return Math.max(0, Math.round(gap / expected) - 1);
};

const audioLatencyFromMetrics = (metrics, fallback) => {
  const captureMs = coerceMetric(metrics?.audio_capture_ms);
  const analysisMs = coerceMetric(metrics?.audio_analysis_ms);
  if (captureMs === null && analysisMs === null) {
    return fallback ?? null;
  }

  return (captureMs || 0) + (analysisMs || 0);
};

const coerceMetric = (value) => {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) {
    return null;
  }

  return Math.max(0, numeric);
};

const roundOneDecimal = (value) => Math.round(value * 10) / 10;
