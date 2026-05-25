import { LayerManager } from "./layer-manager.js";
import { ShaderManager } from "./shader-manager.js";
import { applyShaderParamOverrides } from "../shader-param-controls.js";
import { applyShapeEditorOverrides } from "../shape-editor-controls.js";

export class Engine {
  constructor(canvas) {
    this.canvas = canvas;
    this.gl = null;
    this.shaderManager = null;
    this.layerManager = null;
    this.lastTime = performance.now();
    this.rotation = 0;
    this.currentRotationSpeed = 0.5;
    this.mediaElement = null;
    this.lastMediaTime = null;
    this.visualSettings = {
      visualGain: 1,
      bassBoost: 1,
      smoothing: 0,
      beatHoldMs: 180,
      wobbleAmount: 1,
    };
    this.visualAudioState = null;
    this.liveControls = {
      blackout: false,
      freeze: false,
    };
    this.runtimeGlobals = {};
    this.shaderParamOverrides = {};
    this.shapeEditorOverrides = {};
    this.beatHoldUntil = 0;
    this.frame = {
      audio: {
        amplitude: 0,
        bands: { sub: 0, low: 0, mid: 0, high: 0 },
        fft: [],
        onset: 0,
        onsets: { sub: 0, low: 0, mid: 0, high: 0 },
        drums: { kick: 0, snare: 0, hihat: 0 },
        beat: false,
        beat_pulse: 0,
        beat_count: 0,
        beat_phase: 0,
        beat_2: false,
        beat_4: false,
        beat_8: false,
        beat_triplet: false,
        bar_phase: 0,
        bar_count: 0,
        phrase_count: 0,
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

  setMediaElement(mediaElement) {
    this.mediaElement = mediaElement || null;
    this.lastMediaTime = null;
  }

  setVisualSettings(settings = {}) {
    this.visualSettings = {
      ...this.visualSettings,
      ...settings,
    };
  }

  setLiveControls(controls = {}) {
    this.liveControls = {
      blackout: !!controls?.blackout,
      freeze: !!controls?.freeze,
    };
  }

  setRuntimeGlobals(globals = {}) {
    this.runtimeGlobals = globals && typeof globals === "object" ? { ...globals } : {};
  }

  setShaderParamOverrides(overrides = {}) {
    this.shaderParamOverrides = overrides && typeof overrides === "object" ? overrides : {};
  }

  setShapeEditorOverrides(overrides = {}) {
    this.shapeEditorOverrides = overrides && typeof overrides === "object" ? overrides : {};
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
    let deltaSeconds = (time - this.lastTime) / 1000;
    this.lastTime = time;
    let visualTimeSeconds = time / 1000;

    if (this.mediaElement) {
      const currentMediaTime = Number(this.mediaElement.currentTime || 0);
      visualTimeSeconds = currentMediaTime;

      if (this.mediaElement.paused) {
        deltaSeconds = 0;
      } else if (this.lastMediaTime === null) {
        deltaSeconds = 0;
      } else {
        deltaSeconds = Math.max(0, currentMediaTime - this.lastMediaTime);
      }

      this.lastMediaTime = currentMediaTime;
    } else {
      this.lastMediaTime = null;
    }

    if (this.liveControls.blackout) {
      this.gl.clearColor(0, 0, 0, 1);
      this.gl.clear(this.gl.COLOR_BUFFER_BIT | this.gl.DEPTH_BUFFER_BIT);
      requestAnimationFrame((nextTime) => this.render(nextTime));
      return;
    }

    if (this.liveControls.freeze) {
      requestAnimationFrame((nextTime) => this.render(nextTime));
      return;
    }

    const rawAudio = this.frame?.audio || {};
    const audio = applyVisualSettings({
      audio: rawAudio,
      settings: this.visualSettings,
      previous: this.visualAudioState,
    });
    this.visualAudioState = audio;
    const rawLayers = Array.isArray(this.frame?.scene?.layers) ? this.frame.scene.layers : [];
    const layers = applyShapeEditorOverrides(
      applyShaderParamOverrides(rawLayers, this.shaderParamOverrides),
      this.shapeEditorOverrides
    );
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
      time: visualTimeSeconds,
      rotation: this.rotation,
      resolution: [this.canvas.width, this.canvas.height],
      globals: this.runtimeGlobals,
      visualSettings: this.visualSettings
    });

    requestAnimationFrame((nextTime) => this.render(nextTime));
  }
}

const resolveRotationSpeed = (layers, amplitude) => {
  const layerWithSpeed = Array.isArray(layers)
    ? layers.find((layer) => Number.isFinite(Number(layer?.params?.rotation_speed)))
    : null;
  const fromLayer = Number(layerWithSpeed?.params?.rotation_speed);
  if (Number.isFinite(fromLayer)) {
    return clamp(fromLayer, 0.1, 8.0);
  }
  return 0.7 + amplitude * 2.4;
};

export const applyVisualSettings = ({ audio, settings, previous }) => {
  const visualGain = clamp(Number(settings?.visualGain ?? 1), 0.1, 16);
  const bassBoost = clamp(Number(settings?.bassBoost ?? 1), 0, 8);
  const smoothing = clamp(Number(settings?.smoothing ?? 0), 0, 0.95);
  const wobbleAmount = clamp(Number(settings?.wobbleAmount ?? 1), 0, 8);

  const rawBands = audio?.bands || {};
  const rawOnsets = audio?.onsets || {};
  const rawDrums = audio?.drums || {};
  const next = {
    ...audio,
    amplitude: clamp(Number(audio?.amplitude || 0) * visualGain, 0, 1),
    bands: {
      ...rawBands,
      sub: clamp(Number(rawBands.sub || 0) * bassBoost, 0, 1),
      low: clamp(Number(rawBands.low || 0) * bassBoost, 0, 1),
      mid: clamp(Number(rawBands.mid || 0) * visualGain, 0, 1),
      high: clamp(Number(rawBands.high || 0) * visualGain, 0, 1),
    },
    onset: clamp(Number(audio?.onset || 0) * visualGain, 0, 1),
    onsets: {
      ...rawOnsets,
      sub: clamp(Number(rawOnsets.sub || 0) * bassBoost, 0, 1),
      low: clamp(Number(rawOnsets.low || 0) * bassBoost, 0, 1),
      mid: clamp(Number(rawOnsets.mid || 0) * visualGain, 0, 1),
      high: clamp(Number(rawOnsets.high || 0) * visualGain, 0, 1),
    },
    drums: {
      ...rawDrums,
      kick: clamp(Number(rawDrums.kick || 0) * bassBoost, 0, 1),
      snare: clamp(Number(rawDrums.snare || 0) * visualGain, 0, 1),
      hihat: clamp(Number(rawDrums.hihat || 0) * visualGain, 0, 1),
    },
    visual_gain: visualGain,
    bass_boost: bassBoost,
    wobble_amount: wobbleAmount,
  };

  if (isSilentAudio(next)) {
    return next;
  }

  if (!previous || smoothing <= 0) {
    return next;
  }

  const previousBands = previous.bands || {};
  const alpha = 1 - smoothing;
  return {
    ...next,
    amplitude: previous.amplitude + (next.amplitude - previous.amplitude) * alpha,
    bands: {
      ...next.bands,
      sub: Number(previousBands.sub || 0) + (next.bands.sub - Number(previousBands.sub || 0)) * alpha,
      low: Number(previousBands.low || 0) + (next.bands.low - Number(previousBands.low || 0)) * alpha,
      mid: Number(previousBands.mid || 0) + (next.bands.mid - Number(previousBands.mid || 0)) * alpha,
      high: Number(previousBands.high || 0) + (next.bands.high - Number(previousBands.high || 0)) * alpha,
    },
  };
};

const isSilentAudio = (audio) => {
  const bands = audio?.bands || {};
  const onsets = audio?.onsets || {};
  const drums = audio?.drums || {};
  return Number(audio?.amplitude || 0) <= 0
    && Number(audio?.onset || 0) <= 0
    && Number(audio?.beat_pulse || 0) <= 0
    && !audio?.beat
    && Number(bands.sub || 0) <= 0
    && Number(bands.low || 0) <= 0
    && Number(bands.mid || 0) <= 0
    && Number(bands.high || 0) <= 0
    && Number(onsets.sub || 0) <= 0
    && Number(onsets.low || 0) <= 0
    && Number(onsets.mid || 0) <= 0
    && Number(onsets.high || 0) <= 0
    && Number(drums.kick || 0) <= 0
    && Number(drums.snare || 0) <= 0
    && Number(drums.hihat || 0) <= 0;
};

const clamp = (value, min, max) => Math.min(Math.max(value, min), max);
