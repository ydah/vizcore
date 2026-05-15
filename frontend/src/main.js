import { BAND_KEYS, DEFAULT_FFT_BINS, buildAudioInspectorState, formatMeterValue } from "./audio-inspector.js";
import {
  createLiveControlState,
  isTapTempoShortcut,
  keyboardActionForKey,
  liveControlStatusText,
  normalizeKeyboardMappings,
  shortcutActionForKey,
  shortcutSceneIndexForKey,
  toggleLiveControl,
} from "./live-controls.js";
import {
  createPerformanceMonitorState,
  formatPerformanceMonitorText,
  recordConnectionStatus,
  recordLatencyProbe,
  recordRenderFrame,
  recordShaderCompile,
  recordSocketFrame,
} from "./performance-monitor.js";
import { applyProjectorMode, resolveProjectorMode } from "./projector-mode.js";
import { Engine } from "./renderer/engine.js";
import { SHADER_COMPILE_EVENT } from "./renderer/shader-manager.js";
import {
  pruneShaderParamOverrides,
  shaderParamControlEntries
} from "./shader-param-controls.js";
import { SHADER_ERROR_EVENT, formatShaderErrorMessage, formatShaderErrorTitle } from "./shader-error-overlay.js";
import {
  loadVisualSettingsPreset,
  saveVisualSettingsPreset
} from "./visual-settings-preset.js";
import { WebSocketClient } from "./websocket-client.js";

const canvas = document.querySelector("#vizcore-canvas");
const wsStatusElement = document.querySelector("#ws-status");
const sceneStatusElement = document.querySelector("#scene-status");
const transitionStatusElement = document.querySelector("#transition-status");
const frameStatusElement = document.querySelector("#frame-status");
const bpmStatusElement = document.querySelector("#bpm-status");
const beatStatusElement = document.querySelector("#beat-status");
const blackoutButton = document.querySelector("#blackout-toggle");
const freezeButton = document.querySelector("#freeze-toggle");
const liveControlStatusElement = document.querySelector("#live-control-status");
const performanceMonitorElement = document.querySelector("#performance-monitor");
const inspectorPeakElement = document.querySelector("#inspector-peak");
const inspectorAmplitudeFill = document.querySelector("#inspector-amplitude-fill");
const inspectorAmplitudeValue = document.querySelector("#inspector-amplitude-value");
const inspectorBandElements = Object.fromEntries(
  BAND_KEYS.map((key) => [
    key,
    {
      fill: document.querySelector(`#inspector-band-${key}-fill`),
      value: document.querySelector(`#inspector-band-${key}-value`)
    }
  ])
);
const fftPreviewElement = document.querySelector("#fft-preview");
const audioSourceStatusElement = document.querySelector("#audio-source-status");
const audioTrackStatusElement = document.querySelector("#audio-track-status");
const audioPlaybackStatusElement = document.querySelector("#audio-playback-status");
const sceneSwitcherElement = document.querySelector("#scene-switcher");
const audioToggleButton = document.querySelector("#audio-toggle");
const visualGainControl = document.querySelector("#visual-gain-control");
const bassBoostControl = document.querySelector("#bass-boost-control");
const smoothingControl = document.querySelector("#smoothing-control");
const beatHoldControl = document.querySelector("#beat-hold-control");
const wobbleControl = document.querySelector("#wobble-control");
const reactivitySaveButton = document.querySelector("#reactivity-save");
const reactivityLoadButton = document.querySelector("#reactivity-load");
const reactivityStatusElement = document.querySelector("#reactivity-status");
const shaderParamControlsElement = document.querySelector("#shader-param-controls");
const shaderErrorOverlay = document.querySelector("#shader-error-overlay");
const shaderErrorTitleElement = document.querySelector("#shader-error-title");
const shaderErrorMessageElement = document.querySelector("#shader-error-message");
const shaderErrorCloseButton = document.querySelector("#shader-error-close");
const LATENCY_PROBE_INTERVAL_MS = 3000;

