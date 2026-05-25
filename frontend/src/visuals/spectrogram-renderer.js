const SPECTROGRAM_VERTEX_SHADER = `#version 300 es
in vec2 a_position;
in vec2 a_uv;
out vec2 v_uv;
void main() {
  v_uv = a_uv;
  gl_Position = vec4(a_position, 0.0, 1.0);
}
`;

const SPECTROGRAM_FRAGMENT_SHADER = `#version 300 es
precision mediump float;
in vec2 v_uv;
uniform sampler2D u_texture;
uniform float u_opacity;
out vec4 outColor;

void main() {
  vec4 texel = texture(u_texture, v_uv);
  outColor = vec4(texel.rgb, texel.a * u_opacity);
}
`;

const QUAD_VERTICES = new Float32Array([
  -1.0, -1.0, 0.0, 1.0,
  1.0, -1.0, 1.0, 1.0,
  -1.0, 1.0, 0.0, 0.0,
  1.0, 1.0, 1.0, 0.0
]);

export class SpectrogramRenderer {
  constructor(gl, shaderManager) {
    this.gl = gl;
    this.shaderManager = shaderManager;
    this.program = this.shaderManager.getProgram(
      "spectrogram-renderer",
      SPECTROGRAM_VERTEX_SHADER,
      SPECTROGRAM_FRAGMENT_SHADER
    );
    this.positionLocation = this.gl.getAttribLocation(this.program, "a_position");
    this.uvLocation = this.gl.getAttribLocation(this.program, "a_uv");
    this.textureLocation = this.gl.getUniformLocation(this.program, "u_texture");
    this.opacityLocation = this.gl.getUniformLocation(this.program, "u_opacity");
    this.histories = new Map();

    this.buffer = this.gl.createBuffer();
    this.gl.bindBuffer(this.gl.ARRAY_BUFFER, this.buffer);
    this.gl.bufferData(this.gl.ARRAY_BUFFER, QUAD_VERTICES, this.gl.STATIC_DRAW);

    this.canvas = document.createElement("canvas");
    this.ctx = this.canvas.getContext("2d");

    this.texture = this.gl.createTexture();
    this.gl.bindTexture(this.gl.TEXTURE_2D, this.texture);
    this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_MIN_FILTER, this.gl.LINEAR);
    this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_MAG_FILTER, this.gl.LINEAR);
    this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_S, this.gl.CLAMP_TO_EDGE);
    this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_T, this.gl.CLAMP_TO_EDGE);
  }

  render({ key, audio, params = {} }) {
    const bins = normalizeSpectrogramBins(params.bins);
    const historySize = normalizeSpectrogramHistory(params.history);
    const scroll = normalizeSpectrogramScroll(params.scroll);
    const gain = normalizeSpectrogramGain(params.gain);
    const spectrum = normalizeSpectrogramSpectrum(audio?.fft, bins, gain);
    const history = this.updateHistory({ key, bins, historySize, spectrum });
    const image = buildSpectrogramPixels({ history, bins, historySize, scroll });

    this.drawImage(image);
    this.uploadTexture();
    this.drawQuad({ opacity: 1 });
  }

  updateHistory({ key, bins, historySize, spectrum }) {
    const cacheKey = String(key || "default");
    const current = this.histories.get(cacheKey);
    const history = current?.bins === bins && current?.historySize === historySize ? current.frames : [];
    history.push(spectrum);
    while (history.length > historySize) {
      history.shift();
    }
    this.histories.set(cacheKey, { bins, historySize, frames: history });
    return history;
  }

  drawImage({ width, height, pixels }) {
    if (this.canvas.width !== width) {
      this.canvas.width = width;
    }
    if (this.canvas.height !== height) {
      this.canvas.height = height;
    }

    const imageData = this.ctx.createImageData(width, height);
    imageData.data.set(pixels);
    this.ctx.putImageData(imageData, 0, 0);
  }

  uploadTexture() {
    this.gl.bindTexture(this.gl.TEXTURE_2D, this.texture);
    this.gl.texImage2D(
      this.gl.TEXTURE_2D,
      0,
      this.gl.RGBA,
      this.gl.RGBA,
      this.gl.UNSIGNED_BYTE,
      this.canvas
    );
  }

  drawQuad({ opacity }) {
    const gl = this.gl;
    gl.useProgram(this.program);
    gl.bindBuffer(gl.ARRAY_BUFFER, this.buffer);
    gl.enableVertexAttribArray(this.positionLocation);
    gl.vertexAttribPointer(this.positionLocation, 2, gl.FLOAT, false, 16, 0);
    gl.enableVertexAttribArray(this.uvLocation);
    gl.vertexAttribPointer(this.uvLocation, 2, gl.FLOAT, false, 16, 8);

    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, this.texture);
    gl.uniform1i(this.textureLocation, 0);
    gl.uniform1f(this.opacityLocation, clamp(Number(opacity || 1), 0, 1));
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
  }

  dispose() {
    this.histories.clear();
    if (this.texture) {
      this.gl.deleteTexture(this.texture);
      this.texture = null;
    }
    if (this.buffer) {
      this.gl.deleteBuffer(this.buffer);
      this.buffer = null;
    }
    this.canvas = null;
    this.ctx = null;
  }
}

