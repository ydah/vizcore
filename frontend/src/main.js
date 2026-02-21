import { Engine } from "./renderer/engine.js";
import { WebSocketClient } from "./websocket-client.js";

const canvas = document.querySelector("#vizcore-canvas");
const wsStatusElement = document.querySelector("#ws-status");
const frameStatusElement = document.querySelector("#frame-status");

const engine = new Engine(canvas);
engine.init();
engine.start();

const websocketUrl = buildWebSocketUrl();
const client = new WebSocketClient(websocketUrl, {
  onFrame: (frame) => {
    engine.setAudioFrame(frame);
    const amplitude = Number(frame?.audio?.amplitude || 0).toFixed(4);
    frameStatusElement.textContent = `Amplitude: ${amplitude}`;
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