const visualSettings = loadVisualSettingsPreset(browserStorage());
const liveControls = createLiveControlState();
const performanceMonitor = createPerformanceMonitorState();
let projectorMode = resolveProjectorMode({ body: document.body, location: window.location });
applyProjectorMode(document.body, projectorMode);
const engine = new Engine(canvas);
bindShaderCompileMetrics();
engine.init();
engine.setVisualSettings(visualSettings);
engine.setLiveControls(liveControls);
bindLiveControls();
bindVisualControl(visualGainControl, "visualGain");
bindVisualControl(bassBoostControl, "bassBoost");
bindVisualControl(smoothingControl, "smoothing");
bindVisualControl(beatHoldControl, "beatHoldMs");
bindVisualControl(wobbleControl, "wobbleAmount");
bindVisualPresetControls();
renderLiveControlStatus();
renderPerformanceMonitor();
syncVisualControls();
renderReactivityStatus();
bindShaderErrorOverlay();
const fftBars = initializeFftPreview(fftPreviewElement);
engine.start();
startPerformanceMonitorLoop();

let currentSceneName = "unknown";
let audioElement = null;
let frameCount = 0;
let lastConnectedAt = null;
let lastTransportSyncAt = 0;
let latencyProbeTimer = null;
let beatFlashUntil = 0;
let availableSceneNames = [];
let keyboardMappings = [];
let pendingSceneName = null;
let pendingSceneRequestedAt = 0;
let tapTempoKey = null;
let runtimeGlobalsReceived = false;
let shaderParamOverrides = {};
let shaderParamControlsSignature = "";

const websocketUrl = buildWebSocketUrl();
const client = new WebSocketClient(websocketUrl, {
  onFrame: (frame) => {
    updatePerformanceMonitor(recordSocketFrame(performanceMonitor, frame, Date.now()));
    engine.setAudioFrame(frame);
    frameCount += 1;
    let sceneName = String(frame?.scene?.name || currentSceneName);
    const now = performance.now();
    if (
      pendingSceneName &&
      sceneName !== pendingSceneName &&
      now - pendingSceneRequestedAt < 350
    ) {
      sceneName = currentSceneName;
    }
    if (pendingSceneName && sceneName === pendingSceneName) {
      pendingSceneName = null;
      pendingSceneRequestedAt = 0;
    }
    const sceneChanged = sceneName !== currentSceneName;
    currentSceneName = sceneName;
    if (sceneChanged) {
      shaderParamControlsSignature = "";
    }
    updateShaderParamControls(frame?.scene?.layers);
    const amplitude = Number(frame?.audio?.amplitude || 0).toFixed(4);
    const bpm = Number(frame?.audio?.bpm || 0);
    const beat = !!frame?.audio?.beat;
    const beatCount = Math.max(0, Number(frame?.audio?.beat_count || 0) || 0);
    if (beat) {
      beatFlashUntil = performance.now() + visualSettings.beatHoldMs;
    }
    const beatVisible = performance.now() < beatFlashUntil;
    sceneStatusElement.textContent = `Scene: ${sceneName}`;
    if (sceneChanged) {
      renderSceneButtons();
    }
    frameStatusElement.textContent = `Amplitude: ${amplitude} | Frames: ${frameCount}`;
    bpmStatusElement.textContent = `BPM: ${bpm > 0 ? bpm.toFixed(1) : "--"}`;
    beatStatusElement.textContent = `Beat: ${beatVisible ? "ON" : "off"} | Count: ${beatCount}`;
    beatStatusElement.classList.toggle("is-beat", beatVisible);
    renderAudioInspector(frame?.audio);
  },
  onSceneChange: (payload) => {
    const from = String(payload?.from || "unknown");
    const to = String(payload?.to || "unknown");
    pendingSceneName = null;
    pendingSceneRequestedAt = 0;
    currentSceneName = to;
    sceneStatusElement.textContent = `Scene: ${to}`;
    transitionStatusElement.textContent = `Transition: ${from} -> ${to}`;
    renderSceneButtons();
  },
  onConfigUpdate: (payload) => {
    updateAvailableScenes(payload?.scenes);
    const sceneName = payload?.scene?.name;
    if (sceneName) {
      currentSceneName = String(sceneName);
      sceneStatusElement.textContent = `Scene: ${currentSceneName}`;
      renderSceneButtons();
      shaderParamControlsSignature = "";
      updateShaderParamControls(payload?.scene?.layers);
    }
    if (Object.prototype.hasOwnProperty.call(payload || {}, "tap_tempo_key")) {
      updateTapTempoKey(payload?.tap_tempo_key);
    }
    if (Object.prototype.hasOwnProperty.call(payload || {}, "key_mappings")) {
      updateKeyboardMappings(payload?.key_mappings);
    }
    if (Object.prototype.hasOwnProperty.call(payload || {}, "globals")) {
      runtimeGlobalsReceived = true;
      applyRuntimeGlobals(payload?.globals);
    }
  },
  onLatencyProbe: (payload) => {
    updatePerformanceMonitor(recordLatencyProbe(performanceMonitor, payload, Date.now()));
  },
  onStatus: (status) => {
    updatePerformanceMonitor(recordConnectionStatus(performanceMonitor, status));
    if (status === "connected") {
      lastConnectedAt = new Date();
      startLatencyProbeLoop();
      syncAudioTransportToServer({ force: true });
    } else {
      stopLatencyProbeLoop();
      pendingSceneName = null;
      pendingSceneRequestedAt = 0;
      currentSceneName = "unknown";
      sceneStatusElement.textContent = "Scene: unknown";
      renderSceneButtons();
    }
    const connectedAt = lastConnectedAt ? ` | Last connected: ${formatClock(lastConnectedAt)}` : "";
    wsStatusElement.textContent = `WebSocket: ${status}${connectedAt}`;
  }
});

