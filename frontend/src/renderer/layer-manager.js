import { getBuiltinShader } from "../shaders/builtins.js";
import { getPostEffectShader } from "../shaders/post-effects.js";
import { SHADER_ERROR_EVENT, buildShaderErrorDetail } from "../shader-error-overlay.js";
import {
  buildPresetMeshLines,
  buildRadialBlobLines,
  buildShapeLines,
  buildWaveformLines,
  buildWireframeLines,
  estimateDeformFromSpectrum
} from "../visuals/geometry.js";
import { ImageRenderer } from "../visuals/image-renderer.js";
import { ParticleSystem } from "../visuals/particle-system.js";
import {
  normalizePluginLineOutput,
  normalizePluginShaderOutput,
  resolveLayerRenderer,
  resolveShaderRenderer
} from "../plugin-runtime.js";
import { SpectrogramRenderer } from "../visuals/spectrogram-renderer.js";
import { ShapeRenderer } from "../visuals/shape-renderer.js";
import { TextRenderer } from "../visuals/text-renderer.js";
import { getVJEffectShader } from "../visuals/vj-effects.js";
import { FULLSCREEN_VERTEX_SHADER } from "./shader-manager.js";

const GEOMETRY_VERTEX_SHADER = `#version 300 es
in vec2 a_position;
void main() {
  gl_Position = vec4(a_position, 0.0, 1.0);
}
`;

const GEOMETRY_FRAGMENT_SHADER = `#version 300 es
precision mediump float;
uniform vec3 u_color;
out vec4 outColor;
void main() {
  outColor = vec4(u_color, 1.0);
}
`;

const COMPOSITE_FRAGMENT_SHADER = `#version 300 es
precision mediump float;
in vec2 v_uv;
uniform sampler2D u_texture;
uniform float u_opacity;
out vec4 outColor;
void main() {
  vec4 color = texture(u_texture, v_uv);
  outColor = vec4(color.rgb, color.a * u_opacity);
}
`;

const FULLSCREEN_VERTICES = new Float32Array([
  -1.0, -1.0,
  1.0, -1.0,
  -1.0, 1.0,
  1.0, 1.0
]);
const MAX_LAYER_TARGET_PIXELS = 4_194_304;
const MIN_LAYER_RESOLUTION_SCALE = 0.1;
const SHADER_CACHE_VERSION = "v2";

export const coerceUniformNumber = (value) => {
  if (typeof value === "boolean") {
    return value ? 1 : 0;
  }

  if (typeof value !== "number" && typeof value !== "string") {
    return null;
  }

  if (typeof value === "string" && value.trim() === "") {
    return null;
  }

  const numeric = Number(value);
  if (!Number.isFinite(numeric)) {
    return null;
  }

  return numeric;
};

export const shaderParamUniformNames = (rawKey) => {
  const safeKey = String(rawKey || "").replace(/[^a-zA-Z0-9_]/g, "_");
  if (!safeKey) {
    return [];
  }

  const names = [`u_param_${safeKey}`];

  if (safeKey.startsWith("param_")) {
    names.push(`u_${safeKey}`);
  }

  return [...new Set(names)];
};

export const shaderGlobalUniformNames = (rawKey) => {
  const safeKey = String(rawKey || "").replace(/[^a-zA-Z0-9_]/g, "_");
  if (!safeKey) {
    return [];
  }

  const names = safeKey.startsWith("global_")
    ? [`u_${safeKey}`, `u_global_${safeKey.slice(7)}`]
    : [`u_global_${safeKey}`];

  return [...new Set(names)];
};

export const normalizeSpectrum = (value, size = 32) => {
  const input = Array.isArray(value) || ArrayBuffer.isView(value) ? Array.from(value) : [];
  const output = new Float32Array(size);

  for (let index = 0; index < size; index += 1) {
    const numeric = Number(input[index] || 0);
    output[index] = Number.isFinite(numeric) ? Math.min(Math.max(numeric, 0), 1) : 0;
  }

  return output;
};

export const normalizeBlendMode = (mode) => {
  const value = String(mode || "alpha").toLowerCase();
  if (value === "normal" || value === "alpha") return "alpha";
  if (value === "add" || value === "additive") return "add";
  if (value === "multiply") return "multiply";
  if (value === "screen") return "screen";
  if (value === "difference") return "difference";
  return "alpha";
};

export const resolveLayerResolutionScale = (params = {}, visualSettings = {}) => {
  const rawValue = params?.resolution_scale
    ?? params?.resolutionScale
    ?? params?.target_resolution_scale
    ?? params?.targetResolutionScale
    ?? 1;
  const layerScale = clamp(Number(rawValue), MIN_LAYER_RESOLUTION_SCALE, 1);
  const safeScale = visualSettings?.safeModeActive
    ? clamp(Number(visualSettings?.safeModeScale || 0.75), MIN_LAYER_RESOLUTION_SCALE, 1)
    : 1;
  const scale = layerScale * safeScale;
  return Number.isFinite(scale) ? clamp(scale, MIN_LAYER_RESOLUTION_SCALE, 1) : 1;
};

export const shaderCacheKeyForLayer = (layer, shaderName, fragmentShader) => {
  const customSource = typeof layer?.glsl_source === "string" ? layer.glsl_source : null;
  const schemaSignature = stableHash(layer?.param_schema || layer?.params?.param_schema || []);
  if (customSource) {
    return [
      "custom",
      SHADER_CACHE_VERSION,
      String(layer?.glsl || shaderName),
      stableHash(fragmentShader),
      schemaSignature,
    ].join(":");
  }

  return ["builtin", SHADER_CACHE_VERSION, String(shaderName), schemaSignature].join(":");
};

export const normalizePaletteColors = (value) => {
  const input = Array.isArray(value) ? value : [];
  return input
    .map((entry) => String(entry || "").trim())
    .filter((entry) => entry.length > 0);
};

