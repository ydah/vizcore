import test from "node:test";
import assert from "node:assert/strict";

import { PROTOCOL_VERSION, WebSocketClient } from "../src/websocket-client.js";

function installMockWebSocket() {
  const instances = [];

  class FakeWebSocket {
    constructor(url) {
      this.url = url;
      this.readyState = 0;
      this.listeners = {};
      instances.push(this);
    }

    addEventListener(type, handler) {
      this.listeners[type] = this.listeners[type] || [];
      this.listeners[type].push(handler);
    }

    close() {
      if (this.readyState !== 3) {
        this.readyState = 3;
      }
      this.dispatchEvent("close");
    }

    dispatchEvent(type, payload = {}) {
      (this.listeners[type] || []).forEach((handler) => {
        handler(payload);
      });
    }

    send() {
      return;
    }
  }

  return { FakeWebSocket, instances };
}

test("WebSocketClient routes parsed message payload by message type", () => {
  const calls = {
    frame: null,
    scene: null,
    config: null,
    latency: null,
    runtimeError: null
  };

  const client = new WebSocketClient("ws://127.0.0.1:4567/ws", {
    onFrame: (payload) => { calls.frame = payload; },
    onSceneChange: (payload) => { calls.scene = payload; },
    onConfigUpdate: (payload) => { calls.config = payload; },
    onLatencyProbe: (payload) => { calls.latency = payload; },
    onRuntimeError: (payload) => { calls.runtimeError = payload; }
  });

  client.handleMessage(JSON.stringify({ protocol: PROTOCOL_VERSION, type: "audio_frame", payload: { bpm: 120 } }));
  client.handleMessage(JSON.stringify({ type: "scene_change", payload: { from: "intro", to: "drop" } }));
  client.handleMessage(JSON.stringify({ type: "config_update", payload: { globals: { intensity: 0.7 } } }));
  client.handleMessage(JSON.stringify({ type: "latency_probe", payload: { rtt: 10 } }));
  client.handleMessage(JSON.stringify({ type: "runtime_error", payload: { context: "frame build failed", message: "boom" } }));

  assert.deepEqual(calls.frame, { bpm: 120 });
  assert.deepEqual(calls.scene, { from: "intro", to: "drop" });
  assert.deepEqual(calls.config, { globals: { intensity: 0.7 } });
  assert.deepEqual(calls.latency, { rtt: 10 });
  assert.deepEqual(calls.runtimeError, { context: "frame build failed", message: "boom" });
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

test("WebSocketClient reconnects after socket close", () => {
  const { FakeWebSocket, instances } = installMockWebSocket();
  const originalWebSocket = global.WebSocket;
  const originalSetTimeout = global.setTimeout;
  let reconnectTask = null;

  global.WebSocket = FakeWebSocket;
  global.setTimeout = (fn, ms) => {
    reconnectTask = fn;
    return 1;
  };

  try {
    const statuses = [];
    const client = new WebSocketClient("ws://127.0.0.1:4567/ws", {
      onStatus: (status) => statuses.push(status)
    });

    client.connect();
    const first = instances[0];
    first.readyState = 1;
    first.dispatchEvent("open");

    first.close();

    assert.equal(first.readyState, 3);
    assert.deepEqual(statuses, ["connecting", "connected", "reconnecting"]);
    assert.equal(typeof reconnectTask, "function");

    reconnectTask();
    assert.equal(statuses[3], "connecting");
    assert.equal(instances.length, 2);
  } finally {
    global.WebSocket = originalWebSocket;
    global.setTimeout = originalSetTimeout;
  }
});

test("WebSocketClient ignores close events from stale sockets", () => {
  const { FakeWebSocket, instances } = installMockWebSocket();
  const originalWebSocket = global.WebSocket;
  const originalSetTimeout = global.setTimeout;
  let reconnectCalls = 0;

  global.WebSocket = FakeWebSocket;
  global.setTimeout = () => {
    reconnectCalls += 1;
    return 1;
  };

  try {
    const statuses = [];
    const client = new WebSocketClient("ws://127.0.0.1:4567/ws", {
      onStatus: (status) => statuses.push(status)
    });

    client.connect();
    const first = instances[0];
    first.readyState = 1;
    first.dispatchEvent("open");

    // Force a stale serial to mimic an older socket event.
    client.connectionSerial += 1;
    first.dispatchEvent("close");

    assert.equal(reconnectCalls, 0);
    assert.deepEqual(statuses, ["connecting", "connected"]);
    assert.equal(instances.length, 1);
  } finally {
    global.WebSocket = originalWebSocket;
    global.setTimeout = originalSetTimeout;
  }
});