client.connect();
void initializeRuntime();

async function initializeRuntime() {
  const runtime = await fetchRuntime();
  applyRuntime(runtime);
}

async function fetchRuntime() {
  try {
    const response = await fetch("/runtime", { cache: "no-store" });
    if (!response.ok) {
      return null;
    }
    return await response.json();
  } catch {
    return null;
  }
}

function applyRuntime(runtime) {
  projectorMode = resolveProjectorMode({
    body: document.body,
    current: projectorMode,
    location: window.location,
    runtime,
  });
  applyProjectorMode(document.body, projectorMode);

  const source = String(runtime?.audio_source || "unknown");
  audioSourceStatusElement.textContent = `Audio Source: ${source}`;
  updateAvailableScenes(runtime?.scene_names);
  updateTapTempoKey(runtime?.tap_tempo_key);
  updateKeyboardMappings(runtime?.key_mappings);
  if (!runtimeGlobalsReceived) {
    applyRuntimeGlobals(runtime?.globals);
  }

  const fileName = runtime?.audio_file_name;
  const fileUrl = runtime?.audio_file_url;
  if (!fileUrl) {
    engine.setMediaElement(null);
    audioTrackStatusElement.textContent = "Track: none";
    audioPlaybackStatusElement.textContent = "Playback: unavailable";
    audioToggleButton.hidden = true;
    return;
  }

  audioTrackStatusElement.textContent = `Track: ${String(fileName || "source file")}`;
  setupAudioPlayback(fileUrl);
}

function applyRuntimeGlobals(globals) {
  engine.setRuntimeGlobals(globals);
}

function updateAvailableScenes(sceneValues) {
  const names = normalizeSceneNames(sceneValues);
  if (!names.length) {
    return;
  }
  availableSceneNames = names;
  renderSceneButtons();
}

function updateTapTempoKey(key) {
  const value = String(key || "").trim().toLowerCase();
  tapTempoKey = value || null;
}

