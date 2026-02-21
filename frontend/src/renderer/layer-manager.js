import { getBuiltinShader } from "../shaders/builtins.js";
import { buildWireframeLines, estimateDeformFromSpectrum } from "../visuals/geometry.js";
import { ParticleSystem } from "../visuals/particle-system.js";
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
    this.particleSystem = new ParticleSystem(this.gl, this.shaderManager);

    this.gl.bindBuffer(this.gl.ARRAY_BUFFER, this.fullscreenBuffer);
    this.gl.bufferData(this.gl.ARRAY_BUFFER, FULLSCREEN_VERTICES, this.gl.STATIC_DRAW);
  }

  renderScene({ layers, audio, time, rotation, resolution }) {
    const layerList = Array.isArray(layers) && layers.length > 0 ? layers : [defaultLayer(audio)];
    for (const layer of layerList) {
      if (isParticleLayer(layer)) {
        this.renderParticleLayer(layer, audio, time);
      } else if (isShaderLayer(layer)) {
        this.renderShaderLayer(layer, audio, time, resolution);
      } else {
        this.renderGeometryLayer(layer, audio, rotation);
      }
    }
  }

  renderShaderLayer(layer, audio, time, resolution) {
    const shaderName = String(layer?.shader || "gradient_pulse");
    const fragmentShader = getBuiltinShader(shaderName);
    const program = this.shaderManager.getProgram(
      `builtin:${shaderName}`,
      FULLSCREEN_VERTEX_SHADER,
      fragmentShader
    );
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
}

const isShaderLayer = (layer) => {
  const type = String(layer?.type || "").toLowerCase();
  return type === "shader" || !!layer?.shader || !!layer?.glsl;
};

const isParticleLayer = (layer) => {
  const type = String(layer?.type || "").toLowerCase();
  return type === "particle_field" || type === "particles" || type === "particle";
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