export const parseHexColor = (value) => {
  const raw = String(value || "").trim();
  const match = raw.match(/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/);
  if (!match) {
    return null;
  }

  const hex = match[1].length === 3
    ? match[1].split("").map((char) => `${char}${char}`).join("")
    : match[1];

  return [0, 2, 4].map((offset) => parseInt(hex.slice(offset, offset + 2), 16) / 255);
};

const normalizePalettePosition = (value, paletteLength) => {
  const numeric = Number(value);
  if (!Number.isFinite(numeric) || !paletteLength) {
    return 0;
  }

  const remainder = numeric % paletteLength;
  return remainder >= 0 ? remainder : remainder + paletteLength;
};

const interpolatePaletteColor = (left, right, blend) => {
  const ratio = clamp(blend, 0, 1);
  const rgb = left.map((value, index) => {
    const next = right[index];
    return Math.round(clamp(value + (next - value) * ratio, 0, 1) * 255);
  });
  return `#${rgb.map((value) => value.toString(16).padStart(2, "0")).join("")}`;
};

const normalizeGradientStops = (stops, count) => {
  if (!Array.isArray(stops)) {
    return null;
  }

  const values = stops.map((value) => Number(value)).filter((value) => Number.isFinite(value));
  if (values.length !== count) {
    return null;
  }

  return values.map((value) => clamp(value, 0, 1)).sort((left, right) => left - right);
};

const resolveGradientColor = (value, paletteIndex = 0) => {
  const gradient = value?.gradient || value;
  if (!gradient || typeof gradient !== "object") {
    return null;
  }

  const colors = normalizePaletteColors(gradient?.colors || gradient?.palette);
  if (colors.length === 0) {
    return null;
  }

  if (colors.length === 1) {
    return colors[0];
  }

  const stops = normalizeGradientStops(gradient?.stops || gradient?.stopsPercent, colors.length);
  const basePosition = Number.isFinite(Number(gradient?.position)) ? Number(gradient.position) : Number(paletteIndex);

  let position;
  if (stops) {
    position = Number.isFinite(basePosition) ? clamp(basePosition, 0, 1) : 0;
  } else {
    const fractional = Number.isFinite(basePosition) ? basePosition - Math.floor(basePosition) : 0;
    position = clamp(fractional, 0, 1);
  }

  if (position <= 0) {
    return colors[0];
  }
  if (position >= 1) {
    return colors[colors.length - 1];
  }

  if (!stops) {
    const segmentLength = 1 / (colors.length - 1);
    const segment = Math.min(Math.floor(position / segmentLength), colors.length - 2);
    const blendBase = segment * segmentLength;
    const blend = (position - blendBase) / segmentLength;
    const left = parseHexColor(colors[segment]);
    const right = parseHexColor(colors[segment + 1]);
    if (!left || !right) {
      return colors[segment];
    }

    return interpolatePaletteColor(left, right, blend);
  }

  const segment = Array.from({ length: colors.length - 1 }, (_, index) => index)
    .find((index) => position <= stops[index + 1]);

  if (segment === undefined) {
    return colors[colors.length - 1];
  }

  if (segment <= 0 && position <= stops[0]) {
    return colors[0];
  }

  const start = stops[segment];
  const stop = stops[segment + 1];
  const width = Math.max(stop - start, Number.EPSILON);
  const blend = clamp((position - start) / width, 0, 1);
  const left = parseHexColor(colors[segment]);
  const right = parseHexColor(colors[segment + 1]);
  if (!left || !right) {
    return colors[segment];
  }

  return interpolatePaletteColor(left, right, blend);
};

export const resolveLayerCssColor = (params = {}, fallback = "#e5f3ff", paletteIndex = 0) => {
  const explicitColor = params?.color;
  const explicitHex = typeof explicitColor === "string" ? String(explicitColor || "").trim() : "";
  if (explicitHex) {
    return explicitHex;
  }

  const gradientColor = resolveGradientColor(explicitColor, paletteIndex);
  if (gradientColor) {
    return gradientColor;
  }

  const palette = normalizePaletteColors(params?.palette);
  if (palette.length === 0) {
    return fallback;
  }

  if (palette.length === 1) {
    return palette[0];
  }

  const position = normalizePalettePosition(paletteIndex, palette.length);
  const lowerIndex = Math.floor(position);
  const blend = position - lowerIndex;
  if (blend <= 0 || !Number.isFinite(blend)) {
    return palette[lowerIndex];
  }

  const leftColor = parseHexColor(palette[lowerIndex]);
  const rightColor = parseHexColor(palette[(lowerIndex + 1) % palette.length]);
  if (!leftColor || !rightColor) {
    return palette[lowerIndex];
  }

  return interpolatePaletteColor(leftColor, rightColor, blend);
};

export const resolveLayerRgbColor = (params = {}, fallback = null, paletteIndex = 0) => {
  const parsed = parseHexColor(resolveLayerCssColor(params, "", paletteIndex));
  return parsed || fallback;
};

