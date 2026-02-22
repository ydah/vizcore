import { Engine } from "./renderer/engine.js";
import { WebSocketClient } from "./websocket-client.js";

const canvas = document.querySelector("#vizcore-canvas");
const wsStatusElement = document.querySelector("#ws-status");
const sceneStatusElement = document.querySelector("#scene-status");
const transitionStatusElement = document.querySelector("#transition-status");
const frameStatusElement = document.querySelector("#frame-status");
const bpmStatusElement = document.querySelector("#bpm-status");
const beatStatusElement = document.querySelector("#beat-status");
const audioSourceStatusElement = document.querySelector("#audio-source-status");
const audioTrackStatusElement = document.querySelector("#audio-track-status");
const audioPlaybackStatusElement = document.querySelector("#audio-playback-status");
const sceneSwitcherElement = document.querySelector("#scene-switcher");
const audioToggleButton = document.querySelector("#audio-toggle");

const engine = new Engine(canvas);
engine.init();
engine.start();

let currentSceneName = "unknown";
let audioElement = null;
let frameCount = 0;
let lastConnectedAt = null;
let lastTransportSyncAt = 0;
let beatFlashUntil = 0;
let availableSceneNames = [];
let pendingSceneName = null;
let pendingSceneRequestedAt = 0;

const websocketUrl = buildWebSocketUrl();
const client = new WebSocketClient(websocketUrl, {
  onFrame: (frame) => {
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
    const amplitude = Number(frame?.audio?.amplitude || 0).toFixed(4);
    const bpm = Number(frame?.audio?.bpm || 0);
    const beat = !!frame?.audio?.beat;
    const beatCount = Math.max(0, Number(frame?.audio?.beat_count || 0) || 0);
    if (beat) {
      beatFlashUntil = performance.now() + 180;
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
    }
  },
  onStatus: (status) => {
    if (status === "connected") {
      lastConnectedAt = new Date();
      syncAudioTransportToServer({ force: true });
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
  const source = String(runtime?.audio_source || "unknown");
  audioSourceStatusElement.textContent = `Audio Source: ${source}`;
  updateAvailableScenes(runtime?.scene_names);

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

function updateAvailableScenes(sceneValues) {
  const names = normalizeSceneNames(sceneValues);
  if (!names.length) {
    return;
  }
  availableSceneNames = names;
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
    button.type = "button";
    button.textContent = sceneName;
    button.classList.toggle("is-active", sceneName === currentSceneName);
    button.onclick = () => {
      if (sceneName === currentSceneName) {
        return;
      }
      pendingSceneName = sceneName;
      pendingSceneRequestedAt = performance.now();
      currentSceneName = sceneName;
      sceneStatusElement.textContent = `Scene: ${sceneName}`;
      renderSceneButtons();
      client.send("switch_scene", { scene: sceneName });
    };
    return button;
  });
  sceneSwitcherElement.replaceChildren(...buttons);
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

function buildWebSocketUrl() {
  const protocol = window.location.protocol === "https:" ? "wss" : "ws";
  return `${protocol}://${window.location.host}/ws`;
}
