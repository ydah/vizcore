import { LayerManager } from "./layer-manager.js";
import { ShaderManager } from "./shader-manager.js";

export class Engine {
  constructor(canvas) {
    this.canvas = canvas;
    this.gl = null;
    this.shaderManager = null;
    this.layerManager = null;
    this.lastTime = performance.now();
    this.rotation = 0;
    this.currentRotationSpeed = 0.5;
    this.frame = {
      audio: {
        amplitude: 0,
        bands: { sub: 0, low: 0, mid: 0, high: 0 },
        fft: [],
        beat: false,
        beat_count: 0,
        bpm: 0
      },
      scene: {
        name: "basic",
        layers: []
      }
    };
  }

  init() {
    this.gl = this.canvas.getContext("webgl2");
    if (!this.gl) {
      throw new Error("WebGL2 is not supported in this browser");
    }

    this.shaderManager = new ShaderManager(this.gl);
    this.layerManager = new LayerManager(this.gl, this.shaderManager);

    this.gl.enable(this.gl.DEPTH_TEST);
    this.gl.enable(this.gl.BLEND);
    this.gl.blendFunc(this.gl.SRC_ALPHA, this.gl.ONE_MINUS_SRC_ALPHA);
    this.resize();
    window.addEventListener("resize", () => this.resize());
  }

  setAudioFrame(frame) {
    if (!frame || typeof frame !== "object") {
      return;
    }
    this.frame = frame;
  }

  start() {
    this.lastTime = performance.now();
    requestAnimationFrame((time) => this.render(time));
  }

  resize() {
    const width = Math.floor(this.canvas.clientWidth * window.devicePixelRatio);
    const height = Math.floor(this.canvas.clientHeight * window.devicePixelRatio);
    if (this.canvas.width === width && this.canvas.height === height) {
      return;
    }
    this.canvas.width = width;
    this.canvas.height = height;
    this.gl.viewport(0, 0, width, height);
  }

  render(time) {
    const deltaSeconds = (time - this.lastTime) / 1000;
    this.lastTime = time;

    const audio = this.frame?.audio || {};
    const layers = Array.isArray(this.frame?.scene?.layers) ? this.frame.scene.layers : [];
    const amplitude = clamp(Number(audio.amplitude || 0), 0, 1);
    const rotationSpeed = resolveRotationSpeed(layers, amplitude);
    this.currentRotationSpeed += (rotationSpeed - this.currentRotationSpeed) * 0.1;
    this.rotation += deltaSeconds * this.currentRotationSpeed;

    this.gl.clearColor(
      0.02 + amplitude * 0.05,
      0.03 + clamp(Number(audio?.bands?.high || 0), 0, 1) * 0.08,
      0.08 + amplitude * 0.06,
      1.0
    );
    this.gl.clear(this.gl.COLOR_BUFFER_BIT | this.gl.DEPTH_BUFFER_BIT);

    this.layerManager.renderScene({
      layers,
      audio,
      time: time / 1000,
      rotation: this.rotation,
      resolution: [this.canvas.width, this.canvas.height]
    });

    requestAnimationFrame((nextTime) => this.render(nextTime));
  }
}

const resolveRotationSpeed = (layers, amplitude) => {
  const firstLayer = layers[0];
  const fromLayer = Number(firstLayer?.params?.rotation_speed);
  if (Number.isFinite(fromLayer)) {
    return clamp(fromLayer, 0.05, 6.0);
  }
  return 0.35 + amplitude * 1.8;
};

const clamp = (value, min, max) => Math.min(Math.max(value, min), max);