export class LayerManager {
  constructor(gl, shaderManager) {
    this.gl = gl;
    this.shaderManager = shaderManager;

    this.fullscreenBuffer = this.gl.createBuffer();
    this.geometryBuffer = this.gl.createBuffer();

    this.geometryProgram = this.shaderManager.getProgram(
      "geometry-wireframe",
      GEOMETRY_VERTEX_SHADER,
      GEOMETRY_FRAGMENT_SHADER
    );
    this.geometryPositionLocation = this.gl.getAttribLocation(this.geometryProgram, "a_position");
    this.geometryColorLocation = this.gl.getUniformLocation(this.geometryProgram, "u_color");

    this.compositeProgram = this.shaderManager.getProgram(
      "layer-composite",
      FULLSCREEN_VERTEX_SHADER,
      COMPOSITE_FRAGMENT_SHADER
    );
    this.compositePositionLocation = this.gl.getAttribLocation(this.compositeProgram, "a_position");
    this.compositeTextureLocation = this.gl.getUniformLocation(this.compositeProgram, "u_texture");
    this.compositeOpacityLocation = this.gl.getUniformLocation(this.compositeProgram, "u_opacity");

    this.layerFramebuffer = null;
    this.layerTexture = null;
    this.layerTextureSecondary = null;
    this.layerDepthRenderbuffer = null;
    this.layerTargetWidth = 0;
    this.layerTargetHeight = 0;
    this.layerTargetAvailable = true;
    this.layerErrorKeys = new Set();
    this.lastGoodShaderPrograms = new Map();
    this.activeShaderLayerKeys = null;

    this.particleSystem = new ParticleSystem(this.gl, this.shaderManager);
    this.textRenderer = new TextRenderer(this.gl, this.shaderManager);
    this.imageRenderer = new ImageRenderer(this.gl, this.shaderManager);
    this.shapeRenderer = new ShapeRenderer(this.gl, this.shaderManager);
    this.spectrogramRenderer = new SpectrogramRenderer(this.gl, this.shaderManager);

    this.gl.bindBuffer(this.gl.ARRAY_BUFFER, this.fullscreenBuffer);
    this.gl.bufferData(this.gl.ARRAY_BUFFER, FULLSCREEN_VERTICES, this.gl.STATIC_DRAW);
  }

  renderScene({ layers, audio, time, rotation, resolution, globals, visualSettings }) {
    const layerList = Array.isArray(layers) && layers.length > 0 ? layers : [defaultLayer(audio)];
    const width = Math.max(1, Math.floor(Number(resolution?.[0] || 1)));
    const height = Math.max(1, Math.floor(Number(resolution?.[1] || 1)));
    const shaderLayerKeys = new Set();
    this.activeShaderLayerKeys = shaderLayerKeys;

    layerList.forEach((layer, index) => {
      try {
        this.ensureLayerTarget(width, height, layer, visualSettings);
        if (!this.layerTargetAvailable || !this.layerFramebuffer || !this.layerTexture) {
          const blend = String(layer?.params?.blend || "alpha").toLowerCase();
          this.setBlendMode(blend);
          this.renderLayer(layer, audio, time, rotation, [width, height], globals, visualSettings, index);
          return;
        }

        this.gl.bindFramebuffer(this.gl.FRAMEBUFFER, this.layerFramebuffer);
        this.attachPrimaryLayerTarget();
        this.gl.viewport(0, 0, this.layerTargetWidth, this.layerTargetHeight);
        this.gl.clearColor(0.0, 0.0, 0.0, 0.0);
        this.gl.clear(this.gl.COLOR_BUFFER_BIT | this.gl.DEPTH_BUFFER_BIT);

        this.renderLayer(
          layer,
          audio,
          time,
          rotation,
          [this.layerTargetWidth, this.layerTargetHeight],
          globals,
          visualSettings,
          index,
          index
        );

        this.gl.bindFramebuffer(this.gl.FRAMEBUFFER, null);
        this.gl.viewport(0, 0, width, height);
        this.compositeLayer(layer, { audio, time, resolution: [width, height] });
      } catch (error) {
        this.gl.bindFramebuffer(this.gl.FRAMEBUFFER, null);
        this.gl.viewport(0, 0, width, height);
        this.reportLayerError(layer, error, "layer-pass");
      }
    });
    this.pruneLastGoodShaderPrograms(shaderLayerKeys);
    this.activeShaderLayerKeys = null;
    this.setBlendMode("alpha");
  }

  renderLayer(
    layer,
    audio,
    time,
    rotation,
    resolution,
    globals,
    visualSettings,
    paletteIndex = 0,
    layerIndex = null
  ) {
    if (isParticleLayer(layer)) {
      this.renderParticleLayer(layer, audio, time, paletteIndex);
      return;
    }
    if (isTextLayer(layer)) {
      this.renderTextLayer(layer, audio, time, paletteIndex);
      return;
    }
    if (isImageLayer(layer) || isVideoLayer(layer)) {
      this.renderImageLayer(layer, audio);
      return;
    }
    if (isWaveformLayer(layer)) {
      this.renderWaveformLayer(layer, audio, time, paletteIndex);
      return;
    }
    if (isSpectrogramLayer(layer)) {
      this.renderSpectrogramLayer(layer, audio);
      return;
    }
    if (isShapeLayer(layer)) {
      this.renderShapeLayer(layer, audio, time, resolution, paletteIndex);
      return;
    }
    if (isShaderLayer(layer)) {
      this.renderShaderLayer(layer, audio, time, resolution, globals, visualSettings, paletteIndex, layerIndex);
      return;
    }
    if (this.renderPluginLayer(
      layer,
      audio,
      time,
      rotation,
      resolution,
      globals,
      visualSettings,
      paletteIndex,
      layerIndex
    )) {
      return;
    }
    this.renderGeometryLayer(layer, audio, rotation, time, paletteIndex);
  }

  renderPluginLayer(
    layer,
    audio,
    time,
    rotation,
    resolution,
    globals,
    visualSettings,
    paletteIndex = 0,
    layerIndex = null
  ) {
    const context = {
      layer,
      audio,
      time,
      rotation,
      resolution,
      globals,
      visualSettings,
      paletteIndex
    };

    const renderer = resolveLayerRenderer(layer?.type);
    if (renderer && this.renderPluginOutput(layer, renderer(context), audio, time, resolution, globals, visualSettings, paletteIndex, layerIndex)) {
      return true;
    }

    const shaderRenderer = resolveShaderRenderer(layer?.type);
    if (shaderRenderer && this.renderPluginOutput(layer, shaderRenderer(context), audio, time, resolution, globals, visualSettings, paletteIndex, layerIndex)) {
      return true;
    }

    return false;
  }