function updateKeyboardMappings(mappings) {
  keyboardMappings = normalizeKeyboardMappings(mappings);
  renderSceneButtons();
}

function normalizeSceneNames(sceneValues) {
  const seen = new Set();
  const names = [];
  const entries = Array.isArray(sceneValues) ? sceneValues : [];

  for (const entry of entries) {
    const rawName = typeof entry === "string" ? entry : entry?.name;
    const name = String(rawName || "").trim();
    if (!name || seen.has(name)) {
      continue;
    }
    seen.add(name);
    names.push(name);
  }

  return names;
}

function renderSceneButtons() {
  if (!sceneSwitcherElement) {
    return;
  }

  if (!availableSceneNames.length) {
    sceneSwitcherElement.hidden = true;
    sceneSwitcherElement.replaceChildren();
    return;
  }

  sceneSwitcherElement.hidden = false;
  const buttons = availableSceneNames.map((sceneName) => {
    const button = document.createElement("button");
    const shortcut = sceneShortcutFor(sceneName);
    button.type = "button";
    button.textContent = shortcut ? `${sceneName} [${shortcut}]` : sceneName;
    button.title = shortcut ? `Shortcut: ${shortcut}` : "";
    button.classList.toggle("is-active", sceneName === currentSceneName);
    button.onclick = () => {
      requestSceneSwitch(sceneName);
    };
    return button;
  });
  sceneSwitcherElement.replaceChildren(...buttons);
}

function sceneShortcutFor(sceneName) {
  const mapping = keyboardMappings.find((entry) => (
    entry.action?.type === "switch_scene" && entry.action.scene === sceneName
  ));
  return mapping?.key || "";
}

function updateShaderParamControls(layers) {
  if (!shaderParamControlsElement) {
    return;
  }

  const entries = shaderParamControlEntries(layers, shaderParamOverrides);
  const signature = shaderParamControlsSignatureFor(entries);
  if (signature === shaderParamControlsSignature) {
    return;
  }

  shaderParamControlsSignature = signature;
  shaderParamOverrides = pruneShaderParamOverrides(shaderParamOverrides, entries);
  engine.setShaderParamOverrides(shaderParamOverrides);
  renderShaderParamControls(entries);
}

function shaderParamControlsSignatureFor(entries) {
  return entries.map((entry) => (
    `${entry.key}:${entry.min}:${entry.max}:${entry.step}`
  )).join("|");
}

function renderShaderParamControls(entries) {
  if (!shaderParamControlsElement) {
    return;
  }

  if (!entries.length) {
    shaderParamControlsElement.hidden = true;
    shaderParamControlsElement.replaceChildren();
    return;
  }

  const title = document.createElement("p");
  title.className = "shader-param-controls__title";
  title.textContent = "Shader Params";
  const controls = entries.map((entry) => createShaderParamControl(entry));
  shaderParamControlsElement.replaceChildren(title, ...controls);
  shaderParamControlsElement.hidden = false;
}

function createShaderParamControl(entry) {
  const label = document.createElement("label");
  const name = document.createElement("span");
  const input = document.createElement("input");
  const value = document.createElement("output");
  name.textContent = entry.label;
  input.type = "range";
  input.min = String(entry.min);
  input.max = String(entry.max);
  input.step = String(entry.step);
  input.value = String(entry.value);
  value.value = formatShaderParamValue(entry.value);
  input.addEventListener("input", () => {
    const numeric = Number(input.value);
    shaderParamOverrides[entry.layerKey] ||= {};
    shaderParamOverrides[entry.layerKey][entry.paramName] = numeric;
    engine.setShaderParamOverrides(shaderParamOverrides);
    value.value = formatShaderParamValue(numeric);
  });
  label.append(name, input, value);
  return label;
}

function formatShaderParamValue(value) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) {
    return "--";
  }
  return Math.abs(numeric) >= 10 ? numeric.toFixed(1) : numeric.toFixed(2);
}

