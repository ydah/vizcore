import { BAND_KEYS, DEFAULT_FFT_BINS, buildAudioInspectorState, formatMeterValue } from "./audio-inspector.js";
import {
  createLiveControlState,
  isLiveControlEnabled,
  isTapTempoShortcut,
  keyboardActionForKey,
  liveControlStatusText,
  normalizeKeyboardMappings,
  normalizeLiveControlPayload,
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
  recordRendererCapabilities,
  recordRendererSafeMode,
  recordShaderCompile,
  recordWebSocketBackpressure,
  recordSocketFrame,
} from "./performance-monitor.js";
import {
  loadMidiLearnBindings,
  midiLearnActionLabel,
  midiMessageActive,
  midiMessageSignature,
  midiMessageUnitValue,
  midiSignatureLabel,
  saveMidiLearnBindings,
  upsertMidiLearnBinding,
} from "./midi-learn.js";
import { applyProjectorMode, resolveProjectorMode } from "./projector-mode.js";
import { Engine, RENDERER_CAPABILITIES_EVENT, RENDERER_SAFE_MODE_EVENT } from "./renderer/engine.js";
import { SHADER_COMPILE_EVENT } from "./renderer/shader-manager.js";
import {
  customShapeParamControlEntries,
  customShapeParamMessage,
  pruneCustomShapeParamOverrides
} from "./custom-shape-param-controls.js";
import {
  mappingTargetOptions,
  mappingTargetSignature
} from "./mapping-target-selector.js";
import {
  pruneShaderParamOverrides,
  shaderParamControlEntries
} from "./shader-param-controls.js";
import {
  normalizeShapeEditorPatch,
  pruneShapeEditorOverrides,
  shapeEditorEntries
} from "./shape-editor-controls.js";
import { normalizeRuntimeControlPreset } from "./runtime-control-preset.js";
import { SHADER_ERROR_EVENT, formatShaderErrorMessage, formatShaderErrorTitle } from "./shader-error-overlay.js";
import {
  exportVisualSettingsPreset,
  importVisualSettingsPreset,
  loadVisualSettingsPreset,
  saveVisualSettingsPreset,
  visualSettingFromUnit
} from "./visual-settings-preset.js";
import { applyScenePayload, resolveScenePayload } from "./scene-patches.js";
import { WebSocketClient } from "./websocket-client.js";

window.__vizcoreMainStarted = true;

const canvas = document.querySelector("#vizcore-canvas");
const wsStatusElement = document.querySelector("#ws-status");
const sceneStatusElement = document.querySelector("#scene-status");
const transitionStatusElement = document.querySelector("#transition-status");
const frameStatusElement = document.querySelector("#frame-status");
const runtimeErrorStatusElement = document.querySelector("#runtime-error-status");
const bpmStatusElement = document.querySelector("#bpm-status");
const beatStatusElement = document.querySelector("#beat-status");
const blackoutButton = document.querySelector("#blackout-toggle");
const freezeButton = document.querySelector("#freeze-toggle");
const liveControlStatusElement = document.querySelector("#live-control-status");
const performanceMonitorElement = document.querySelector("#performance-monitor");
const inspectorPeakElement = document.querySelector("#inspector-peak");
const inspectorHiraganaElement = document.querySelector("#inspector-hiragana");
const inspectorHiraganaDetailElement = document.querySelector("#inspector-hiragana-detail");
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
const audioHealthStatusElement = document.querySelector("#audio-health-status");
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
const reactivityProjectSaveButton = document.querySelector("#reactivity-project-save");
const reactivityExportButton = document.querySelector("#reactivity-export");
const reactivityImportButton = document.querySelector("#reactivity-import");
const reactivityStatusElement = document.querySelector("#reactivity-status");
const midiLearnStatusElement = document.querySelector("#midi-learn-status");
const midiLearnButtons = Array.from(document.querySelectorAll("[data-midi-learn-action]"));
const shaderParamControlsElement = document.querySelector("#shader-param-controls");
const shapeEditorControlsElement = document.querySelector("#shape-editor-controls");
const customShapeParamControlsElement = document.querySelector("#custom-shape-param-controls");
const mappingTargetSelectorElement = document.querySelector("#mapping-target-selector");
const shaderErrorOverlay = document.querySelector("#shader-error-overlay");
const shaderErrorTitleElement = document.querySelector("#shader-error-title");
const shaderErrorMessageElement = document.querySelector("#shader-error-message");
const shaderErrorCloseButton = document.querySelector("#shader-error-close");
const LATENCY_PROBE_INTERVAL_MS = 3000;
const RUNTIME_REFRESH_INTERVAL_MS = 1500;
const RUNTIME_RETRY_INTERVAL_MS = 800;
const frontendAssetVersion = frontendAssetVersionFromScripts({
  scripts: document.scripts,
  baseUrl: window.location.href
});

const visualSettings = loadVisualSettingsPreset(browserStorage());
let midiLearnBindings = loadMidiLearnBindings(browserStorage());
const liveControls = createLiveControlState();
const performanceMonitor = createPerformanceMonitorState();
let projectorMode = resolveProjectorMode({ body: document.body, location: window.location });
let currentSceneName = "unknown";
let audioElement = null;
let currentAudioFileUrl = null;
let audioStartGestureCleanup = null;
let websocketRole = "control";
let frameCount = 0;
let lastConnectedAt = null;
let lastTransportSyncAt = 0;
let latencyProbeTimer = null;
let runtimeRefreshTimer = null;
let runtimeRefreshInFlight = null;
let beatFlashUntil = 0;
let availableSceneNames = [];
let keyboardMappings = [];
let pendingSceneName = null;
let pendingSceneRequestedAt = 0;
let tapTempoKey = null;
let runtimeGlobalsReceived = false;
let runtimeControlPresetApplied = false;
let runtimeControlPresetSceneApplied = null;
let runtimeControlPresetSceneOverrides = {};
let runtimeControlPresetVisualBase = null;
let runtimeControlPresetMidiBase = null;
let controlPresetSaveUrl = null;
let shaderParamOverrides = {};
let scenePayload = null;
let shaderParamControlsSignature = "";
let shapeEditorOverrides = {};
let shapeEditorControlsSignature = "";
let customShapeParamOverrides = {};
let customShapeParamControlsSignature = "";
let mappingTargetSelectorSignature = "";
let selectedMappingTarget = "";
let midiAccess = null;
let pendingMidiLearnAction = null;
applyProjectorMode(document.body, projectorMode);
const engine = new Engine(canvas);
let rendererReady = false;
bindShaderCompileMetrics();
bindRendererMetrics();
try {
  engine.init();
  rendererReady = true;
} catch (error) {
  renderShaderError({
    layer: "renderer",
    shader: "webgl2",
    message: error instanceof Error ? error.message : String(error)
  });
}
engine.setVisualSettings(visualSettings);
engine.setLiveControls(liveControls);
bindLiveControls();
bindVisualControl(visualGainControl, "visualGain");
bindVisualControl(bassBoostControl, "bassBoost");
bindVisualControl(smoothingControl, "smoothing");
bindVisualControl(beatHoldControl, "beatHoldMs");
bindVisualControl(wobbleControl, "wobbleAmount");
bindVisualPresetControls();
bindMidiLearnControls();
renderLiveControlStatus();
renderPerformanceMonitor();
syncVisualControls();
renderReactivityStatus();
renderMidiLearnStatus();
bindShaderErrorOverlay();
const fftBars = initializeFftPreview(fftPreviewElement);
if (rendererReady) {
  engine.start();
}
startPerformanceMonitorLoop();

