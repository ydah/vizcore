const VERTEX_SHADER = `#version 300 es
in vec2 a_position;
void main() {
  gl_Position = vec4(a_position, 0.0, 1.0);
}
`;

const FRAGMENT_SHADER = `#version 300 es
precision mediump float;
uniform vec3 u_color;
out vec4 outColor;
void main() {
  outColor = vec4(u_color, 1.0);
}
`;

const BASE_VERTICES = [
  [-1.0, -1.0, -1.0],
  [1.0, -1.0, -1.0],
  [1.0, 1.0, -1.0],
  [-1.0, 1.0, -1.0],
  [-1.0, -1.0, 1.0],
  [1.0, -1.0, 1.0],
  [1.0, 1.0, 1.0],
  [-1.0, 1.0, 1.0]
];

const EDGES = [
  [0, 1], [1, 2], [2, 3], [3, 0],
  [4, 5], [5, 6], [6, 7], [7, 4],
  [0, 4], [1, 5], [2, 6], [3, 7]
];

export class Engine {
  constructor(canvas) {
    this.canvas = canvas;
    this.gl = null;
    this.program = null;
    this.positionBuffer = null;
    this.colorLocation = null;
    this.positionLocation = -1;
    this.lineVertexCount = 0;
    this.rotation = 0;
    this.lastTime = performance.now();
    this.amplitude = 0;
    this.colorShift = 0;
    this.currentRotationSpeed = 0.5;
  }

  init() {
    this.gl = this.canvas.getContext("webgl2");
    if (!this.gl) {
      throw new Error("WebGL2 is not supported in this browser");
    }

    this.program = this.createProgram(VERTEX_SHADER, FRAGMENT_SHADER);
    this.positionLocation = this.gl.getAttribLocation(this.program, "a_position");
    this.colorLocation = this.gl.getUniformLocation(this.program, "u_color");
    this.positionBuffer = this.gl.createBuffer();

    this.gl.enable(this.gl.DEPTH_TEST);
    this.resize();
    window.addEventListener("resize", () => this.resize());
  }

  setAudioFrame(frame) {
    const amplitude = Number(frame?.audio?.amplitude || 0);
    const colorShift = Number(frame?.scene?.layers?.[0]?.params?.color_shift || 0);
    this.amplitude = clamp(amplitude, 0, 1);
    this.colorShift = clamp(colorShift, 0, 1);
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

    const targetSpeed = 0.35 + this.amplitude * 1.8;
    this.currentRotationSpeed += (targetSpeed - this.currentRotationSpeed) * 0.1;
    this.rotation += deltaSeconds * this.currentRotationSpeed;

    const positions = this.buildProjectedLines(this.rotation, this.rotation * 0.8);
    this.lineVertexCount = positions.length / 2;

    this.gl.clearColor(
      0.02 + this.amplitude * 0.05,
      0.03 + this.colorShift * 0.08,
      0.08 + this.amplitude * 0.06,
      1.0
    );
    this.gl.clear(this.gl.COLOR_BUFFER_BIT | this.gl.DEPTH_BUFFER_BIT);

    this.gl.useProgram(this.program);
    this.gl.bindBuffer(this.gl.ARRAY_BUFFER, this.positionBuffer);
    this.gl.bufferData(this.gl.ARRAY_BUFFER, new Float32Array(positions), this.gl.DYNAMIC_DRAW);
    this.gl.enableVertexAttribArray(this.positionLocation);
    this.gl.vertexAttribPointer(this.positionLocation, 2, this.gl.FLOAT, false, 0, 0);

    this.gl.uniform3f(
      this.colorLocation,
      0.45 + this.amplitude * 0.45,
      0.75 + this.colorShift * 0.2,
      0.96
    );

    this.gl.drawArrays(this.gl.LINES, 0, this.lineVertexCount);
    requestAnimationFrame((nextTime) => this.render(nextTime));
  }

  buildProjectedLines(angleY, angleX) {
    const projected = BASE_VERTICES.map((vertex) => projectVertex(vertex, angleY, angleX));
    const lines = [];

    for (const [start, end] of EDGES) {
      lines.push(projected[start][0], projected[start][1]);
      lines.push(projected[end][0], projected[end][1]);
    }

    return lines;
  }

  createProgram(vertexSource, fragmentSource) {
    const gl = this.gl;
    const vertexShader = compileShader(gl, gl.VERTEX_SHADER, vertexSource);
    const fragmentShader = compileShader(gl, gl.FRAGMENT_SHADER, fragmentSource);

    const program = gl.createProgram();
    gl.attachShader(program, vertexShader);
    gl.attachShader(program, fragmentShader);
    gl.linkProgram(program);

    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
      const info = gl.getProgramInfoLog(program);
      throw new Error(`Program linking failed: ${info}`);
    }

    gl.deleteShader(vertexShader);
    gl.deleteShader(fragmentShader);
    return program;
  }
}

function compileShader(gl, type, source) {
  const shader = gl.createShader(type);
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    const info = gl.getShaderInfoLog(shader);
    throw new Error(`Shader compilation failed: ${info}`);
  }
  return shader;
}

function projectVertex(vertex, angleY, angleX) {
  const [x, y, z] = vertex;

  const cosY = Math.cos(angleY);
  const sinY = Math.sin(angleY);
  const x1 = x * cosY - z * sinY;
  const z1 = x * sinY + z * cosY;

  const cosX = Math.cos(angleX);
  const sinX = Math.sin(angleX);
  const y1 = y * cosX - z1 * sinX;
  const z2 = y * sinX + z1 * cosX + 4.2;

  const perspectiveScale = 1.6 / z2;
  return [x1 * perspectiveScale, y1 * perspectiveScale];
}

function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max);
}
