import { Engine } from "./renderer/engine.js";
import { WebSocketClient } from "./websocket-client.js";

const canvas = document.querySelector("#vizcore-canvas");
const wsStatusElement = document.querySelector("#ws-status");
const sceneStatusElement = document.querySelector("#scene-status");
const transitionStatusElement = document.querySelector("#transition-status");
const frameStatusElement = document.querySelector("#frame-status");

const engine = new Engine(canvas);
engine.init();
engine.start();

let currentSceneName = "unknown";

const websocketUrl = buildWebSocketUrl();
const client = new WebSocketClient(websocketUrl, {
  onFrame: (frame) => {
    engine.setAudioFrame(frame);
    const sceneName = String(frame?.scene?.name || currentSceneName);
    currentSceneName = sceneName;
    const amplitude = Number(frame?.audio?.amplitude || 0).toFixed(4);
    sceneStatusElement.textContent = `Scene: ${sceneName}`;
    frameStatusElement.textContent = `Amplitude: ${amplitude}`;
  },
  onSceneChange: (payload) => {
    const from = String(payload?.from || "unknown");
    const to = String(payload?.to || "unknown");
    currentSceneName = to;
    sceneStatusElement.textContent = `Scene: ${to}`;
    transitionStatusElement.textContent = `Transition: ${from} -> ${to}`;
  },
  onConfigUpdate: (payload) => {
    const sceneName = payload?.scene?.name;
    if (sceneName) {
      currentSceneName = String(sceneName);
      sceneStatusElement.textContent = `Scene: ${currentSceneName}`;
    }
  },
  onStatus: (status) => {
    wsStatusElement.textContent = `WebSocket: ${status}`;
  }
});

client.connect();

function buildWebSocketUrl() {
  const protocol = window.location.protocol === "https:" ? "wss" : "ws";
  return `${protocol}://${window.location.host}/ws`;
}
