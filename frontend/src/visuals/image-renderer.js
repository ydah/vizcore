const IMAGE_VERTEX_SHADER = `#version 300 es
in vec2 a_position;
in vec2 a_uv;
out vec2 v_uv;
void main() {
  v_uv = a_uv;
  gl_Position = vec4(a_position, 0.0, 1.0);
}
`;

const IMAGE_FRAGMENT_SHADER = `#version 300 es
precision mediump float;
in vec2 v_uv;
uniform sampler2D u_texture;
uniform float u_intensity;
out vec4 outColor;

void main() {
  vec4 texel = texture(u_texture, v_uv);
  outColor = vec4(texel.rgb, texel.a * u_intensity);
}
`;

const QUAD_VERTICES = new Float32Array([
  -1.0, -1.0, 0.0, 1.0,
  1.0, -1.0, 1.0, 1.0,
  -1.0, 1.0, 0.0, 0.0,
  1.0, 1.0, 1.0, 0.0
]);

export class ImageRenderer {
  constructor(gl, shaderManager) {
    this.gl = gl;
    this.shaderManager = shaderManager;
    this.program = this.shaderManager.getProgram("image-renderer", IMAGE_VERTEX_SHADER, IMAGE_FRAGMENT_SHADER);
    this.positionLocation = this.gl.getAttribLocation(this.program, "a_position");
    this.uvLocation = this.gl.getAttribLocation(this.program, "a_uv");
    this.textureLocation = this.gl.getUniformLocation(this.program, "u_texture");
    this.intensityLocation = this.gl.getUniformLocation(this.program, "u_intensity");
    this.images = new Map();

    this.buffer = this.gl.createBuffer();
    this.gl.bindBuffer(this.gl.ARRAY_BUFFER, this.buffer);
    this.gl.bufferData(this.gl.ARRAY_BUFFER, QUAD_VERTICES, this.gl.STATIC_DRAW);

    this.canvas = document.createElement("canvas");
    this.canvas.width = 1024;
    this.canvas.height = 1024;
    this.ctx = this.canvas.getContext("2d");

    this.texture = this.gl.createTexture();
    this.gl.bindTexture(this.gl.TEXTURE_2D, this.texture);
    this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_MIN_FILTER, this.gl.LINEAR);
    this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_MAG_FILTER, this.gl.LINEAR);
    this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_S, this.gl.CLAMP_TO_EDGE);
    this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_T, this.gl.CLAMP_TO_EDGE);
  }

  render({ src, audio, fit, scale, rotation }) {
    const source = resolveMediaSource(src);
    if (!source) return;

    const image = this.loadImage(source);
    if (!image?.complete || Number(image.naturalWidth || 0) <= 0 || Number(image.naturalHeight || 0) <= 0) {
      return;
    }

    this.syncCanvasSize();
    const amplitude = clamp(Number(audio?.amplitude || 0), 0, 1);
    const pulse = clamp(Number(audio?.beat_pulse || 0), 0, 1);
    this.drawImageToCanvas({
      image,
      fit,
      scale: normalizeScale(scale) * (1 + amplitude * 0.04 + pulse * 0.03),
      rotation: normalizeRotation(rotation)
    });
    this.uploadTexture();
    this.drawQuad({ intensity: 0.9 + amplitude * 0.1 });
  }

  loadImage(src) {
    if (this.images.has(src)) {
      return this.images.get(src);
    }

    const image = new Image();
    if (!src.startsWith("data:")) {
      image.crossOrigin = "anonymous";
    }
    image.decoding = "async";
    image.src = src;
    this.images.set(src, image);
    return image;
  }

  drawImageToCanvas({ image, fit, scale, rotation }) {
    const ctx = this.ctx;
    ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
    const rect = resolveImageRect({
      canvasWidth: this.canvas.width,
      canvasHeight: this.canvas.height,
      imageWidth: image.naturalWidth,
      imageHeight: image.naturalHeight,
      fit,
      scale
    });

    ctx.save();
    ctx.translate(this.canvas.width / 2, this.canvas.height / 2);
    ctx.rotate(rotation);
    ctx.drawImage(image, -rect.width / 2, -rect.height / 2, rect.width, rect.height);
    ctx.restore();
  }

  syncCanvasSize() {
    const width = clamp(Math.floor(this.gl.drawingBufferWidth || 1024), 640, 2048);
    const height = clamp(Math.floor(this.gl.drawingBufferHeight || 1024), 360, 2048);
    if (this.canvas.width === width && this.canvas.height === height) {
      return;
    }
    this.canvas.width = width;
    this.canvas.height = height;
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

  drawQuad({ intensity }) {
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
    gl.uniform1f(this.intensityLocation, clamp(Number(intensity || 1), 0, 1));
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
  }
}

export const resolveMediaSource = (value) => {
  const source = String(value || "").trim();
  return source || null;
};

export const normalizeImageFit = (value) => {
  const fit = String(value || "contain").trim().toLowerCase();
  if (fit === "cover" || fit === "stretch") return fit;
  return "contain";
};

export const normalizeScale = (value) => {
  const scale = Number(value);
  if (!Number.isFinite(scale)) return 1;
  return clamp(scale, 0.01, 8);
};

export const normalizeRotation = (value) => {
  const rotation = Number(value);
  return Number.isFinite(rotation) ? rotation : 0;
};

export const resolveImageRect = ({ canvasWidth, canvasHeight, imageWidth, imageHeight, fit, scale = 1 }) => {
  const width = Math.max(Number(canvasWidth) || 0, 1);
  const height = Math.max(Number(canvasHeight) || 0, 1);
  const sourceWidth = Math.max(Number(imageWidth) || 0, 1);
  const sourceHeight = Math.max(Number(imageHeight) || 0, 1);
  const resolvedScale = normalizeScale(scale);
  const resolvedFit = normalizeImageFit(fit);

  if (resolvedFit === "stretch") {
    return { width: width * resolvedScale, height: height * resolvedScale };
  }

  const multiplier = resolvedFit === "cover"
    ? Math.max(width / sourceWidth, height / sourceHeight)
    : Math.min(width / sourceWidth, height / sourceHeight);
  return {
    width: sourceWidth * multiplier * resolvedScale,
    height: sourceHeight * multiplier * resolvedScale
  };
};

const clamp = (value, min, max) => Math.min(Math.max(value, min), max);