function requestSceneSwitch(sceneName) {
  if (!sceneName || sceneName === currentSceneName) {
    return;
  }

  pendingSceneName = sceneName;
  pendingSceneRequestedAt = performance.now();
  currentSceneName = sceneName;
  sceneStatusElement.textContent = `Scene: ${sceneName}`;
  renderSceneButtons();
  client.send("switch_scene", { scene: sceneName });
}

function applyKeyboardAction(action) {
  if (action?.type === "switch_scene") {
    requestSceneSwitch(action.scene);
    return;
  }

  if (action?.type === "live_control") {
    applyLiveControls(toggleLiveControl(liveControls, action.control));
  }
}

function startPerformanceMonitorLoop() {
  requestAnimationFrame((time) => {
    updatePerformanceMonitor(recordRenderFrame(performanceMonitor, time));
    startPerformanceMonitorLoop();
  });
}

function startLatencyProbeLoop() {
  stopLatencyProbeLoop();
  sendLatencyProbe();
  latencyProbeTimer = setInterval(sendLatencyProbe, LATENCY_PROBE_INTERVAL_MS);
}

function stopLatencyProbeLoop() {
  if (!latencyProbeTimer) {
    return;
  }

  clearInterval(latencyProbeTimer);
  latencyProbeTimer = null;
}

function sendLatencyProbe() {
  client.send("latency_probe", {
    client_sent_at_ms: Date.now()
  });
}

function updatePerformanceMonitor(nextState) {
  Object.assign(performanceMonitor, nextState);
  renderPerformanceMonitor();
}

function renderPerformanceMonitor() {
  if (!performanceMonitorElement) {
    return;
  }

  performanceMonitorElement.textContent = formatPerformanceMonitorText(performanceMonitor);
}

function bindShaderCompileMetrics() {
  window.addEventListener(SHADER_COMPILE_EVENT, (event) => {
    updatePerformanceMonitor(recordShaderCompile(performanceMonitor, event.detail));
  });
}

function bindLiveControls() {
  bindLiveControlButton(blackoutButton, "blackout");
  bindLiveControlButton(freezeButton, "freeze");
  window.addEventListener("keydown", (event) => {
    const keyboardAction = keyboardActionForKey(event, keyboardMappings);
    if (keyboardAction) {
      event.preventDefault();
      applyKeyboardAction(keyboardAction);
      return;
    }

    const action = shortcutActionForKey(event);
    if (action) {
      event.preventDefault();
      applyLiveControls(toggleLiveControl(liveControls, action));
      return;
    }

    const sceneIndex = shortcutSceneIndexForKey(event, availableSceneNames.length);
    if (sceneIndex === null) {
      return;
    }

    event.preventDefault();
    requestSceneSwitch(availableSceneNames[sceneIndex]);
  });

  window.addEventListener("keydown", (event) => {
    if (!isTapTempoShortcut(event, tapTempoKey)) {
      return;
    }

    event.preventDefault();
    client.send("tap_tempo", { client_tapped_at_ms: Date.now() });
  });
}

function bindLiveControlButton(button, control) {
  if (!button) {
    return;
  }

  button.addEventListener("click", () => {
    applyLiveControls(toggleLiveControl(liveControls, control));
  });
}

function applyLiveControls(nextState) {
  Object.assign(liveControls, nextState);
  engine.setLiveControls(liveControls);
  renderLiveControlStatus();
}

function renderLiveControlStatus() {
  if (liveControlStatusElement) {
    liveControlStatusElement.textContent = liveControlStatusText(liveControls);
  }

  if (blackoutButton) {
    blackoutButton.classList.toggle("is-active", liveControls.blackout);
    blackoutButton.setAttribute("aria-pressed", String(liveControls.blackout));
  }

  if (freezeButton) {
    freezeButton.classList.toggle("is-active", liveControls.freeze);
    freezeButton.setAttribute("aria-pressed", String(liveControls.freeze));
  }
}

