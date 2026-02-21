import { getBuiltinShader } from "../shaders/builtins.js";
import { getPostEffectShader } from "../shaders/post-effects.js";
import { buildWireframeLines, estimateDeformFromSpectrum } from "../visuals/geometry.js";
import { ParticleSystem } from "../visuals/particle-system.js";
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
    this.layerDepthRenderbuffer = null;
    this.layerTargetWidth = 0;
    this.layerTargetHeight = 0;

    this.particleSystem = new ParticleSystem(this.gl, this.shaderManager);
    this.textRenderer = new TextRenderer(this.gl, this.shaderManager);

    this.gl.bindBuffer(this.gl.ARRAY_BUFFER, this.fullscreenBuffer);
    this.gl.bufferData(this.gl.ARRAY_BUFFER, FULLSCREEN_VERTICES, this.gl.STATIC_DRAW);
  }

  renderScene({ layers, audio, time, rotation, resolution }) {
    const layerList = Array.isArray(layers) && layers.length > 0 ? layers : [defaultLayer(audio)];
    const width = Math.max(1, Math.floor(Number(resolution?.[0] || 1)));
    const height = Math.max(1, Math.floor(Number(resolution?.[1] || 1)));
    this.ensureLayerTarget(width, height);

    for (const layer of layerList) {
      this.gl.bindFramebuffer(this.gl.FRAMEBUFFER, this.layerFramebuffer);
      this.gl.viewport(0, 0, width, height);
      this.gl.clearColor(0.0, 0.0, 0.0, 0.0);
      this.gl.clear(this.gl.COLOR_BUFFER_BIT | this.gl.DEPTH_BUFFER_BIT);

      this.renderLayer(layer, audio, time, rotation, [width, height]);

      this.gl.bindFramebuffer(this.gl.FRAMEBUFFER, null);
      this.gl.viewport(0, 0, width, height);
      this.compositeLayer(layer, { audio, time, resolution: [width, height] });
    }
    this.setBlendMode("alpha");
  }

  renderLayer(layer, audio, time, rotation, resolution) {
    if (isParticleLayer(layer)) {
      this.renderParticleLayer(layer, audio, time);
      return;
    }
    if (isTextLayer(layer)) {
      this.renderTextLayer(layer, audio, time);
      return;
    }
    if (isShaderLayer(layer)) {
      this.renderShaderLayer(layer, audio, time, resolution);
      return;
    }
    this.renderGeometryLayer(layer, audio, rotation);
  }

  renderShaderLayer(layer, audio, time, resolution) {
    const shaderName = String(layer?.shader || "gradient_pulse");
    const customSource = typeof layer?.glsl_source === "string" ? layer.glsl_source : null;
    const fragmentShader = customSource || getBuiltinShader(shaderName);
    const cacheKey = customSource
      ? `custom:${String(layer?.glsl || shaderName)}:${hashString(customSource)}`
      : `builtin:${shaderName}`;
    let program = null;
    try {
      program = this.shaderManager.getProgram(cacheKey, FULLSCREEN_VERTEX_SHADER, fragmentShader);
    } catch (error) {
      if (!customSource) {
        throw error;
      }
      console.warn("Failed to compile custom GLSL, falling back to builtin shader", error);
      program = this.shaderManager.getProgram(
        `builtin:${shaderName}`,
        FULLSCREEN_VERTEX_SHADER,
        getBuiltinShader(shaderName)
      );
    }
    const gl = this.gl;

    gl.useProgram(program);
    gl.bindBuffer(gl.ARRAY_BUFFER, this.fullscreenBuffer);

    const positionLocation = gl.getAttribLocation(program, "a_position");
    gl.enableVertexAttribArray(positionLocation);
    gl.vertexAttribPointer(positionLocation, 2, gl.FLOAT, false, 0, 0);

    const bands = audio?.bands || {};
    this.setUniform1f(program, "u_time", time);
    this.setUniform2f(program, "u_resolution", resolution[0], resolution[1]);
    this.setUniform1f(program, "u_amplitude", audio?.amplitude || 0);
    this.setUniform1f(program, "u_bass", bands.low || 0);
    this.setUniform1f(program, "u_mid", bands.mid || 0);
    this.setUniform1f(program, "u_high", bands.high || 0);
    this.setUniform1f(program, "u_beat", audio?.beat ? 1 : 0);
    this.setUniform1f(program, "u_bpm", audio?.bpm || 0);

    const params = layer?.params || {};
    for (const [key, value] of Object.entries(params)) {
      if (typeof value !== "number") {
        continue;
      }
      const safeKey = key.replace(/[^a-zA-Z0-9_]/g, "_");
      this.setUniform1f(program, `u_param_${safeKey}`, value);
    }

    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
  }

  renderGeometryLayer(layer, audio, rotation) {
    const gl = this.gl;
    const params = layer?.params || {};
    const colorShift = clamp(Number(params.color_shift || 0), 0, 1);
    const deform = estimateDeformFromSpectrum(params.deform ?? audio?.fft);
    const points = buildWireframeLines({
      rotationY: rotation,
      rotationX: rotation * 0.8,
      deform
    });

    gl.useProgram(this.geometryProgram);
    gl.bindBuffer(gl.ARRAY_BUFFER, this.geometryBuffer);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(points), gl.DYNAMIC_DRAW);
    gl.enableVertexAttribArray(this.geometryPositionLocation);
    gl.vertexAttribPointer(this.geometryPositionLocation, 2, gl.FLOAT, false, 0, 0);

    const amplitude = clamp(Number(audio?.amplitude || 0), 0, 1);
    gl.uniform3f(
      this.geometryColorLocation,
      0.45 + amplitude * 0.45,
      0.75 + colorShift * 0.2,
      0.96
    );
    gl.drawArrays(gl.LINES, 0, points.length / 2);
  }

  renderParticleLayer(layer, audio, time) {
    const params = layer?.params || {};
    this.particleSystem.render({
      count: Number(params.count || 2400),
      speed: Number(params.speed || audio?.amplitude || 0),
      size: Number(params.size || 2.0),
      audio,
      time
    });
  }

  renderTextLayer(layer, audio, time) {
    const params = layer?.params || {};
    this.textRenderer.render({
      content: params.content || "VIZCORE",
      fontSize: Number(params.font_size || 120),
      color: params.color || "#e5f3ff",
      audio,
      time
    });
  }

  compositeLayer(layer, { audio, time, resolution }) {
    const gl = this.gl;
    const params = layer?.params || {};
    const opacity = clamp(Number(params.opacity || 1), 0, 1);
    const blend = String(params.blend || "alpha").toLowerCase();
    const effectName = String(params.effect || "");
    const vjEffectName = String(params.vj_effect || "");
    const effectIntensity = clamp(Number(params.effect_intensity || audio?.amplitude || 0.35), 0, 1);
    const effectShader = getPostEffectShader(effectName);
    const vjShader = getVJEffectShader(vjEffectName);
    const selectedShader = vjShader || effectShader;
    const selectedEffectName = vjShader ? `vj:${vjEffectName}` : `post:${effectName}`;
    const program = selectedShader
      ? this.shaderManager.getProgram(
        selectedEffectName,
        FULLSCREEN_VERTEX_SHADER,
        selectedShader
      )
      : this.compositeProgram;

    this.setBlendMode(blend);

    gl.useProgram(program);
    gl.bindBuffer(gl.ARRAY_BUFFER, this.fullscreenBuffer);
    const positionLocation = gl.getAttribLocation(program, "a_position");
    gl.enableVertexAttribArray(positionLocation);
    gl.vertexAttribPointer(positionLocation, 2, gl.FLOAT, false, 0, 0);

    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, this.layerTexture);
    this.setUniform1i(program, "u_texture", 0);
    this.setUniform1f(program, "u_opacity", opacity);
    this.setUniform1f(program, "u_time", time);
    this.setUniform1f(program, "u_intensity", effectIntensity);
    this.setUniform2f(program, "u_resolution", resolution[0], resolution[1]);

    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
  }

  ensureLayerTarget(width, height) {
    if (this.layerFramebuffer && this.layerTargetWidth === width && this.layerTargetHeight === height) {
      return;
    }
    this.layerTargetWidth = width;
    this.layerTargetHeight = height;

    this.disposeLayerTarget();

    const gl = this.gl;
    this.layerFramebuffer = gl.createFramebuffer();
    this.layerTexture = gl.createTexture();
    this.layerDepthRenderbuffer = gl.createRenderbuffer();

    gl.bindTexture(gl.TEXTURE_2D, this.layerTexture);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, width, height, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);

    gl.bindFramebuffer(gl.FRAMEBUFFER, this.layerFramebuffer);
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, this.layerTexture, 0);

    gl.bindRenderbuffer(gl.RENDERBUFFER, this.layerDepthRenderbuffer);
    gl.renderbufferStorage(gl.RENDERBUFFER, gl.DEPTH_COMPONENT16, width, height);
    gl.framebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.RENDERBUFFER, this.layerDepthRenderbuffer);

    gl.bindRenderbuffer(gl.RENDERBUFFER, null);
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
  }

  disposeLayerTarget() {
    if (this.layerTexture) {
      this.gl.deleteTexture(this.layerTexture);
      this.layerTexture = null;
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

  setBlendMode(mode) {
    if (mode === "add" || mode === "additive") {
      this.gl.blendFunc(this.gl.SRC_ALPHA, this.gl.ONE);
      return;
    }
    this.gl.blendFunc(this.gl.SRC_ALPHA, this.gl.ONE_MINUS_SRC_ALPHA);
  }

  setUniform1f(program, uniformName, value) {
    const location = this.gl.getUniformLocation(program, uniformName);
    if (location === null) {
      return;
    }
    this.gl.uniform1f(location, Number(value || 0));
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

const defaultLayer = (audio) => ({
  name: "wireframe_cube",
  type: "geometry",
  params: {
    color_shift: Number(audio?.bands?.high || 0),
    deform: audio?.fft || []
  }
});

const clamp = (value, min, max) => Math.min(Math.max(value, min), max);

const hashString = (value) => {
  let hash = 0;
  for (let index = 0; index < value.length; index += 1) {
    hash = (hash * 31 + value.charCodeAt(index)) >>> 0;
  }
  return hash.toString(16);
};