  renderPluginOutput(
    layer,
    output,
    audio,
    time,
    resolution,
    globals,
    visualSettings,
    paletteIndex = 0,
    layerIndex = null
  ) {
    const lines = normalizePluginLineOutput(output);
    if (lines) {
      const fallbackColor = resolveLayerRgbColor(layer?.params || {}, [0.82, 0.92, 1.0], paletteIndex);
      this.renderLinePoints(lines.points, lines.color || fallbackColor);
      return true;
    }

    const shader = normalizePluginShaderOutput(output);
    if (!shader) {
      return false;
    }

    this.renderShaderLayer({
      ...layer,
      shader: layer?.shader || "default",
      glsl: `plugin:${String(layer?.type || "layer")}:${shader.cacheKey}`,
      glsl_source: shader.fragmentShader
    }, audio, time, resolution, globals, visualSettings, paletteIndex, layerIndex);
    return true;
  }

  renderShaderLayer(
    layer,
    audio,
    time,
    resolution,
    globals,
    visualSettings,
    paletteIndex = 0,
    layerIndex = null
  ) {
    const shaderName = String(layer?.shader || "gradient_pulse");
    const customSource = typeof layer?.glsl_source === "string" ? layer.glsl_source : null;
    const fragmentShader = customSource || getBuiltinShader(shaderName);
    const cacheKey = shaderCacheKeyForLayer(layer, shaderName, fragmentShader);
    const layerCacheKey = this.shaderLayerCacheKey(layer, layerIndex, customSource);
    if (layerCacheKey) {
      this.activeShaderLayerKeys?.add(layerCacheKey);
    }

    let program = null;
    try {
      program = this.shaderManager.getProgram(cacheKey, FULLSCREEN_VERTEX_SHADER, fragmentShader);
      if (layerCacheKey) {
        this.lastGoodShaderPrograms.set(layerCacheKey, {
          program,
          cacheKey,
          createdAt: Date.now()
        });
      }
    } catch (error) {
      if (customSource) {
        this.reportShaderError(layer, error, "custom-shader");
        console.warn("Failed to compile custom GLSL, falling back to builtin shader", error);
        const cached = layerCacheKey ? this.lastGoodShaderPrograms.get(layerCacheKey) : null;
        if (cached && cached.program) {
          program = cached.program;
        }

        try {
          if (!program) {
            program = this.shaderManager.getProgram(
              shaderCacheKeyForLayer(
                { ...layer, glsl_source: null },
                shaderName,
                getBuiltinShader(shaderName)
              ),
              FULLSCREEN_VERTEX_SHADER,
              getBuiltinShader(shaderName)
            );
          }
        } catch (builtinError) {
          this.reportShaderError(layer, builtinError, "builtin-shader-fallback");
          this.reportLayerError(layer, builtinError, "builtin-shader-fallback");
          program = null;
        }
      } else {
        this.reportShaderError(layer, error, "builtin-shader");
        this.reportLayerError(layer, error, "builtin-shader");
        program = null;
      }

      if (!program) {
        program = this.shaderManager.getProgram(
          shaderCacheKeyForLayer({ shader: "default" }, "default", getBuiltinShader("default")),
          FULLSCREEN_VERTEX_SHADER,
          getBuiltinShader("default")
        );
      }
    }
    const gl = this.gl;

    gl.useProgram(program);
    gl.bindBuffer(gl.ARRAY_BUFFER, this.fullscreenBuffer);

    const positionLocation = gl.getAttribLocation(program, "a_position");
    gl.enableVertexAttribArray(positionLocation);
    gl.vertexAttribPointer(positionLocation, 2, gl.FLOAT, false, 0, 0);

    const bands = audio?.bands || {};
    const bandPeaks = audio?.band_peaks || {};
    const onsets = audio?.onsets || {};
    const drums = audio?.drums || {};
    this.setUniform1f(program, "u_time", time);
    this.setUniform2f(program, "u_resolution", resolution[0], resolution[1]);
    this.setUniform1f(program, "u_amplitude", audio?.amplitude || 0);
    this.setUniform1f(program, "u_bass", bands.low || 0);
    this.setUniform1f(program, "u_mid", bands.mid || 0);
    this.setUniform1f(program, "u_high", bands.high || 0);
    this.setUniform1f(program, "u_bass_peak", bandPeaks.low || 0);
    this.setUniform1f(program, "u_mid_peak", bandPeaks.mid || 0);
    this.setUniform1f(program, "u_high_peak", bandPeaks.high || 0);
    this.setUniform1f(program, "u_beat", audio?.beat ? 1 : 0);
    this.setUniform1f(program, "u_beat_pulse", audio?.beat_pulse || (audio?.beat ? 1 : 0));
    this.setUniform1f(program, "u_beat_phase", audio?.beat_phase || 0);
    this.setUniform1f(program, "u_bar_phase", audio?.bar_phase || 0);
    this.setUniform1f(program, "u_bar_count", audio?.bar_count || 0);
    this.setUniform1f(program, "u_phrase_count", audio?.phrase_count || 0);
    this.setUniform1f(program, "u_beat_2", audio?.beat_2 ? 1 : 0);
    this.setUniform1f(program, "u_beat_4", audio?.beat_4 ? 1 : 0);
    this.setUniform1f(program, "u_beat_8", audio?.beat_8 ? 1 : 0);
    this.setUniform1f(program, "u_beat_triplet", audio?.beat_triplet ? 1 : 0);
    this.setUniform1f(program, "u_onset", audio?.onset || 0);
    this.setUniform1f(program, "u_sub_onset", onsets.sub || 0);
    this.setUniform1f(program, "u_low_onset", onsets.low || 0);
    this.setUniform1f(program, "u_mid_onset", onsets.mid || 0);
    this.setUniform1f(program, "u_high_onset", onsets.high || 0);
    this.setUniform1f(program, "u_kick", drums.kick || 0);
    this.setUniform1f(program, "u_snare", drums.snare || 0);
    this.setUniform1f(program, "u_hihat", drums.hihat || 0);
    this.setUniform1f(program, "u_bpm", audio?.bpm || 0);
    const spectrum = normalizeSpectrum(audio?.fft, 32);
    this.setUniform1fv(program, "u_fft[0]", spectrum);
    this.setUniform1f(program, "u_fft_size", spectrum.length);
    this.setUniform1f(program, "u_visual_gain", audio?.visual_gain || visualSettings?.visualGain || 1);
    this.setUniform1f(program, "u_bass_boost", audio?.bass_boost || visualSettings?.bassBoost || 1);
    this.setUniform1f(program, "u_wobble_amount", audio?.wobble_amount || visualSettings?.wobbleAmount || 1);

    const runtimeGlobals = globals && typeof globals === "object" ? globals : {};
    for (const [key, value] of Object.entries(runtimeGlobals)) {
      const numeric = coerceUniformNumber(value);
      if (numeric === null) {
        continue;
      }
      for (const uniformName of shaderGlobalUniformNames(key)) {
        this.setUniform1f(program, uniformName, numeric);
      }
    }

    const params = layer?.params || {};
    for (const [key, value] of Object.entries(params)) {
      const numeric = coerceUniformNumber(value);
      if (numeric === null) {
        continue;
      }
      for (const uniformName of shaderParamUniformNames(key)) {
        this.setUniform1f(program, uniformName, numeric);
      }
    }

    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
  }