function setupAudioPlayback(audioUrl) {
  if (audioElement) {
    audioElement.pause();
  }

  audioElement = new Audio(audioUrl);
  audioElement.preload = "auto";
  audioElement.loop = true;
  engine.setMediaElement(audioElement);

  audioToggleButton.hidden = false;
  audioToggleButton.disabled = false;

  const updatePlaybackState = () => {
    if (!audioElement) {
      return;
    }
    const state = audioElement.paused ? "paused" : "playing";
    const current = formatSeconds(audioElement.currentTime);
    const duration = Number.isFinite(audioElement.duration) ? formatSeconds(audioElement.duration) : "--:--";
    audioPlaybackStatusElement.textContent = `Playback: ${state} ${current} / ${duration}`;
    audioToggleButton.textContent = audioElement.paused ? "Play Audio" : "Pause Audio";
  };

  const playAudio = async () => {
    if (!audioElement) {
      return;
    }
    try {
      await audioElement.play();
      updatePlaybackState();
    } catch (error) {
      const message = String(error?.message || "autoplay blocked");
      audioPlaybackStatusElement.textContent = `Playback: blocked (${message})`;
      audioToggleButton.textContent = "Play Audio";
    }
  };

  audioElement.addEventListener("play", updatePlaybackState);
  audioElement.addEventListener("pause", updatePlaybackState);
  audioElement.addEventListener("timeupdate", updatePlaybackState);
  audioElement.addEventListener("loadedmetadata", updatePlaybackState);
  audioElement.addEventListener("play", () => syncAudioTransportToServer({ force: true }));
  audioElement.addEventListener("pause", () => syncAudioTransportToServer({ force: true }));
  audioElement.addEventListener("seeking", () => syncAudioTransportToServer({ force: true }));
  audioElement.addEventListener("seeked", () => syncAudioTransportToServer({ force: true }));
  audioElement.addEventListener("loadedmetadata", () => syncAudioTransportToServer({ force: true }));
  audioElement.addEventListener("timeupdate", () => syncAudioTransportToServer());

  audioToggleButton.onclick = async () => {
    if (!audioElement) {
      return;
    }
    if (audioElement.paused) {
      await playAudio();
      return;
    }
    audioElement.pause();
    updatePlaybackState();
  };

  updatePlaybackState();
  syncAudioTransportToServer({ force: true });
  void playAudio();
}

function formatSeconds(value) {
  const seconds = Math.max(0, Math.floor(Number(value) || 0));
  const minutes = Math.floor(seconds / 60);
  const remain = seconds % 60;
  return `${String(minutes).padStart(2, "0")}:${String(remain).padStart(2, "0")}`;
}

function formatClock(date) {
  const hours = String(date.getHours()).padStart(2, "0");
  const minutes = String(date.getMinutes()).padStart(2, "0");
  const seconds = String(date.getSeconds()).padStart(2, "0");
  return `${hours}:${minutes}:${seconds}`;
}

function syncAudioTransportToServer({ force = false } = {}) {
  if (!audioElement) {
    return;
  }

  const now = performance.now();
  if (!force && now - lastTransportSyncAt < 80) {
    return;
  }

  const sent = client.send("transport_sync", {
    playing: !audioElement.paused,
    position_seconds: Number(audioElement.currentTime || 0)
  });
  if (sent) {
    lastTransportSyncAt = now;
  }
}

function bindVisualControl(control, key, parser = Number) {
  if (!control) return;
  control.addEventListener("input", () => {
    visualSettings[key] = parser(control.value);
    engine.setVisualSettings(visualSettings);
    renderReactivityStatus();
  });
}

