import test from "node:test";
import assert from "node:assert/strict";

import { PROTOCOL_VERSION, WebSocketClient } from "../src/websocket-client.js";

test("WebSocketClient routes parsed message payload by message type", () => {
  const calls = {
    frame: null,
    scene: null,
    config: null,
    latency: null
  };

  const client = new WebSocketClient("ws://127.0.0.1:4567/ws", {
    onFrame: (payload) => { calls.frame = payload; },
    onSceneChange: (payload) => { calls.scene = payload; },
    onConfigUpdate: (payload) => { calls.config = payload; },
    onLatencyProbe: (payload) => { calls.latency = payload; }
  });

  client.handleMessage(JSON.stringify({ protocol: PROTOCOL_VERSION, type: "audio_frame", payload: { bpm: 120 } }));
  client.handleMessage(JSON.stringify({ type: "scene_change", payload: { from: "intro", to: "drop" } }));
  client.handleMessage(JSON.stringify({ type: "config_update", payload: { globals: { intensity: 0.7 } } }));
  client.handleMessage(JSON.stringify({ type: "latency_probe", payload: { rtt: 10 } }));

  assert.deepEqual(calls.frame, { bpm: 120 });
  assert.deepEqual(calls.scene, { from: "intro", to: "drop" });
  assert.deepEqual(calls.config, { globals: { intensity: 0.7 } });
  assert.deepEqual(calls.latency, { rtt: 10 });
});

test("WebSocketClient ignores malformed or unsupported messages", () => {
  let called = false;
  const client = new WebSocketClient("ws://127.0.0.1:4567/ws", {
    onFrame: () => { called = true; }
  });

  client.handleMessage("not-json");
  client.handleMessage(JSON.stringify({}));
  client.handleMessage(JSON.stringify({ type: "unknown", payload: { v: 1 } }));
  client.handleMessage(JSON.stringify({ protocol: "vizcore.frame.v99", type: "audio_frame", payload: { v: 1 } }));

  assert.equal(called, false);
});

test("WebSocketClient sends protocol version in outgoing messages", () => {
  const sent = [];
  const client = new WebSocketClient("ws://127.0.0.1:4567/ws");
  client.socket = {
    readyState: 1,
    send: (message) => { sent.push(message); }
  };

  assert.equal(client.send("switch_scene", { scene: "drop" }), true);
  assert.deepEqual(JSON.parse(sent[0]), {
    protocol: PROTOCOL_VERSION,
    type: "switch_scene",
    payload: { scene: "drop" }
  });
});