export const normalizeSpectrogramScroll = (value) => {
  const scroll = String(value || "vertical").trim().toLowerCase();
  return scroll === "horizontal" ? "horizontal" : "vertical";
};

export const normalizeSpectrogramBins = (value) => {
  return clampInt(value || 64, 16, 256);
};

export const normalizeSpectrogramHistory = (value) => {
  return clampInt(value || 96, 16, 512);
};

export const normalizeSpectrogramGain = (value) => {
  const gain = Number(value);
  if (!Number.isFinite(gain)) return 1;
  return clamp(gain, 0.1, 8);
};

export const normalizeSpectrogramSpectrum = (value, bins, gain = 1) => {
  const input = Array.isArray(value) || ArrayBuffer.isView(value) ? Array.from(value) : [];
  const output = [];
  const safeBins = normalizeSpectrogramBins(bins);
  const safeGain = normalizeSpectrogramGain(gain);

  for (let index = 0; index < safeBins; index += 1) {
    const progress = safeBins === 1 ? 0 : index / (safeBins - 1);
    output.push(clamp(sampleSpectrum(input, progress) * safeGain, 0, 1));
  }

  return output;
};

export const buildSpectrogramPixels = ({ history, bins, historySize, scroll }) => {
  const safeBins = normalizeSpectrogramBins(bins);
  const safeHistorySize = normalizeSpectrogramHistory(historySize);
  const direction = normalizeSpectrogramScroll(scroll);
  const width = direction === "vertical" ? safeBins : safeHistorySize;
  const height = direction === "vertical" ? safeHistorySize : safeBins;
  const pixels = new Uint8ClampedArray(width * height * 4);
  const frames = Array.isArray(history) ? history.slice(-safeHistorySize) : [];

  frames.forEach((frame, frameIndex) => {
    const timeIndex = safeHistorySize - frames.length + frameIndex;
    for (let bin = 0; bin < safeBins; bin += 1) {
      const value = clamp(Number(frame?.[bin] || 0), 0, 1);
      const x = direction === "vertical" ? bin : timeIndex;
      const y = direction === "vertical" ? timeIndex : safeBins - 1 - bin;
      writePixel(pixels, width, x, y, spectrogramColor(value));
    }
  });

  return { width, height, pixels };
};

export const spectrogramColor = (value) => {
  const energy = clamp(Number(value || 0), 0, 1);
  const mid = 1 - Math.abs(energy * 2 - 1);
  return [
    Math.round(10 + energy * 245),
    Math.round(18 + Math.max(0, energy - 0.18) * 250),
    Math.round(36 + mid * 155 + energy * 36),
    Math.round(energy * 255)
  ];
};

const writePixel = (pixels, width, x, y, color) => {
  const offset = ((y * width) + x) * 4;
  pixels[offset] = color[0];
  pixels[offset + 1] = color[1];
  pixels[offset + 2] = color[2];
  pixels[offset + 3] = color[3];
};

const sampleSpectrum = (spectrum, progress) => {
  if (!spectrum.length) return 0;

  const position = progress * (spectrum.length - 1);
  const left = Math.floor(position);
  const right = Math.min(left + 1, spectrum.length - 1);
  const mix = position - left;
  const from = finiteNumber(spectrum[left], 0);
  const to = finiteNumber(spectrum[right], 0);
  return clamp(from + (to - from) * mix, 0, 1);
};

const finiteNumber = (value, fallback) => {
  const numeric = Number(value);
  return Number.isFinite(numeric) ? numeric : fallback;
};

const clampInt = (value, min, max) => {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) return min;
  return Math.round(Math.min(Math.max(numeric, min), max));
};

const clamp = (value, min, max) => Math.min(Math.max(value, min), max);
