const DEFAULT_EXPECTED_FRAME_MS = 1000 / 60;
const FPS_WINDOW_MS = 500;
const LATENCY_HISTORY_MAX = 120;

export const createPerformanceMonitorState = () => ({
  audioLatencyMs: null,
  audioCaptureMs: null,
  audioAnalysisMs: null,
  sceneBuildMs: null,
  clockOffsetMs: null,
  droppedFrames: 0,
  wsDroppedFrames: 0,
  wsActiveClients: 0,
  wsEstimatedLagFrames: 0,
  wsAvgPayloadBytes: 0,
  fps: 0,
  frameMs: 0,
  lastRenderAtMs: null,
  lastSocketTimestampMs: null,
  latencyProbeSamples: [],
  latencyProbeMaxMs: null,
  latencyProbeP95Ms: null,
  rendererFloatColorBuffer: false,
  rendererTextureFloat: false,
  rendererMaxDrawBuffers: null,
  reconnects: 0,
  rendererDpr: null,
  rendererMaxTextureSize: null,
  rendererSafeMode: false,
  renderWindowFrames: 0,
  renderWindowStartedAtMs: null,
  rttMs: null,
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
  const audioCaptureMs = audioCaptureFromMetrics(frame?.metrics, state?.audioCaptureMs);
  const audioAnalysisMs = audioAnalysisFromMetrics(frame?.metrics, state?.audioAnalysisMs);
  const sceneBuildMs = sceneBuildFromMetrics(frame?.metrics, state?.sceneBuildMs);
  const clockOffsetMs = Number.isFinite(state?.clockOffsetMs) ? Number(state.clockOffsetMs) : 0;
  const browserTimestampMs = timestampMs - clockOffsetMs;

  return {
    ...state,
    audioLatencyMs,
    audioCaptureMs,
    audioAnalysisMs,
    sceneBuildMs,
    droppedFrames,
    lastSocketTimestampMs: timestampMs,
    wsLatencyMs: Math.max(0, Math.round(receivedAt - browserTimestampMs)),
  };
};

export const recordLatencyProbe = (state, payload, receivedAtMs) => {
  const clientSentAtMs = Number(payload?.client_sent_at_ms);
  const serverReceivedAtMs = Number(payload?.server_received_at_ms);
  const serverSentAtMs = Number(payload?.server_sent_at_ms);
  const browserReceivedAtMs = Number(receivedAtMs);

  if (
    !Number.isFinite(clientSentAtMs) ||
    !Number.isFinite(serverReceivedAtMs) ||
    !Number.isFinite(serverSentAtMs) ||
    !Number.isFinite(browserReceivedAtMs) ||
    browserReceivedAtMs < clientSentAtMs ||
    serverSentAtMs < serverReceivedAtMs
  ) {
    return { ...state };
  }

  const serverProcessingMs = serverSentAtMs - serverReceivedAtMs;
  const rttMs = Math.max(0, browserReceivedAtMs - clientSentAtMs - serverProcessingMs);
  const clockOffsetMs = ((serverReceivedAtMs - clientSentAtMs) + (serverSentAtMs - browserReceivedAtMs)) / 2;
  const nextLatencySamples = appendNumericHistory(
    Array.isArray(state?.latencyProbeSamples) ? state.latencyProbeSamples : [],
    rttMs,
    LATENCY_HISTORY_MAX,
  );
  const { max, p95 } = latencyProbeStats(nextLatencySamples);

  return {
    ...state,
    latencyProbeSamples: nextLatencySamples,
    latencyProbeMaxMs: max,
    latencyProbeP95Ms: p95,
    clockOffsetMs: Math.round(clockOffsetMs),
    rttMs: Math.round(rttMs),
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

export const recordRendererCapabilities = (state, detail) => {
  const effectiveDpr = coerceMetric(detail?.effectiveDevicePixelRatio);
  const maxTextureSize = coerceMetric(detail?.maxTextureSize);

  return {
    ...state,
    rendererDpr: effectiveDpr ?? state?.rendererDpr ?? null,
    rendererMaxTextureSize: maxTextureSize ?? state?.rendererMaxTextureSize ?? null,
    rendererMaxDrawBuffers: Number.isFinite(coerceMetric(detail?.maxDrawBuffers))
      ? coerceMetric(detail.maxDrawBuffers)
      : state?.rendererMaxDrawBuffers ?? null,
    rendererFloatColorBuffer: !!detail?.floatColorBuffer,
    rendererTextureFloat: !!detail?.textureFloat,
  };
};

export const recordRendererSafeMode = (state, detail) => {
  return {
    ...state,
    rendererSafeMode: !!detail?.active,
    rendererDpr: coerceMetric(detail?.effectiveDevicePixelRatio) ?? state?.rendererDpr ?? null,
  };
};

export const recordWebSocketBackpressure = (state, detail) => {
  const total = detail?.total || {};
  const clients = Array.isArray(detail?.clients) ? detail.clients : [];
  const averageLag = clients.length > 0
    ? Math.max(0, clients.reduce((acc, entry) => acc + coerceFiniteNumber(entry?.estimated_lag_frames || 0), 0) / clients.length)
    : 0;

  return {
    ...state,
    wsDroppedFrames: Number(total?.dropped_frames || 0),
    wsActiveClients: Number(detail?.active_clients || 0),
    wsAvgPayloadBytes: Number(coerceMetric(total?.avg_payload_bytes) || 0),
    wsEstimatedLagFrames: averageLag,
  };
};

export const formatPerformanceMonitorText = (state) => {
  const fps = Number(state?.fps || 0) > 0 ? Number(state.fps).toFixed(1) : "--";
  const frameMs = Number(state?.frameMs || 0) > 0 ? `${Number(state.frameMs).toFixed(1)}ms` : "--";
  const wsLatency = Number.isFinite(state?.wsLatencyMs) ? `${Math.round(state.wsLatencyMs)}ms` : "--";
  const rtt = Number.isFinite(state?.rttMs) ? `${Math.round(state.rttMs)}ms` : "--";
  const clockOffset = Number.isFinite(state?.clockOffsetMs) ? `${formatSignedInteger(state.clockOffsetMs)}ms` : "--";
  const audioLatency = Number.isFinite(state?.audioLatencyMs) ? `${Number(state.audioLatencyMs).toFixed(1)}ms` : "--";
  const audioCaptureMs = Number.isFinite(state?.audioCaptureMs) ? `${Number(state.audioCaptureMs).toFixed(1)}ms` : "--";
  const audioAnalysisMs = Number.isFinite(state?.audioAnalysisMs) ? `${Number(state.audioAnalysisMs).toFixed(1)}ms` : "--";
  const sceneBuildMs = Number.isFinite(state?.sceneBuildMs) ? `${Number(state.sceneBuildMs).toFixed(1)}ms` : "--";
  const probeMax = Number.isFinite(state?.latencyProbeMaxMs) ? `${Math.round(state.latencyProbeMaxMs)}ms` : "--";
  const probeP95 = Number.isFinite(state?.latencyProbeP95Ms) ? `${Math.round(state.latencyProbeP95Ms)}ms` : "--";
  const shaderCompile = Number.isFinite(state?.shaderCompileMs) ? `${Number(state.shaderCompileMs).toFixed(1)}ms` : "--";
  const rendererDpr = Number.isFinite(state?.rendererDpr) ? `${Number(state.rendererDpr).toFixed(2)}x` : "--";
  const maxTexture = Number.isFinite(state?.rendererMaxTextureSize) ? Math.round(state.rendererMaxTextureSize) : "--";
  const maxDrawBuffers = Number.isFinite(state?.rendererMaxDrawBuffers) ? Math.round(state.rendererMaxDrawBuffers) : "--";
  const floatColorBuffer = state?.rendererFloatColorBuffer ? "floatColorBuffer yes" : "floatColorBuffer no";
  const textureFloat = state?.rendererTextureFloat ? "textureFloat yes" : "textureFloat no";
  const safeMode = state?.rendererSafeMode ? "on" : "off";
  const droppedFrames = Math.max(0, Number(state?.droppedFrames || 0));
  const wsDroppedFrames = Math.max(0, Number(state?.wsDroppedFrames || 0));
  const wsEstimatedLagFrames = Math.max(0, Number(state?.wsEstimatedLagFrames || 0));
  const reconnects = Math.max(0, Number(state?.reconnects || 0));
  const wsAvgPayload = Number.isFinite(state?.wsAvgPayloadBytes) ? `${Math.round(state.wsAvgPayloadBytes)}B` : "--";

  return `Perf: ${fps} FPS | Frame ${frameMs} | WS ${wsLatency} | RTT ${rtt} | Probe max ${probeMax} | Probe p95 ${probeP95} | Clock ${clockOffset} | Drop ${droppedFrames} | BDrop ${wsDroppedFrames} | WSLag ${wsEstimatedLagFrames.toFixed(1)}f | Audio ${audioLatency} | Capture ${audioCaptureMs} | Analyze ${audioAnalysisMs} | Build ${sceneBuildMs} | Shader ${shaderCompile} | DPR ${rendererDpr} | MaxTex ${maxTexture} | DrawBuf ${maxDrawBuffers} | ${floatColorBuffer} | ${textureFloat} | Safe ${safeMode} | Backpressure ${wsAvgPayload} | Reconnect ${reconnects}`;
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

const audioCaptureFromMetrics = (metrics, fallback) => {
  const captureMs = coerceMetric(metrics?.audio_capture_ms);
  return captureMs ?? fallback ?? null;
};

const audioAnalysisFromMetrics = (metrics, fallback) => {
  const analysisMs = coerceMetric(metrics?.audio_analysis_ms);
  return analysisMs ?? fallback ?? null;
};

const sceneBuildFromMetrics = (metrics, fallback) => {
  const buildMs = coerceMetric(metrics?.scene_build_ms);
  return buildMs ?? fallback ?? null;
};

const coerceMetric = (value) => {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) {
    return null;
  }

  return Math.max(0, numeric);
};

const roundOneDecimal = (value) => Math.round(value * 10) / 10;

const coerceFiniteNumber = (value) => {
  const numeric = Number(value);
  return Number.isFinite(numeric) ? numeric : 0;
};

const formatSignedInteger = (value) => {
  const rounded = Math.round(Number(value) || 0);
  return rounded > 0 ? `+${rounded}` : `${rounded}`;
};

const appendNumericHistory = (history = [], sample, maxLength = LATENCY_HISTORY_MAX) => {
  if (!Number.isFinite(sample)) {
    return Array.isArray(history) ? history.slice(-maxLength) : [];
  }

  const keep = Math.max(1, Number(maxLength) || 1);
  const sanitizedHistory = Array.isArray(history)
    ? history.filter((entry) => Number.isFinite(entry)).map((entry) => Number(entry))
    : [];
  const next = [...sanitizedHistory, Number(sample)];
  if (next.length <= keep) {
    return next;
  }

  return next.slice(next.length - keep);
};

const latencyProbeStats = (samples) => {
  const numericSamples = (Array.isArray(samples) ? samples : []).filter((entry) => Number.isFinite(entry));
  if (numericSamples.length === 0) {
    return { max: null, p95: null };
  }

  const sorted = [...numericSamples].sort((left, right) => left - right);
  const max = sorted[sorted.length - 1];
  const index = Math.min(sorted.length - 1, Math.max(0, Math.ceil(0.95 * sorted.length) - 1));

  return { max, p95: sorted[index] };
};