function bindVisualPresetControls() {
  if (reactivitySaveButton) {
    reactivitySaveButton.addEventListener("click", () => {
      Object.assign(visualSettings, saveVisualSettingsPreset(browserStorage(), visualSettings));
      renderReactivityStatus("Saved");
    });
  }

  if (reactivityLoadButton) {
    reactivityLoadButton.addEventListener("click", () => {
      Object.assign(visualSettings, loadVisualSettingsPreset(browserStorage(), { fallback: visualSettings }));
      syncVisualControls();
      engine.setVisualSettings(visualSettings);
      renderReactivityStatus("Loaded");
    });
  }
}

function syncVisualControls() {
  setControlValue(visualGainControl, visualSettings.visualGain);
  setControlValue(bassBoostControl, visualSettings.bassBoost);
  setControlValue(smoothingControl, visualSettings.smoothing);
  setControlValue(beatHoldControl, visualSettings.beatHoldMs);
  setControlValue(wobbleControl, visualSettings.wobbleAmount);
}

function setControlValue(control, value) {
  if (control) {
    control.value = String(value);
  }
}

function browserStorage() {
  try {
    return window.localStorage;
  } catch {
    return null;
  }
}

function renderReactivityStatus(prefix = null) {
  if (!reactivityStatusElement) {
    return;
  }

  const values = [
    `Visual Gain: ${visualSettings.visualGain.toFixed(1)}x`,
    `Bass: ${visualSettings.bassBoost.toFixed(1)}x`,
    `Smooth: ${visualSettings.smoothing.toFixed(2)}`,
    `Beat Hold: ${Math.round(visualSettings.beatHoldMs)}ms`,
    `Wobble: ${visualSettings.wobbleAmount.toFixed(2)}x`,
  ].join(" | ");

  reactivityStatusElement.textContent = prefix ? `${prefix} | ${values}` : values;
}

function bindShaderErrorOverlay() {
  window.addEventListener(SHADER_ERROR_EVENT, (event) => {
    renderShaderError(event.detail);
  });
  if (shaderErrorCloseButton) {
    shaderErrorCloseButton.addEventListener("click", () => {
      if (shaderErrorOverlay) {
        shaderErrorOverlay.hidden = true;
      }
    });
  }
}

function renderShaderError(detail) {
  if (!shaderErrorOverlay || !shaderErrorTitleElement || !shaderErrorMessageElement) {
    return;
  }

  shaderErrorTitleElement.textContent = formatShaderErrorTitle(detail);
  shaderErrorMessageElement.textContent = formatShaderErrorMessage(detail);
  shaderErrorOverlay.hidden = false;
}

function initializeFftPreview(container) {
  if (!container) {
    return [];
  }

  const bars = Array.from({ length: DEFAULT_FFT_BINS }, () => {
    const bar = document.createElement("span");
    bar.className = "fft-bar";
    bar.setAttribute("aria-hidden", "true");
    return bar;
  });
  container.replaceChildren(...bars);
  return bars;
}

function renderAudioInspector(audio) {
  const state = buildAudioInspectorState(audio);
  setMeter(inspectorAmplitudeFill, inspectorAmplitudeValue, state.amplitude, 3);

  for (const key of BAND_KEYS) {
    const elements = inspectorBandElements[key] || {};
    setMeter(elements.fill, elements.value, state.bands[key], 2);
  }

  state.fft.forEach((value, index) => {
    const bar = fftBars[index];
    if (!bar) {
      return;
    }
    bar.style.setProperty("--bin-value", value.toFixed(4));
  });

  if (inspectorPeakElement) {
    inspectorPeakElement.textContent = state.peakFrequency > 0
      ? `Peak: ${Math.round(state.peakFrequency)} Hz`
      : "Peak: --";
  }
}

function setMeter(fill, valueElement, value, digits) {
  if (fill) {
    fill.style.setProperty("--meter-value", value.toFixed(4));
  }
  if (valueElement) {
    valueElement.textContent = formatMeterValue(value, digits);
  }
}

function buildWebSocketUrl() {
  const protocol = window.location.protocol === "https:" ? "wss" : "ws";
  return `${protocol}://${window.location.host}/ws`;
}