  renderGeometryLayer(layer, audio, rotation, time, paletteIndex = 0) {
    const gl = this.gl;
    const params = layer?.params || {};
    const colorShift = clamp(Number(params.color_shift || 0), 0, 1);
    const deform = estimateDeformFromSpectrum(params.deform ?? audio?.fft);
    const type = String(layer?.type || "").toLowerCase();
    let points = buildWireframeLines({
      rotationY: rotation,
      rotationX: rotation * 0.8,
      deform
    });

    if (type === "radial_blob") {
      points = buildRadialBlobLines({ time, params, audio });
    } else if (isMeshLayer(layer)) {
      points = buildPresetMeshLines({
        rotationY: rotation,
        rotationX: rotation * 0.8,
        deform,
        params
      });
    }

    gl.useProgram(this.geometryProgram);
    gl.bindBuffer(gl.ARRAY_BUFFER, this.geometryBuffer);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(points), gl.DYNAMIC_DRAW);
    gl.enableVertexAttribArray(this.geometryPositionLocation);
    gl.vertexAttribPointer(this.geometryPositionLocation, 2, gl.FLOAT, false, 0, 0);

    const amplitude = clamp(Number(audio?.amplitude || 0), 0, 1);
    const pulse = clamp(Number(audio?.beat_pulse || 0), 0, 1);
    const fallbackColor = [
      0.45 + amplitude * 0.45 + pulse * 0.15,
      0.75 + colorShift * 0.2,
      0.96
    ];
    const color = resolveLayerRgbColor(params, fallbackColor, paletteIndex);
    gl.uniform3f(this.geometryColorLocation, color[0], color[1], color[2]);
    gl.drawArrays(gl.LINES, 0, points.length / 2);
  }

  renderWaveformLayer(layer, audio, time, paletteIndex = 0) {
    const gl = this.gl;
    const params = layer?.params || {};
    const points = buildWaveformLines({ time, params, audio });

    if (points.length === 0) {
      return;
    }

    gl.useProgram(this.geometryProgram);
    gl.bindBuffer(gl.ARRAY_BUFFER, this.geometryBuffer);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(points), gl.DYNAMIC_DRAW);
    gl.enableVertexAttribArray(this.geometryPositionLocation);
    gl.vertexAttribPointer(this.geometryPositionLocation, 2, gl.FLOAT, false, 0, 0);

    const amplitude = clamp(Number(audio?.amplitude || 0), 0, 1);
    const high = clamp(Number(audio?.bands?.high || 0), 0, 1);
    const fallbackColor = [
      0.28 + high * 0.32,
      0.86 + amplitude * 0.14,
      0.72 + high * 0.22
    ];
    const color = resolveLayerRgbColor(params, fallbackColor, paletteIndex);
    gl.uniform3f(this.geometryColorLocation, color[0], color[1], color[2]);
    gl.drawArrays(gl.LINES, 0, points.length / 2);
  }

  renderParticleLayer(layer, audio, time, paletteIndex = 0) {
    const params = layer?.params || {};
    this.particleSystem.render({
      count: Number(params.count || 2400),
      speed: Number(params.speed || audio?.amplitude || 0),
      size: Number(params.size || 2.0),
      forceField: String(params.force_field || "drift"),
      turbulence: Number(params.turbulence || 0),
      bassExplosion: Number(params.bass_explosion || 0),
      sparkle: Number(params.sparkle || 0),
      color: resolveLayerRgbColor(params, null, paletteIndex),
      audio,
      time
    });
  }

  renderTextLayer(layer, audio, time, paletteIndex = 0) {
    const params = layer?.params || {};
    this.textRenderer.render({
      content: params.content || "VIZCORE",
      fontSize: Number(params.font_size || 120),
      color: resolveLayerCssColor(params, "#e5f3ff", paletteIndex),
      fontFamily: params.font || params.font_family,
      align: params.align,
      letterSpacing: params.letter_spacing,
      strokeWidth: params.stroke_width,
      strokeColor: params.stroke_color,
      shadowColor: params.shadow_color,
      shadowBlur: params.shadow_blur,
      glowStrength: Number(params.glow_strength ?? 0.15),
      audio,
      time
    });
  }

  renderImageLayer(layer, audio) {
    const params = layer?.params || {};
    this.imageRenderer.render({
      src: params.src || params.file,
      fit: params.fit,
      scale: params.scale,
      rotation: params.rotation,
      playbackRate: params.playback_rate,
      invert: params.invert,
      audio
    });
  }

  renderSpectrogramLayer(layer, audio) {
    this.spectrogramRenderer.render({
      key: layer?.name || "spectrogram",
      audio,
      params: layer?.params || {}
    });
  }

  renderShapeLayer(layer, audio, time, resolution, paletteIndex = 0) {
    const params = layer?.params || {};
    const amplitude = clamp(Number(audio?.amplitude || 0), 0, 1);
    const fallbackColor = [0.85, 0.50 + amplitude * 0.24, 0.95];
    const cssColor = resolveLayerCssColor(params, "#d98cff", paletteIndex);
    const rendered = this.shapeRenderer.render({
      params,
      color: cssColor,
      resolution,
      audio,
      time
    });
    if (rendered) {
      return;
    }

    const points = buildShapeLines({ params });

    if (points.length === 0) {
      return;
    }

    const color = resolveLayerRgbColor(params, fallbackColor, paletteIndex);
    this.renderLinePoints(points, color);
  }

  renderLinePoints(points, color) {
    const gl = this.gl;
    gl.useProgram(this.geometryProgram);
    gl.bindBuffer(gl.ARRAY_BUFFER, this.geometryBuffer);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(points), gl.DYNAMIC_DRAW);
    gl.enableVertexAttribArray(this.geometryPositionLocation);
    gl.vertexAttribPointer(this.geometryPositionLocation, 2, gl.FLOAT, false, 0, 0);
    gl.uniform3f(this.geometryColorLocation, color[0], color[1], color[2]);
    gl.drawArrays(gl.LINES, 0, points.length / 2);
  }

  compositeLayer(layer, { audio, time, resolution }) {
    const gl = this.gl;
    const params = layer?.params || {};
    const effects = this.resolvePostEffects(params);
    if (effects.length === 0) {
      this.drawLayerTexture(this.layerTexture, { layer, audio, time, resolution, opacity: params.opacity });
      return;
    }

    const blend = String(params.blend || "alpha").toLowerCase();
    const effectIntensity = clamp(Number(params.effect_intensity || audio?.amplitude || 0.35), 0, 1);
    let sourceTexture = this.layerTexture;
    let targetTexture = this.layerTextureSecondary;

    this.setBlendMode(blend);
    effects.forEach((effectName) => {
      const resolvedName = String(effectName);
      const vjShader = getVJEffectShader(resolvedName);
      const effectShader = getPostEffectShader(resolvedName);
      const selectedShader = vjShader || effectShader;
      const selectedEffectName = vjShader ? `vj:${resolvedName}` : `post:${resolvedName}`;
      let program = this.compositeProgram;

      if (selectedShader) {
        try {
          program = this.shaderManager.getProgram(
            selectedEffectName,
            FULLSCREEN_VERTEX_SHADER,
            selectedShader
          );
        } catch (error) {
          this.reportLayerError(layer, error, selectedEffectName);
          program = this.compositeProgram;
        }
      }

      this.applyEffectPass({
        sourceTexture,
        destinationTexture: targetTexture,
        program,
        time,
        resolution: [this.layerTargetWidth, this.layerTargetHeight],
        effectIntensity
      });

      [sourceTexture, targetTexture] = [targetTexture, sourceTexture];
    });

    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    gl.viewport(0, 0, resolution[0], resolution[1]);
    this.drawLayerTexture(sourceTexture, {
      layer,
      audio,
      time,
      resolution,
      opacity: params.opacity
    });
  }

  resolvePostEffects(params) {
    const postEffects = Array.isArray(params?.post_effects)
      ? params.post_effects
          .map((value) => String(value || "").trim().toLowerCase())
          .filter((value) => value.length > 0)
      : [];
    if (postEffects.length > 0) {
      return postEffects;
    }

    const vjEffectName = String(params?.vj_effect || "").trim().toLowerCase();
    if (vjEffectName) {
      return [vjEffectName];
    }

    const effectName = String(params?.effect || "").trim().toLowerCase();
    if (effectName) {
      return [effectName];
    }

    return [];
  }

  applyEffectPass({ sourceTexture, destinationTexture, program, time, resolution, effectIntensity }) {
    const gl = this.gl;
    if (!sourceTexture || !destinationTexture) {
      return;
    }

    gl.bindFramebuffer(gl.FRAMEBUFFER, this.layerFramebuffer);
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, destinationTexture, 0);
    gl.viewport(0, 0, this.layerTargetWidth, this.layerTargetHeight);
    gl.clearColor(0.0, 0.0, 0.0, 0.0);
    gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

    gl.useProgram(program);
    gl.bindBuffer(gl.ARRAY_BUFFER, this.fullscreenBuffer);
    const positionLocation = gl.getAttribLocation(program, "a_position");
    gl.enableVertexAttribArray(positionLocation);
    gl.vertexAttribPointer(positionLocation, 2, gl.FLOAT, false, 0, 0);

    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, sourceTexture);
    this.setUniform1i(program, "u_texture", 0);
    this.setUniform1f(program, "u_time", time);
    this.setUniform1f(program, "u_intensity", effectIntensity);
    this.setUniform2f(program, "u_resolution", resolution[0], resolution[1]);
    this.setUniform1f(program, "u_opacity", 1);

    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
  }

  drawLayerTexture(texture, { layer, audio, time, resolution, opacity }) {
    const gl = this.gl;
    const params = layer?.params || {};
    gl.useProgram(this.compositeProgram);
    gl.bindBuffer(gl.ARRAY_BUFFER, this.fullscreenBuffer);
    gl.enableVertexAttribArray(this.compositePositionLocation);
    gl.vertexAttribPointer(this.compositePositionLocation, 2, gl.FLOAT, false, 0, 0);

    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, texture);
    this.setUniform1i(this.compositeProgram, "u_texture", 0);
    this.setUniform1f(this.compositeProgram, "u_opacity", clamp(Number(opacity || 1), 0, 1));
    this.setUniform1f(this.compositeProgram, "u_time", time);
    this.setUniform1f(this.compositeProgram, "u_intensity", params.effect_intensity || audio?.amplitude || 0.35);
    this.setUniform2f(this.compositeProgram, "u_resolution", resolution[0], resolution[1]);

    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
  }

  ensureLayerTarget(width, height, layer = null, visualSettings = null) {
    if (!this.layerTargetAvailable) {
      return;
    }

    const [targetWidth, targetHeight] = this.resolveLayerTargetSize(width, height, layer, visualSettings);
    if (this.layerFramebuffer && this.layerTargetWidth === targetWidth && this.layerTargetHeight === targetHeight) {
      return;
    }
    this.layerTargetWidth = targetWidth;
    this.layerTargetHeight = targetHeight;

    this.disposeLayerTarget();

    const gl = this.gl;
    this.layerFramebuffer = gl.createFramebuffer();
    this.layerTexture = this.createLayerTexture(targetWidth, targetHeight);
    this.layerTextureSecondary = this.createLayerTexture(targetWidth, targetHeight);
    this.layerDepthRenderbuffer = gl.createRenderbuffer();

    gl.bindFramebuffer(gl.FRAMEBUFFER, this.layerFramebuffer);
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, this.layerTexture, 0);

    gl.bindRenderbuffer(gl.RENDERBUFFER, this.layerDepthRenderbuffer);
    gl.renderbufferStorage(gl.RENDERBUFFER, gl.DEPTH_COMPONENT16, targetWidth, targetHeight);
    gl.framebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.RENDERBUFFER, this.layerDepthRenderbuffer);

    const status = gl.checkFramebufferStatus(gl.FRAMEBUFFER);
    if (status !== gl.FRAMEBUFFER_COMPLETE) {
      console.warn("Layer framebuffer unavailable; falling back to direct rendering", status);
      this.layerTargetAvailable = false;
      this.disposeLayerTarget();
      gl.bindRenderbuffer(gl.RENDERBUFFER, null);
      gl.bindFramebuffer(gl.FRAMEBUFFER, null);
      return;
    }

    gl.bindRenderbuffer(gl.RENDERBUFFER, null);
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
  }

  attachPrimaryLayerTarget() {
    if (!this.layerFramebuffer || !this.layerTexture) {
      return;
    }

    this.gl.framebufferTexture2D(
      this.gl.FRAMEBUFFER,
      this.gl.COLOR_ATTACHMENT0,
      this.gl.TEXTURE_2D,
      this.layerTexture,
      0
    );
  }

  createLayerTexture(width, height) {
    const gl = this.gl;
    const texture = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, width, height, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    return texture;
  }

  disposeLayerTarget() {
    if (this.layerTexture) {
      this.gl.deleteTexture(this.layerTexture);
      this.layerTexture = null;
    }
    if (this.layerTextureSecondary) {
      this.gl.deleteTexture(this.layerTextureSecondary);
      this.layerTextureSecondary = null;
    }
    if (this.layerDepthRenderbuffer) {
      this.gl.deleteRenderbuffer(this.layerDepthRenderbuffer);
      this.layerDepthRenderbuffer = null;
    }
    if (this.layerFramebuffer) {
      this.gl.deleteFramebuffer(this.layerFramebuffer);
      this.layerFramebuffer = null;
    }
  }

  resolveLayerTargetSize(width, height, layer = null, visualSettings = null) {
    const gl = this.gl;
    const maxTextureSize = Number(gl.getParameter(gl.MAX_TEXTURE_SIZE) || 4096);
    const scale = resolveLayerResolutionScale(layer?.params || {}, visualSettings || {});
    let targetWidth = clamp(Math.floor(width * scale), 1, maxTextureSize);
    let targetHeight = clamp(Math.floor(height * scale), 1, maxTextureSize);

    const pixels = targetWidth * targetHeight;
    if (pixels > MAX_LAYER_TARGET_PIXELS) {
      const scale = Math.sqrt(MAX_LAYER_TARGET_PIXELS / pixels);
      targetWidth = Math.max(1, Math.floor(targetWidth * scale));
      targetHeight = Math.max(1, Math.floor(targetHeight * scale));
    }

    return [targetWidth, targetHeight];
  }

  dispose() {
    this.disposeLayerTarget();
    this.particleSystem?.dispose?.();
    this.textRenderer?.dispose?.();
    this.imageRenderer?.dispose?.();
    this.shapeRenderer?.dispose?.();
    this.spectrogramRenderer?.dispose?.();
    if (this.fullscreenBuffer) {
      this.gl.deleteBuffer(this.fullscreenBuffer);
      this.fullscreenBuffer = null;
    }
    if (this.geometryBuffer) {
      this.gl.deleteBuffer(this.geometryBuffer);
      this.geometryBuffer = null;
    }
  }

  setBlendMode(mode) {
    const blendMode = normalizeBlendMode(mode);
    this.gl.blendEquation(this.gl.FUNC_ADD);

    switch (blendMode) {
      case "add":
        this.gl.blendFunc(this.gl.SRC_ALPHA, this.gl.ONE);
        return;
      case "multiply":
        this.gl.blendFunc(this.gl.DST_COLOR, this.gl.ONE_MINUS_SRC_ALPHA);
        return;
      case "screen":
        this.gl.blendFunc(this.gl.ONE, this.gl.ONE_MINUS_SRC_COLOR);
        return;
      case "difference":
        this.gl.blendFunc(this.gl.ONE_MINUS_DST_COLOR, this.gl.ONE_MINUS_SRC_COLOR);
        return;
      default:
        this.gl.blendFunc(this.gl.SRC_ALPHA, this.gl.ONE_MINUS_SRC_ALPHA);
    }
  }

  setUniform1f(program, uniformName, value) {
    const location = this.gl.getUniformLocation(program, uniformName);
    if (location === null) {
      return;
    }
    this.gl.uniform1f(location, Number(value || 0));
  }

  setUniform1fv(program, uniformName, values) {
    const location = this.gl.getUniformLocation(program, uniformName);
    if (location === null) {
      return;
    }
    this.gl.uniform1fv(location, values);
  }

  setUniform2f(program, uniformName, x, y) {
    const location = this.gl.getUniformLocation(program, uniformName);
    if (location === null) {
      return;
    }
    this.gl.uniform2f(location, Number(x || 0), Number(y || 0));
  }

  setUniform1i(program, uniformName, value) {
    const location = this.gl.getUniformLocation(program, uniformName);
    if (location === null) {
      return;
    }
    this.gl.uniform1i(location, Number(value || 0));
  }

  reportLayerError(layer, error, phase) {
    const name = String(layer?.name || "unnamed");
    const shader = String(layer?.shader || layer?.type || "unknown");
    const key = `${phase}:${name}:${shader}`;
    if (this.layerErrorKeys.has(key)) {
      return;
    }
    this.layerErrorKeys.add(key);
    console.warn(`Layer render failed (${phase}) [${name}]`, error);
  }

  reportShaderError(layer, error, phase) {
    const detail = buildShaderErrorDetail({ layer, error, phase });
    const key = `shader:${detail.phase}:${detail.name}:${detail.shader}:${detail.message}`;
    if (this.layerErrorKeys.has(key)) {
      return;
    }
    this.layerErrorKeys.add(key);
    if (typeof window !== "undefined" && typeof window.dispatchEvent === "function") {
      window.dispatchEvent(new CustomEvent(SHADER_ERROR_EVENT, { detail }));
    }
  }

  pruneLastGoodShaderPrograms(activeKeys) {
    const active = activeKeys instanceof Set ? activeKeys : null;
    if (!active) {
      return;
    }
    for (const key of this.lastGoodShaderPrograms.keys()) {
      if (!active.has(key)) {
        this.lastGoodShaderPrograms.delete(key);
      }
    }
  }

  shaderLayerCacheKey(layer, layerIndex, hasCustomSource) {
    const name = String(layer?.name || "unnamed");
    const type = String(layer?.type || "layer");
    const sourceKind = hasCustomSource ? "custom" : "builtin";
    const sourceId = String(layer?.glsl || layer?.shader || layer?.type || "default");
    const index = Number.isFinite(layerIndex) ? layerIndex : "static";
    return `shader-layer|${sourceKind}|${index}|${type}|${name}|${sourceId}`;
  }
}

