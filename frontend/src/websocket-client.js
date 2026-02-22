const RECONNECT_INTERVAL_MS = 1000;
const READY_STATE_CONNECTING = 0;
const READY_STATE_OPEN = 1;

export class WebSocketClient {
  constructor(url, callbacks = {}) {
    this.url = url;
    this.onFrame = callbacks.onFrame || (() => {});
    this.onSceneChange = callbacks.onSceneChange || (() => {});
    this.onConfigUpdate = callbacks.onConfigUpdate || (() => {});
    this.onStatus = callbacks.onStatus || (() => {});
    this.socket = null;
    this.reconnectTimer = null;
    this.shouldReconnect = true;
    this.connectionSerial = 0;
  }

  connect() {
    if (this.socket && (this.socket.readyState === READY_STATE_CONNECTING || this.socket.readyState === READY_STATE_OPEN)) {
      return;
    }
    this.shouldReconnect = true;
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    this.onStatus("connecting");

    const serial = this.connectionSerial + 1;
    this.connectionSerial = serial;
    const socket = new WebSocket(this.url);
    this.socket = socket;
    socket.addEventListener("open", () => {
      if (!this.isActiveSocket(socket, serial)) {
        return;
      }
      this.onStatus("connected");
    });
    socket.addEventListener("close", () => {
      if (!this.isActiveSocket(socket, serial)) {
        return;
      }
      this.socket = null;
      if (!this.shouldReconnect) {
        this.onStatus("disconnected");
        return;
      }
      this.scheduleReconnect();
    });
    socket.addEventListener("error", () => {
      if (!this.isActiveSocket(socket, serial)) {
        return;
      }
      this.onStatus("error");
    });
    socket.addEventListener("message", (event) => {
      if (!this.isActiveSocket(socket, serial)) {
        return;
      }
      this.handleMessage(event.data);
    });
  }

  disconnect() {
    this.shouldReconnect = false;
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    const socket = this.socket;
    this.socket = null;
    if (socket && (socket.readyState === READY_STATE_CONNECTING || socket.readyState === READY_STATE_OPEN)) {
      socket.close();
    }
  }

  scheduleReconnect() {
    if (!this.shouldReconnect || this.reconnectTimer) {
      return;
    }
    this.onStatus("reconnecting");
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      this.connect();
    }, RECONNECT_INTERVAL_MS);
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

  isActiveSocket(socket, serial) {
    return this.socket === socket && this.connectionSerial === serial;
  }
}