const websocketUrl = buildWebSocketUrl();
const client = new WebSocketClient(websocketUrl, {
  onFrame: (frame) => {
    const resolvedScene = resolveScenePayload({
      incomingScene: frame?.scene,
      currentScene: scenePayload,
      frameVersion: frame?.scene_version,
    });
    if (resolvedScene) {
      scenePayload = resolvedScene;
    }
    const normalizedFrame = {
      ...frame,
      scene: scenePayload
    };

    updatePerformanceMonitor(recordSocketFrame(performanceMonitor, frame, Date.now()));
    engine.setAudioFrame(normalizedFrame);
    frameCount += 1;
    const scene = scenePayload;
    let sceneName = String(scene?.name || currentSceneName);
    document.body.dataset.vizcoreFrameCount = String(frameCount);
    document.body.dataset.vizcoreScene = sceneName;
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
    applyRuntimeControlPresetForScene(sceneName);
    updateSceneControls(scene);
    const amplitude = Number(frame?.audio?.amplitude || 0).toFixed(4);
    const bpm = Number(frame?.audio?.bpm || 0);
    const beat = !!frame?.audio?.beat;
    const beatCount = Math.max(0, Number(frame?.audio?.beat_count || 0) || 0);
    if (beat) {
      beatFlashUntil = performance.now() + visualSettings.beatHoldMs;
    }
    const beatVisible = performance.now() < beatFlashUntil;
    sceneStatusElement.textContent = `Scene: ${sceneName}`;
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
    applyRuntimeControlPresetForScene(to, { force: true });
    transitionStatusElement.textContent = `Transition: ${from} -> ${to}`;
    renderSceneButtons();
  },
  onConfigUpdate: (payload) => {
    updateAvailableScenes(payload?.scenes);
    const sceneName = payload?.scene?.name;
    if (sceneName) {
      scenePayload = applyScenePayload(payload.scene);
      applyRuntimeControlPresetForScene(sceneName, { force: true });
      updateSceneControls(scenePayload, { forceReset: true });
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
    if (Object.prototype.hasOwnProperty.call(payload || {}, "live_controls")) {
      applyLiveControls({
        ...normalizeLiveControls(payload?.live_controls),
      });
    }
  },
  onLatencyProbe: (payload) => {
    updatePerformanceMonitor(recordLatencyProbe(performanceMonitor, payload, Date.now()));
  },
  onRuntimeError: (payload) => {
    updateRuntimeErrorStatus(payload);
  },
  onStatus: (status) => {
    updatePerformanceMonitor(recordConnectionStatus(performanceMonitor, status));
    if (status === "connected") {
      lastConnectedAt = new Date();
      startLatencyProbeLoop();
      void refreshRuntime({ force: true });
      syncAudioTransportToServer({ force: true });
      if (runtimeErrorStatusElement) {
        runtimeErrorStatusElement.textContent = "Runtime: ok";
      }
    } else {
      stopLatencyProbeLoop();
      pendingSceneName = null;
      pendingSceneRequestedAt = 0;
      currentSceneName = "unknown";
      sceneStatusElement.textContent = "Scene: unknown";
      renderSceneButtons();
      if (runtimeErrorStatusElement) {
        runtimeErrorStatusElement.textContent = "Runtime: disconnected";
      }
    }
  const connectedAt = lastConnectedAt ? ` | Last connected: ${formatClock(lastConnectedAt)}` : "";
  wsStatusElement.textContent = `WebSocket: ${status} (${websocketUrl})${connectedAt}`;
  }
});

client.connect();
void initializeRuntime();

async function initializeRuntime() {
  await refreshRuntime({ scheduleNext: true });
}

async function refreshRuntime({ scheduleNext = false, force = false } = {}) {
  if (runtimeRefreshInFlight && !force) {
    return runtimeRefreshInFlight;
  }

  runtimeRefreshInFlight = (async () => {
    const runtime = await fetchRuntime();
    if (!runtime) {
      if (scheduleNext) {
        scheduleRuntimeRefresh(RUNTIME_RETRY_INTERVAL_MS);
      }
      return null;
    }

    if (shouldReloadForFrontendAsset(runtime)) {
      return runtime;
    }

    applyRuntime(runtime);
    if (scheduleNext) {
      scheduleRuntimeRefresh(RUNTIME_REFRESH_INTERVAL_MS);
    }
    return runtime;
  })();

  try {
    return await runtimeRefreshInFlight;
  } finally {
    runtimeRefreshInFlight = null;
  }
}

function scheduleRuntimeRefresh(delayMs) {
  if (runtimeRefreshTimer) {
    clearTimeout(runtimeRefreshTimer);
  }

  runtimeRefreshTimer = setTimeout(() => {
    runtimeRefreshTimer = null;
    void refreshRuntime({ scheduleNext: true });
  }, Math.max(250, Number(delayMs || RUNTIME_REFRESH_INTERVAL_MS)));
}

function shouldReloadForFrontendAsset(runtime) {
  if (!shouldReloadForFrontendAssetVersion({
    currentVersion: frontendAssetVersion,
    runtimeVersion: runtime?.frontend_asset_version
  })) {
    return false;
  }

  window.location.reload();
  return true;
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
  updateControlPresetPersistence(runtime);
  if (!runtimeGlobalsReceived) {
    applyRuntimeGlobals(runtime?.globals);
  }
  applyRuntimeControlPreset(runtime?.control_preset);
  updatePerformanceMonitor(recordWebSocketBackpressure(performanceMonitor, runtime?.websocket_backpressure));

  const fileName = runtime?.audio_file_name;
  const fileUrl = runtime?.audio_file_url;
  applyRuntimeAudioInputHealth(runtime?.input);
  if (!fileUrl) {
    clearAudioPlayback();
    audioTrackStatusElement.textContent = "Track: none";
    audioPlaybackStatusElement.textContent = "Playback: unavailable";
    audioToggleButton.hidden = true;
    return;
  }

  audioTrackStatusElement.textContent = `Track: ${String(fileName || "source file")}`;
  const nextAudioFileUrl = String(fileUrl);
  if (currentAudioFileUrl !== nextAudioFileUrl || !audioElement) {
    setupAudioPlayback(nextAudioFileUrl);
  }
}

function applyRuntimeAudioInputHealth(input) {
  if (!audioHealthStatusElement) {
    return;
  }

  const source = String(input?.source || "unknown");
  const sampleRate = Number(input?.sample_rate);
  const requestedSampleRate = Number(input?.requested_sample_rate);
  const frameSize = Number(input?.frame_size);
  const ringBuffer = input?.ring_buffer || {};
  const overrun = Number(ringBuffer?.overrun_count || 0);
  const underrun = Number(ringBuffer?.underrun_count || 0);
  const sampleRateText = Number.isFinite(sampleRate) && sampleRate > 0
    ? `${Math.round(sampleRate)}Hz`
    : "--";
  const requestedSampleRateText = Number.isFinite(requestedSampleRate) &&
      requestedSampleRate > 0 &&
      requestedSampleRate !== sampleRate
    ? ` (${Math.round(requestedSampleRate)}Hz requested)`
    : "";
  const frameText = Number.isFinite(frameSize) && frameSize > 0
    ? ` | Frame ${Math.round(frameSize)}`
    : "";

  audioHealthStatusElement.textContent = `Input: ${source} | Sample ${sampleRateText}${requestedSampleRateText} | ${frameText} | Overrun ${Math.max(0, overrun)} | Underrun ${Math.max(0, underrun)}`;
}

function applyRuntimeGlobals(globals) {
  engine.setRuntimeGlobals(globals);
}

function updateControlPresetPersistence(runtime) {
  const url = String(runtime?.control_preset_url || "").trim();
  controlPresetSaveUrl = runtime?.control_preset_writable && url ? url : null;
  if (reactivityProjectSaveButton) {
    reactivityProjectSaveButton.hidden = !controlPresetSaveUrl;
  }
}

function applyRuntimeControlPreset(value) {
  if (!value || runtimeControlPresetApplied) {
    return;
  }

  const preset = normalizeRuntimeControlPreset(value);
  const hasVisual = Boolean(preset.visualSettings);
  const hasMidi = Boolean(preset.midiLearnBindings);
  const hasSceneOverrides = preset.sceneOverrides && Object.keys(preset.sceneOverrides).length > 0;
  if (!hasVisual && !hasMidi && !hasSceneOverrides) {
    return;
  }

  if (hasVisual) {
    const imported = importVisualSettingsPreset(
      { visual_settings: preset.visualSettings },
      { fallback: visualSettings }
    );
    Object.assign(visualSettings, imported);
    runtimeControlPresetVisualBase = cloneRuntimeValue(visualSettings);
    saveVisualSettingsPreset(browserStorage(), visualSettings);
    syncVisualControls();
    engine.setVisualSettings(visualSettings);
    renderReactivityStatus("Project preset");
  } else {
    runtimeControlPresetVisualBase = cloneRuntimeValue(visualSettings);
  }

  if (hasMidi) {
    midiLearnBindings = cloneRuntimeValue(preset.midiLearnBindings);
    runtimeControlPresetMidiBase = cloneRuntimeValue(midiLearnBindings);
    saveMidiLearnBindings(browserStorage(), midiLearnBindings);
    renderMidiLearnStatus();
  } else {
    runtimeControlPresetMidiBase = cloneRuntimeValue(midiLearnBindings);
  }

  runtimeControlPresetSceneOverrides = cloneRuntimeValue(preset.sceneOverrides || {});
  runtimeControlPresetApplied = true;
  runtimeControlPresetSceneApplied = null;
  applyRuntimeControlPresetForScene(currentSceneName, { force: true });
}

function applyRuntimeControlPresetForScene(sceneName, { force = false } = {}) {
  if (!runtimeControlPresetApplied) {
    return;
  }

  const normalizedScene = normalizeSceneName(sceneName || currentSceneName);
  if (!force && runtimeControlPresetSceneApplied === normalizedScene) {
    return;
  }
  runtimeControlPresetSceneApplied = normalizedScene;

  const override = normalizeRuntimeSceneOverride(runtimeControlPresetSceneOverrides[normalizedScene]) || {};
  const nextVisual = deriveSceneVisualSettings(runtimeControlPresetVisualBase, override.visualSettings);
  if (nextVisual) {
    const hasVisualChanges = hasVisualSettingsChanges(visualSettings, nextVisual);
    if (hasVisualChanges) {
      Object.assign(visualSettings, nextVisual);
      syncVisualControls();
      engine.setVisualSettings(visualSettings);
      renderReactivityStatus("Project preset");
    }
  }

  const nextBindings = deriveSceneMidiBindings(runtimeControlPresetMidiBase, override.midiLearnBindings);
  if (nextBindings && hasMidiLearnBindingChanges(midiLearnBindings, nextBindings)) {
    midiLearnBindings = nextBindings;
    renderMidiLearnStatus();
  }
}

function deriveSceneVisualSettings(baseSettings, sceneVisualSettings) {
  const base = baseSettings && typeof baseSettings === "object" ? cloneRuntimeValue(baseSettings) : {};
  if (sceneVisualSettings) {
    return Object.assign(base, cloneRuntimeValue(sceneVisualSettings));
  }
  return Object.keys(base).length ? base : null;
}

function deriveSceneMidiBindings(baseBindings, sceneMidiBindings) {
  const base = baseBindings && typeof baseBindings === "object" ? cloneRuntimeValue(baseBindings) : {};
  if (sceneMidiBindings) {
    return Object.assign(base, cloneRuntimeValue(sceneMidiBindings));
  }
  return Object.keys(base).length ? base : null;
}

function normalizeRuntimeSceneOverride(value) {
  if (!value || typeof value !== "object") {
    return null;
  }

  const input = value && typeof value === "object" ? value : {};
  const output = {};
  const visualSettings = objectValue(input.visualSettings) || objectValue(input.visual_settings);
  const midiLearnBindings = objectValue(input.midiLearnBindings) || objectValue(input.midi_learn_bindings);
  if (visualSettings) {
    output.visualSettings = visualSettings;
  }
  if (midiLearnBindings) {
    output.midiLearnBindings = midiLearnBindings;
  }
  return Object.keys(output).length ? output : null;
}

function syncRuntimeControlPresetSceneVisualSetting(key, value) {
  if (!runtimeControlPresetApplied) {
    return;
  }

  const sceneName = normalizeSceneName(currentSceneName);
  const override = runtimeControlPresetSceneOverrides[sceneName];
  if (override && typeof override === "object") {
    const normalizedSceneOverride = normalizeRuntimeSceneOverride(override) || {};
    const currentOverride = cloneRuntimeValue(normalizedSceneOverride);
    currentOverride.visualSettings ||= {};
    currentOverride.visualSettings[key] = value;
    runtimeControlPresetSceneOverrides[sceneName] = currentOverride;
    applyRuntimeControlPresetForScene(sceneName, { force: true });
    return;
  }

  runtimeControlPresetVisualBase = runtimeControlPresetVisualBase || cloneRuntimeValue(visualSettings);
  runtimeControlPresetVisualBase[key] = value;
}

function syncRuntimeControlPresetMidiBindings(nextBindings) {
  if (!runtimeControlPresetApplied) {
    return;
  }

  const sceneName = normalizeSceneName(currentSceneName);
  const normalizedBindings = objectValue(nextBindings) ? cloneRuntimeValue(nextBindings) : {};
  const override = runtimeControlPresetSceneOverrides[sceneName];
  if (override && typeof override === "object") {
    const normalizedSceneOverride = normalizeRuntimeSceneOverride(override) || {};
    const currentOverride = cloneRuntimeValue(normalizedSceneOverride);
    currentOverride.midiLearnBindings = normalizedBindings;
    runtimeControlPresetSceneOverrides[sceneName] = currentOverride;
    applyRuntimeControlPresetForScene(sceneName, { force: true });
    return;
  }

  runtimeControlPresetMidiBase = normalizedBindings;
}

function syncRuntimeControlPresetBaseWithRuntime(nextVisualSettings = visualSettings) {
  if (!runtimeControlPresetApplied) {
    return;
  }

  runtimeControlPresetVisualBase = cloneRuntimeValue(nextVisualSettings);
}

function hasVisualSettingsChanges(currentValue, nextValue) {
  return (
    currentValue.visualGain !== nextValue.visualGain ||
    currentValue.bassBoost !== nextValue.bassBoost ||
    currentValue.smoothing !== nextValue.smoothing ||
    currentValue.beatHoldMs !== nextValue.beatHoldMs ||
    currentValue.wobbleAmount !== nextValue.wobbleAmount
  );
}

function hasMidiLearnBindingChanges(currentBindings, nextBindings) {
  if (!nextBindings) {
    return false;
  }
  const currentKeys = Object.keys(currentBindings || {});
  const nextKeys = Object.keys(nextBindings);
  if (currentKeys.length !== nextKeys.length) {
    return true;
  }
  for (const signature of nextKeys) {
    if (!Object.prototype.hasOwnProperty.call(currentBindings, signature)) {
      return true;
    }
    if (JSON.stringify(currentBindings[signature]) !== JSON.stringify(nextBindings[signature])) {
      return true;
    }
  }
  return false;
}

function normalizeSceneName(sceneName) {
  return String(sceneName || "").trim() || "unknown";
}

function objectValue(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : null;
}

function cloneRuntimeValue(value) {
  if (!value || typeof value !== "object") {
    return {};
  }

  return JSON.parse(JSON.stringify(value));
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

function updateSceneControls(scene, { forceReset = false } = {}) {
  const sceneLayers = scene?.layers;
  const hasLayers = Array.isArray(sceneLayers);
  const nextSceneName = String(scene?.name || currentSceneName);

  if (currentSceneName !== nextSceneName) {
    currentSceneName = nextSceneName;
    sceneStatusElement.textContent = `Scene: ${currentSceneName}`;
    renderSceneButtons();
    forceReset = true;
  }

  if (!scene) {
    return;
  }

  if (forceReset) {
    shaderParamControlsSignature = "";
    shapeEditorControlsSignature = "";
    customShapeParamControlsSignature = "";
    mappingTargetSelectorSignature = "";
  }

  updateShaderParamControls(hasLayers ? sceneLayers : null);
  updateShapeEditorControls(hasLayers ? sceneLayers : null);
  updateCustomShapeParamControls(hasLayers ? sceneLayers : null);
  updateMappingTargetSelector(hasLayers ? sceneLayers : null);
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

function updateShapeEditorControls(layers) {
  const entries = shapeEditorEntries(layers, shapeEditorOverrides);
  const signature = shapeEditorControlsSignatureFor(entries);
  if (signature === shapeEditorControlsSignature) {
    return;
  }

  shapeEditorControlsSignature = signature;
  shapeEditorOverrides = pruneShapeEditorOverrides(shapeEditorOverrides, entries);
  engine.setShapeEditorOverrides(shapeEditorOverrides);
  renderShapeEditorControls(entries);
}

function shapeEditorControlsSignatureFor(entries) {
  return entries.map((entry) => (
    `${entry.key}:${entry.kind}:${JSON.stringify(entry.values)}`
  )).join("|");
}

function renderShapeEditorControls(entries) {
  if (!shapeEditorControlsElement) {
    return;
  }

  if (!entries.length) {
    shapeEditorControlsElement.hidden = true;
    shapeEditorControlsElement.replaceChildren();
    return;
  }

  const title = document.createElement("p");
  title.className = "shader-param-controls__title";
  title.textContent = "Shape Editor";
  const controls = entries.map((entry) => createShapeEditorControl(entry));
  shapeEditorControlsElement.replaceChildren(title, ...controls);
  shapeEditorControlsElement.hidden = false;
}

function createShapeEditorControl(entry) {
  const section = document.createElement("details");
  const summary = document.createElement("summary");
  summary.textContent = entry.label;
  section.append(summary);
  section.append(
    createShapeKindControl(entry),
    createShapeNumberControl(entry, "translateX", "Move X", -640, 640, 1),
    createShapeNumberControl(entry, "translateY", "Move Y", -360, 360, 1),
    createShapeNumberControl(entry, "rotate", "Rotate", -180, 180, 1),
    createShapeNumberControl(entry, "scaleX", "Scale X", -4, 4, 0.05),
    createShapeNumberControl(entry, "scaleY", "Scale Y", -4, 4, 0.05),
    createShapeNumberControl(entry, "opacity", "Opacity", 0, 1, 0.05),
    createShapeColorControl(entry, "fill", "Fill"),
    createShapeColorControl(entry, "strokeColor", "Stroke"),
    createShapeNumberControl(entry, "strokeWidth", "Stroke W", 0, 24, 0.5)
  );
  return section;
}

function createShapeKindControl(entry) {
  const label = document.createElement("label");
  const name = document.createElement("span");
  const select = document.createElement("select");
  name.textContent = "Kind";
  ["circle", "line", "rect", "polygon", "polyline", "path", "star"].forEach((kind) => {
    const option = document.createElement("option");
    option.value = kind;
    option.textContent = kind;
    select.append(option);
  });
  select.value = entry.kind;
  select.addEventListener("change", () => {
    writeShapeEditorOverride(entry, { ...entry.values, kind: select.value });
  });
  label.append(name, select);
  return label;
}

function createShapeNumberControl(entry, key, labelText, min, max, step) {
  const label = document.createElement("label");
  const name = document.createElement("span");
  const input = document.createElement("input");
  const value = document.createElement("output");
  name.textContent = labelText;
  input.type = "range";
  input.min = String(min);
  input.max = String(max);
  input.step = String(step);
  input.value = String(entry.values[key]);
  value.value = formatShaderParamValue(entry.values[key]);
  input.addEventListener("input", () => {
    const numeric = Number(input.value);
    writeShapeEditorOverride(entry, { ...entry.values, [key]: numeric });
    value.value = formatShaderParamValue(numeric);
  });
  label.append(name, input, value);
  return label;
}

function createShapeColorControl(entry, key, labelText) {
  const label = document.createElement("label");
  const name = document.createElement("span");
  const input = document.createElement("input");
  const value = document.createElement("output");
  name.textContent = labelText;
  input.type = "color";
  input.value = entry.values[key];
  value.value = entry.values[key];
  input.addEventListener("input", () => {
    writeShapeEditorOverride(entry, { ...entry.values, [key]: input.value, [`${key}Enabled`]: true });
    value.value = input.value;
  });
  label.append(name, input, value);
  return label;
}

function writeShapeEditorOverride(entry, values) {
  shapeEditorOverrides[entry.layerKey] ||= {};
  shapeEditorOverrides[entry.layerKey][entry.shapeIndex] = normalizeShapeEditorPatch(values);
  engine.setShapeEditorOverrides(shapeEditorOverrides);
}

function updateCustomShapeParamControls(layers) {
  const entries = customShapeParamControlEntries(layers, customShapeParamOverrides);
  const signature = customShapeParamControlsSignatureFor(entries);
  if (signature === customShapeParamControlsSignature) {
    return;
  }

  customShapeParamControlsSignature = signature;
  customShapeParamOverrides = pruneCustomShapeParamOverrides(customShapeParamOverrides, entries);
  renderCustomShapeParamControls(entries);
}

function customShapeParamControlsSignatureFor(entries) {
  return entries.map((entry) => (
    `${entry.key}:${entry.min}:${entry.max}:${entry.step}:${entry.value}`
  )).join("|");
}

function renderCustomShapeParamControls(entries) {
  if (!customShapeParamControlsElement) {
    return;
  }

  if (!entries.length) {
    customShapeParamControlsElement.hidden = true;
    customShapeParamControlsElement.replaceChildren();
    return;
  }

  const title = document.createElement("p");
  title.className = "shader-param-controls__title";
  title.textContent = "Custom Shape Params";
  const controls = entries.map((entry) => createCustomShapeParamControl(entry));
  customShapeParamControlsElement.replaceChildren(title, ...controls);
  customShapeParamControlsElement.hidden = false;
}

function createCustomShapeParamControl(entry) {
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
    customShapeParamOverrides[entry.layerKey] ||= {};
    customShapeParamOverrides[entry.layerKey][entry.customShapeIndex] ||= {};
    customShapeParamOverrides[entry.layerKey][entry.customShapeIndex][entry.paramName] = numeric;
    client.send("custom_shape_param", customShapeParamMessage(entry, numeric));
    value.value = formatShaderParamValue(numeric);
  });
  label.append(name, input, value);
  return label;
}

function updateMappingTargetSelector(layers) {
  const options = mappingTargetOptions(layers);
  const signature = mappingTargetSignature(options);
  if (signature === mappingTargetSelectorSignature) {
    return;
  }

  mappingTargetSelectorSignature = signature;
  renderMappingTargetSelector(options);
}

function renderMappingTargetSelector(options) {
  if (!mappingTargetSelectorElement) {
    return;
  }

  if (!options.length) {
    selectedMappingTarget = "";
    mappingTargetSelectorElement.hidden = true;
    mappingTargetSelectorElement.replaceChildren();
    return;
  }

  const title = document.createElement("p");
  title.className = "shader-param-controls__title";
  title.textContent = "Mapping Targets";
  const label = document.createElement("label");
  const name = document.createElement("span");
  const select = document.createElement("select");
  const output = document.createElement("output");
  name.textContent = "Target";
  options.forEach((option) => {
    const item = document.createElement("option");
    item.value = option.target;
    item.textContent = option.label;
    select.append(item);
  });
  if (!options.some((option) => option.target === selectedMappingTarget)) {
    selectedMappingTarget = options[0].target;
  }
  select.value = selectedMappingTarget;
  output.value = selectedMappingTarget;
  select.addEventListener("change", () => {
    selectedMappingTarget = select.value;
    output.value = select.value;
  });
  label.append(name, select, output);
  mappingTargetSelectorElement.replaceChildren(title, label);
  mappingTargetSelectorElement.hidden = false;
}

function requestSceneSwitch(sceneName, effect = null) {
  if (!sceneName || sceneName === currentSceneName) {
    return;
  }

  pendingSceneName = sceneName;
  pendingSceneRequestedAt = performance.now();
  currentSceneName = sceneName;
  sceneStatusElement.textContent = `Scene: ${sceneName}`;
  renderSceneButtons();
  const payload = { scene: sceneName };
  const normalizedEffect = normalizeTransitionEffect(effect);
  if (normalizedEffect) {
    payload.effect = normalizedEffect;
  }
  client.send("switch_scene", payload);
}

function applyKeyboardAction(action) {
  if (action?.type === "switch_scene") {
    requestSceneSwitch(action.scene, action.effect);
    return;
  }

  if (action?.type === "live_control") {
    if (Object.prototype.hasOwnProperty.call(action, "value")) {
      applyLiveControls({
        [action?.control]: normalizeLiveControlPayload(action),
      });
      return;
    }

    applyLiveControls(toggleLiveControl(liveControls, action?.control));
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

function normalizeTransitionEffect(effect) {
  if (!effect) {
    return null;
  }
  if (typeof effect === "string" || typeof effect === "number" || typeof effect === "symbol") {
    return String(effect);
  }
  if (typeof effect !== "object" || Array.isArray(effect)) {
    return null;
  }

  return effect;
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

function bindRendererMetrics() {
  window.addEventListener(RENDERER_CAPABILITIES_EVENT, (event) => {
    updatePerformanceMonitor(recordRendererCapabilities(performanceMonitor, event.detail));
  });
  window.addEventListener(RENDERER_SAFE_MODE_EVENT, (event) => {
    updatePerformanceMonitor(recordRendererSafeMode(performanceMonitor, event.detail));
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
      applyKeyboardAction({ type: "live_control", control: action });
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
  if (!nextState || typeof nextState !== "object") {
    return;
  }

  const nextBlackout = mergeLiveControlState(
    liveControls.blackout,
    nextState.blackout
  );
  const nextFreeze = mergeLiveControlState(
    liveControls.freeze,
    nextState.freeze
  );
  Object.assign(liveControls, {
    blackout: nextBlackout,
    freeze: nextFreeze,
  });
  engine.setLiveControls(liveControls);
  renderLiveControlStatus();
}

function mergeLiveControlState(currentState, nextState) {
  const current = normalizeLiveControlPayload(currentState);
  if (nextState === undefined) {
    return current;
  }
  if (!nextState || typeof nextState !== "object" || Array.isArray(nextState)) {
    return normalizeLiveControlPayload(nextState);
  }

  const normalized = normalizeLiveControlPayload(nextState);
  const nextHasFade = Object.prototype.hasOwnProperty.call(nextState, "fade");
  const nextHasRelease = Object.prototype.hasOwnProperty.call(nextState, "release");
  const nextHasColor = Object.prototype.hasOwnProperty.call(nextState, "color");

  return {
    ...current,
    ...normalized,
    ...(nextHasFade ? { fade: normalized.fade } : {}),
    ...(nextHasRelease ? { release: normalized.release } : {}),
    ...(nextHasColor ? { color: normalized.color } : {}),
  };
}

function normalizeLiveControls(value) {
  const input = value && typeof value === "object" ? value : {};
  return {
    blackout: normalizeLiveControlPayload(input.blackout),
    freeze: normalizeLiveControlPayload(input.freeze),
  };
}

function renderLiveControlStatus() {
  if (liveControlStatusElement) {
    liveControlStatusElement.textContent = liveControlStatusText(liveControls);
  }

  if (blackoutButton) {
    const isActive = isLiveControlEnabled(liveControls.blackout);
    blackoutButton.classList.toggle("is-active", isActive);
    blackoutButton.setAttribute("aria-pressed", String(isActive));
  }

  if (freezeButton) {
    const isActive = isLiveControlEnabled(liveControls.freeze);
    freezeButton.classList.toggle("is-active", isActive);
    freezeButton.setAttribute("aria-pressed", String(isActive));
  }
}

function setupAudioPlayback(audioUrl) {
  if (audioElement) {
    audioElement.pause();
  }
  clearAudioStartGesture();

  currentAudioFileUrl = String(audioUrl || "");
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
      return false;
    }
    try {
      await audioElement.play();
      updatePlaybackState();
      clearAudioStartGesture();
      return true;
    } catch (error) {
      const message = String(error?.message || "autoplay blocked");
      audioPlaybackStatusElement.textContent = `Playback: blocked (${message})`;
      audioToggleButton.textContent = "Play Audio";
      return false;
    }
  };

  const syncPlaybackTransportToServer = (options = {}) => {
    syncAudioTransportToServer({ ...options, allowReadOnlyStart: true });
  };

  audioElement.addEventListener("play", updatePlaybackState);
  audioElement.addEventListener("pause", updatePlaybackState);
  audioElement.addEventListener("timeupdate", updatePlaybackState);
  audioElement.addEventListener("loadedmetadata", updatePlaybackState);
  audioElement.addEventListener("play", () => syncPlaybackTransportToServer({ force: true }));
  audioElement.addEventListener("pause", () => syncPlaybackTransportToServer({ force: true }));
  audioElement.addEventListener("seeking", () => syncPlaybackTransportToServer({ force: true }));
  audioElement.addEventListener("seeked", () => syncPlaybackTransportToServer({ force: true }));
  audioElement.addEventListener("loadedmetadata", () => syncPlaybackTransportToServer({ force: true }));
  audioElement.addEventListener("timeupdate", () => syncPlaybackTransportToServer());

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
  bindProjectorAudioStartGesture(playAudio);
  syncAudioTransportToServer({ force: true });
  void playAudio();
}

function clearAudioPlayback() {
  if (audioElement) {
    audioElement.pause();
  }
  audioElement = null;
  currentAudioFileUrl = null;
  engine.setMediaElement(null);
  clearAudioStartGesture();
}

function clearAudioStartGesture() {
  if (!audioStartGestureCleanup) {
    return;
  }

  audioStartGestureCleanup();
  audioStartGestureCleanup = null;
}

function bindProjectorAudioStartGesture(playAudio) {
  clearAudioStartGesture();
  if (!projectorMode || typeof playAudio !== "function") {
    return;
  }

  const startFromGesture = async () => {
    if (!audioElement || !audioElement.paused) {
      clearAudioStartGesture();
      return;
    }

    await playAudio();
  };

  window.addEventListener("pointerdown", startFromGesture, true);
  window.addEventListener("keydown", startFromGesture, true);
  audioStartGestureCleanup = () => {
    window.removeEventListener("pointerdown", startFromGesture, true);
    window.removeEventListener("keydown", startFromGesture, true);
  };
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

function syncAudioTransportToServer({ force = false, allowReadOnlyStart = false } = {}) {
  if (!audioElement) {
    return;
  }

  const playing = !audioElement.paused;
  if (!canSendAudioTransport({ role: websocketRole, playing, allowReadOnlyStart })) {
    return;
  }

  const now = performance.now();
  if (!force && now - lastTransportSyncAt < 80) {
    return;
  }

  const sent = client.send("transport_sync", {
    playing,
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
    syncRuntimeControlPresetSceneVisualSetting(key, visualSettings[key]);
  });
}

function bindVisualPresetControls() {
  if (reactivitySaveButton) {
    reactivitySaveButton.addEventListener("click", () => {
      Object.assign(visualSettings, saveVisualSettingsPreset(browserStorage(), visualSettings));
      syncRuntimeControlPresetBaseWithRuntime(visualSettings);
      renderReactivityStatus("Saved");
    });
  }

  if (reactivityLoadButton) {
    reactivityLoadButton.addEventListener("click", () => {
      Object.assign(visualSettings, loadVisualSettingsPreset(browserStorage(), { fallback: visualSettings }));
      syncVisualControls();
      engine.setVisualSettings(visualSettings);
      syncRuntimeControlPresetBaseWithRuntime(visualSettings);
      renderReactivityStatus("Loaded");
    });
  }

  if (reactivityProjectSaveButton) {
    reactivityProjectSaveButton.addEventListener("click", async () => {
      if (!controlPresetSaveUrl) {
        renderReactivityStatus("Project save unavailable");
        return;
      }

      const saved = await saveProjectControlPreset();
      renderReactivityStatus(saved ? "Project saved" : "Project save failed");
    });
  }

  if (reactivityExportButton) {
    reactivityExportButton.addEventListener("click", async () => {
      const payload = exportVisualSettingsPreset(visualSettings);
      const copied = await writeClipboardText(payload);
      if (!copied && typeof window.prompt === "function") {
        window.prompt("Visual preset JSON", payload);
      }
      renderReactivityStatus(copied ? "Exported" : "Export ready");
    });
  }

  if (reactivityImportButton) {
    reactivityImportButton.addEventListener("click", () => {
      if (typeof window.prompt !== "function") {
        renderReactivityStatus("Import unavailable");
        return;
      }

      const payload = window.prompt("Paste visual preset JSON");
      if (!payload) {
        renderReactivityStatus();
        return;
      }

      Object.assign(visualSettings, importVisualSettingsPreset(payload, { fallback: visualSettings }));
      Object.assign(visualSettings, saveVisualSettingsPreset(browserStorage(), visualSettings));
      syncVisualControls();
      engine.setVisualSettings(visualSettings);
      syncRuntimeControlPresetBaseWithRuntime(visualSettings);
      renderReactivityStatus("Imported");
    });
  }
}

async function saveProjectControlPreset() {
  try {
    const response = await fetch(controlPresetSaveUrl, {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        visual_settings: visualSettings,
        midi_learn_bindings: midiLearnBindings,
        scene_overrides: runtimeControlPresetSceneOverrides,
      }),
    });
    return response.ok;
  } catch {
    return false;
  }
}

function bindMidiLearnControls() {
  midiLearnButtons.forEach((button) => {
    button.addEventListener("click", async () => {
      const action = midiLearnActionForButton(button);
      if (!action) {
        renderMidiLearnStatus("No action selected");
        return;
      }

      const ready = await ensureMidiAccess();
      if (!ready) {
        renderMidiLearnStatus("Web MIDI unavailable");
        return;
      }

      pendingMidiLearnAction = action;
      renderMidiLearnStatus(`Move a MIDI control for ${midiLearnActionLabel(action)}`);
    });
  });
}

function midiLearnActionForButton(button) {
  const action = String(button?.dataset?.midiLearnAction || "");
  if (action === "current-scene") {
    return currentSceneName && currentSceneName !== "unknown"
      ? { type: "switch_scene", scene: currentSceneName }
      : null;
  }
  if (action === "blackout" || action === "freeze") {
    return { type: "live_control", control: action };
  }
  if (action.startsWith("visual:")) {
    return { type: "visual_setting", key: action.slice(7) };
  }
  return null;
}

async function ensureMidiAccess() {
  if (midiAccess) {
    return true;
  }

  const requestMIDIAccess = typeof navigator === "undefined" ? null : navigator.requestMIDIAccess;
  if (typeof requestMIDIAccess !== "function") {
    return false;
  }

  try {
    midiAccess = await requestMIDIAccess.call(navigator);
    bindMidiInputs(midiAccess.inputs);
    midiAccess.onstatechange = () => {
      bindMidiInputs(midiAccess.inputs);
      renderMidiLearnStatus();
    };
    return true;
  } catch {
    midiAccess = null;
    return false;
  }
}

function bindMidiInputs(inputs) {
  for (const input of inputs.values()) {
    input.onmidimessage = handleMidiMessage;
  }
}

function handleMidiMessage(event) {
  const signature = midiMessageSignature(event?.data);
  if (!signature) {
    return;
  }

  if (pendingMidiLearnAction && midiMessageActive(event?.data)) {
    midiLearnBindings = upsertMidiLearnBinding(midiLearnBindings, signature, pendingMidiLearnAction);
    midiLearnBindings = saveMidiLearnBindings(browserStorage(), midiLearnBindings);
    syncRuntimeControlPresetMidiBindings(midiLearnBindings);
    renderMidiLearnStatus(`Learned ${midiSignatureLabel(signature)} -> ${midiLearnActionLabel(pendingMidiLearnAction)}`);
    pendingMidiLearnAction = null;
    return;
  }

  const action = midiLearnBindings[signature];
  if (!action) {
    return;
  }

  applyMidiLearnAction(action, midiMessageUnitValue(event?.data), midiMessageActive(event?.data));
}

function applyMidiLearnAction(action, unitValue, active) {
  if (action.type === "visual_setting") {
    visualSettings[action.key] = visualSettingFromUnit(action.key, unitValue, visualSettings[action.key]);
    syncVisualControls();
    engine.setVisualSettings(visualSettings);
    syncRuntimeControlPresetSceneVisualSetting(action.key, visualSettings[action.key]);
    renderReactivityStatus("MIDI");
    return;
  }

  if (!active || unitValue <= 0) {
    return;
  }

  if (action.type === "switch_scene") {
    requestSceneSwitch(action.scene, action.effect);
    renderMidiLearnStatus(`MIDI: ${midiLearnActionLabel(action)}`);
    return;
  }

  if (action.type === "live_control") {
    if (Object.prototype.hasOwnProperty.call(action, "value")) {
      applyLiveControls({
        [action.control]: normalizeLiveControlPayload(action),
      });
    } else {
      applyLiveControls(toggleLiveControl(liveControls, action.control));
    }
    renderMidiLearnStatus(`MIDI: ${midiLearnActionLabel(action)}`);
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

async function writeClipboardText(value) {
  try {
    const clipboard = typeof navigator === "undefined" ? null : navigator.clipboard;
    if (!clipboard?.writeText) {
      return false;
    }
    await clipboard.writeText(value);
    return true;
  } catch {
    return false;
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

function renderMidiLearnStatus(prefix = null) {
  if (!midiLearnStatusElement) {
    return;
  }

  const bindingCount = Object.keys(midiLearnBindings).length;
  const accessState = midiAccess ? "ready" : "idle";
  midiLearnStatusElement.textContent = prefix || `MIDI Learn: ${accessState} | Bindings: ${bindingCount}`;
}

function bindShaderErrorOverlay() {
  window.addEventListener(SHADER_ERROR_EVENT, (event) => {
    renderShaderError(event.detail);
    reportShaderErrorToServer(event.detail);
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

function reportShaderErrorToServer(detail = {}) {
  const source = String(detail?.source || "shader").trim() || "shader";
  const layer = String(detail?.name || "layer").trim();
  const shader = String(detail?.shader || "unknown").trim();
  const event = String(detail?.event || "shader_failed").trim() || "shader_failed";
  const phase = String(detail?.phase || "").trim();
  const message = String(detail?.message || "").trim();
  const fullMessage = `${layer} (${shader}) ${phase ? `[${phase}] ` : ""}${message}`;
  client.send("client_runtime_error", {
    source,
    event,
    context: "shader compile failed",
    message: fullMessage,
    layer,
    shader,
    phase
  });
  updateRuntimeErrorStatus({
    source,
    event,
    context: "shader compile failed",
    message: fullMessage
  });
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
  renderHiraganaInspector(state.hiragana);
}

function renderHiraganaInspector(hiragana) {
  if (!inspectorHiraganaElement || !inspectorHiraganaDetailElement) {
    return;
  }

  if (!hiragana?.enabled) {
    inspectorHiraganaElement.hidden = true;
    inspectorHiraganaDetailElement.hidden = true;
    return;
  }

  const text = hiragana.text || "--";
  inspectorHiraganaElement.hidden = false;
  inspectorHiraganaElement.textContent = `Hiragana: ${text} ${formatMeterValue(hiragana.confidence, 2)}`;

  const vowel = hiragana.vowel
    ? `Vowel: ${hiragana.vowel} ${formatMeterValue(hiragana.vowelConfidence, 2)}`
    : "Vowel: --";
  const consonant = hiragana.consonant
    ? `Consonant: ${hiragana.consonant} ${formatMeterValue(hiragana.consonantConfidence, 2)}`
    : "Consonant: --";
  const candidates = hiragana.candidates.length
    ? `Candidates: ${hiragana.candidates.map((candidate) => `${candidate.text} ${formatMeterValue(candidate.confidence, 2)}`).join(" / ")}`
    : "Candidates: --";

  inspectorHiraganaDetailElement.hidden = false;
  inspectorHiraganaDetailElement.textContent = `${vowel} | ${consonant} | ${candidates}`;
}

function updateRuntimeErrorStatus(payload = {}) {
  if (!runtimeErrorStatusElement) {
    return;
  }

  const source = String(payload?.source || "runtime").trim();
  const event = String(payload?.event || "").trim();
  const context = String(payload?.context || "runtime error").trim();
  const message = String(payload?.message || "").trim();
  const frameId = payload?.frame_id;

  const detail = [context, event].filter(Boolean).join(" / ");
  const frameText = Number.isFinite(frameId) ? ` (frame ${frameId})` : "";
  const text = message
    ? `Runtime (${source}): ${detail}${frameText} | ${message}`
    : `Runtime (${source}): ${detail}${frameText}`;

  runtimeErrorStatusElement.textContent = text;
}

function setMeter(fill, valueElement, value, digits) {
  if (fill) {
    fill.style.setProperty("--meter-value", value.toFixed(4));
  }
  if (valueElement) {
    valueElement.textContent = formatMeterValue(value, digits);
  }
}

function frontendAssetVersionFromScripts({ scripts = [], baseUrl = "http://127.0.0.1/" } = {}) {
  for (const script of Array.from(scripts || [])) {
    const src = String(script?.src || script?.getAttribute?.("src") || "");
    if (!src.includes("/src/main.js")) {
      continue;
    }

    try {
      return new URL(src, baseUrl).searchParams.get("v") || "";
    } catch {
      return "";
    }
  }

  return "";
}

function shouldReloadForFrontendAssetVersion({ currentVersion = "", runtimeVersion = "" } = {}) {
  const current = String(currentVersion || "").trim();
  const runtime = String(runtimeVersion || "").trim();
  return Boolean(current && runtime && current !== runtime);
}

function canSendAudioTransport({ role = "control", playing = false, allowReadOnlyStart = false } = {}) {
  if (String(role || "control") === "control") {
    return true;
  }

  return !!allowReadOnlyStart && !!playing;
}

function resolveWebSocketRole({ projectorMode: isProjectorMode = false, search = "" } = {}) {
  const mode = new URLSearchParams(String(search || "")).get("mode");
  const normalizedMode = String(mode || "").toLowerCase();
  if (isProjectorMode || normalizedMode === "projector") {
    return "projector";
  }
  if (normalizedMode === "monitor") {
    return "monitor";
  }
  return "control";
}

function buildWebSocketUrl() {
  const protocol = window.location.protocol === "https:" ? "wss" : "ws";
  websocketRole = resolveWebSocketRole({
    projectorMode,
    search: window.location.search || ""
  });
  return `${protocol}://${window.location.host}/ws?role=${encodeURIComponent(websocketRole)}`;
}