const isShaderLayer = (layer) => {
  const type = String(layer?.type || "").toLowerCase();
  return type === "shader" || !!layer?.shader || !!layer?.glsl;
};

const isParticleLayer = (layer) => {
  const type = String(layer?.type || "").toLowerCase();
  return type === "particle_field" || type === "particles" || type === "particle";
};

const isTextLayer = (layer) => {
  const type = String(layer?.type || "").toLowerCase();
  return type === "text" || type === "text_layer";
};

const isSvgLayer = (layer) => {
  const type = String(layer?.type || "").toLowerCase();
  return type === "svg" || type === "svg_layer";
};

const isRasterImageLayer = (layer) => {
  const type = String(layer?.type || "").toLowerCase();
  return type === "image" || type === "image_layer" || type === "photo";
};

const isImageLayer = (layer) => isSvgLayer(layer) || isRasterImageLayer(layer);

const isVideoLayer = (layer) => {
  const type = String(layer?.type || "").toLowerCase();
  return type === "video" || type === "video_layer" || type === "footage";
};

const isWaveformLayer = (layer) => {
  const type = String(layer?.type || "").toLowerCase();
  return type === "waveform" || type === "waveform_layer";
};

const isSpectrogramLayer = (layer) => {
  const type = String(layer?.type || "").toLowerCase();
  return type === "spectrogram" || type === "spectrogram_layer";
};

