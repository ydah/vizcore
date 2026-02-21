const RECONNECT_INTERVAL_MS = 1000;

export class WebSocketClient {
  constructor(url, callbacks = {}) {
    this.url = url;
    this.onFrame = callbacks.onFrame || (() => {});
    this.onSceneChange = callbacks.onSceneChange || (() => {});
    this.onConfigUpdate = callbacks.onConfigUpdate || (() => {});
    this.onStatus = callbacks.onStatus || (() => {});
    this.socket = null;
    this.reconnectTimer = null;
  }

  connect() {
    this.disconnect();
    this.onStatus("connecting");

    this.socket = new WebSocket(this.url);
    this.socket.addEventListener("open", () => this.onStatus("connected"));
    this.socket.addEventListener("close", () => this.scheduleReconnect());
    this.socket.addEventListener("error", () => this.onStatus("error"));
    this.socket.addEventListener("message", (event) => this.handleMessage(event.data));
  }

  disconnect() {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    if (this.socket) {
      this.socket.close();
      this.socket = null;
    }
  }

  scheduleReconnect() {
    this.onStatus("reconnecting");
    this.reconnectTimer = setTimeout(() => this.connect(), RECONNECT_INTERVAL_MS);
  }

  handleMessage(rawMessage) {
    let message;
    try {
      message = JSON.parse(rawMessage);
    } catch {
      return;
    }

    if (!message || !message.type || !message.payload) {
      return;
    }

    if (message.type === "audio_frame") {
      this.onFrame(message.payload);
      return;
    }

    if (message.type === "scene_change") {
      this.onSceneChange(message.payload);
      return;
    }

    if (message.type === "config_update") {
      this.onConfigUpdate(message.payload);
    }
  }
}