const isShapeLayer = (layer) => {
  const type = String(layer?.type || "").toLowerCase();
  return type === "shape" || type === "shapes" || type === "shape_layer";
};

const isMeshLayer = (layer) => {
  const type = String(layer?.type || "").toLowerCase();
  return type === "mesh" || type === "mesh_layer" || type === "preset_mesh";
};

const defaultLayer = (audio) => ({
  name: "wireframe_cube",
  type: "geometry",
  params: {
    color_shift: Number(audio?.bands?.high || 0),
    deform: audio?.fft || []
  }
});

const clamp = (value, min, max) => Math.min(Math.max(value, min), max);

const stableHash = (value) => hashString(stableStringify(value));

const stableStringify = (value) => {
  if (value === null || typeof value !== "object") {
    return String(value);
  }

  if (Array.isArray(value)) {
    return `[${value.map((entry) => stableStringify(entry)).join(",")}]`;
  }

  return `{${Object.keys(value).sort().map((key) => `${key}:${stableStringify(value[key])}`).join(",")}}`;
};

const hashString = (value) => {
  const text = String(value || "");
  let hash = 0;
  for (let index = 0; index < text.length; index += 1) {
    hash = (hash * 31 + text.charCodeAt(index)) >>> 0;
  }
  return hash.toString(16);
};
