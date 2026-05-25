const TEXT_VERTEX_SHADER = `#version 300 es
in vec2 a_position;
in vec2 a_uv;
out vec2 v_uv;
void main() {
  v_uv = a_uv;
  gl_Position = vec4(a_position, 0.0, 1.0);
}
`;

const TEXT_FRAGMENT_SHADER = `#version 300 es
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

export class TextRenderer {
  constructor(gl, shaderManager) {
    this.gl = gl;
    this.shaderManager = shaderManager;
    this.program = this.shaderManager.getProgram("text-renderer", TEXT_VERTEX_SHADER, TEXT_FRAGMENT_SHADER);
    this.positionLocation = this.gl.getAttribLocation(this.program, "a_position");
    this.uvLocation = this.gl.getAttribLocation(this.program, "a_uv");
    this.textureLocation = this.gl.getUniformLocation(this.program, "u_texture");
    this.intensityLocation = this.gl.getUniformLocation(this.program, "u_intensity");

    this.buffer = this.gl.createBuffer();
    this.gl.bindBuffer(this.gl.ARRAY_BUFFER, this.buffer);
    this.gl.bufferData(this.gl.ARRAY_BUFFER, QUAD_VERTICES, this.gl.STATIC_DRAW);

    this.canvas = document.createElement("canvas");
    this.canvas.width = 1024;
    this.canvas.height = 512;
    this.ctx = this.canvas.getContext("2d");

    this.texture = this.gl.createTexture();
    this.gl.bindTexture(this.gl.TEXTURE_2D, this.texture);
    this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_MIN_FILTER, this.gl.LINEAR);
    this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_MAG_FILTER, this.gl.LINEAR);
    this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_S, this.gl.CLAMP_TO_EDGE);
    this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_T, this.gl.CLAMP_TO_EDGE);
  }

  render({ content, fontSize, audio, time, color, fontFamily, align, letterSpacing, strokeWidth, strokeColor, shadowColor, shadowBlur, glowStrength }) {
    const lines = normalizeTextLines(content);
    if (!lines.length) {
      return;
    }

    this.syncCanvasSize();

    const amp = clamp(Number(audio?.amplitude || 0), 0, 1);
    const beatBoost = audio?.beat ? 1.0 : 0.0;
    const singleLineMax = Math.floor(this.canvas.height * 0.22);
    const multilineMax = Math.floor((this.canvas.height * 0.58) / Math.max(lines.length, 1));
    const maxFontSize = Math.max(32, Math.min(singleLineMax, multilineMax));
    const dynamicSize = Math.round(
      clamp(Number(fontSize || 96), 18, maxFontSize) * (1 + amp * 0.08 + beatBoost * 0.04)
    );
    this.drawTextToCanvas({
      lines,
      fontSize: dynamicSize,
      time,
      color,
      fontFamily,
      align,
      letterSpacing,
      strokeWidth,
      strokeColor,
      shadowColor,
      shadowBlur,
      amplitude: amp,
      glowStrength: Number(glowStrength ?? 0.15)
    });
    this.uploadTexture();
    this.drawQuad({ intensity: 0.85 + amp * 0.15 });
  }

  drawTextToCanvas({ lines, fontSize, time, color, fontFamily, align, letterSpacing, strokeWidth, strokeColor, shadowColor, shadowBlur, amplitude, glowStrength }) {
    const ctx = this.ctx;
    ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);

    ctx.fillStyle = "rgba(0, 0, 0, 0.0)";
    ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);

    const safeColor = typeof color === "string" && color.trim() ? color : "#e5f3ff";
    const glow = clamp(Number(glowStrength || 0), 0, 1) * (1.5 + amplitude * 5.0);
    const xShift = Math.sin(time * 2.0) * (2 + amplitude * 4);
    const textAlign = normalizeTextAlign(align);
    const spacing = normalizeLetterSpacing(letterSpacing);
    const stroke = clamp(Number(strokeWidth || 0), 0, 24);
    const shadow = shadowBlur === undefined ? glow : clamp(Number(shadowBlur || 0), 0, 80);

    ctx.textAlign = textAlign;
    ctx.textBaseline = "middle";
    ctx.font = `700 ${fontSize}px ${normalizeFontFamily(fontFamily)}`;
    ctx.shadowColor = normalizeTextColor(shadowColor, "rgba(110, 208, 255, 0.35)");
    ctx.shadowBlur = shadow;
    ctx.fillStyle = safeColor;
    const x = resolveTextX(this.canvas.width, textAlign) + xShift;
    const lineHeight = fontSize * 1.16;
    const startY = this.canvas.height / 2 - ((lines.length - 1) * lineHeight) / 2;
    lines.forEach((line, index) => {
      const y = startY + index * lineHeight;
      if (stroke > 0) {
        ctx.lineJoin = "round";
        ctx.lineWidth = stroke;
        ctx.strokeStyle = normalizeTextColor(strokeColor, safeColor);
        drawText(ctx, { text: line, x, y, align: textAlign, letterSpacing: spacing, method: "strokeText" });
      }
      drawText(ctx, { text: line, x, y, align: textAlign, letterSpacing: spacing, method: "fillText" });
    });
  }

  syncCanvasSize() {
    const width = clamp(Math.floor(this.gl.drawingBufferWidth || 1024), 640, 2048);
    const height = clamp(Math.floor(this.gl.drawingBufferHeight || 512), 360, 2048);
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

  dispose() {
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

const clamp = (value, min, max) => Math.min(Math.max(value, min), max);

export const normalizeTextAlign = (value) => {
  const align = String(value || "center").trim().toLowerCase();
  if (align === "left" || align === "right" || align === "center") {
    return align;
  }
  return "center";
};

export const resolveTextX = (width, align) => {
  const canvasWidth = Number(width) || 0;
  if (align === "left") return canvasWidth * 0.12;
  if (align === "right") return canvasWidth * 0.88;
  return canvasWidth * 0.5;
};

export const normalizeTextLines = (value) => {
  return String(value || "")
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .slice(0, 6);
};

export const normalizeLetterSpacing = (value) => {
  const spacing = Number(value);
  if (!Number.isFinite(spacing)) return 0;
  return clamp(spacing, 0, 96);
};

export const measureLetterSpacedText = (ctx, text, letterSpacing = 0) => {
  const chars = Array.from(String(text || ""));
  if (!chars.length) return 0;

  const spacing = normalizeLetterSpacing(letterSpacing);
  const glyphWidth = chars.reduce((total, char) => {
    return total + Number(ctx.measureText(char)?.width || 0);
  }, 0);
  return glyphWidth + spacing * (chars.length - 1);
};

export const resolveLetterSpacedStartX = (ctx, text, x, align, letterSpacing = 0) => {
  const width = measureLetterSpacedText(ctx, text, letterSpacing);
  if (align === "right") return x - width;
  if (align === "center") return x - width / 2;
  return x;
};

export const normalizeFontFamily = (value) => {
  const family = String(value || "").trim();
  if (!family) return "\"IBM Plex Sans\", \"Noto Sans JP\", sans-serif";
  if (family.includes(",")) return `${family}, "IBM Plex Sans", "Noto Sans JP", sans-serif`;

  return `"${family.replaceAll("\"", "")}", "IBM Plex Sans", "Noto Sans JP", sans-serif`;
};

const normalizeTextColor = (value, fallback) => {
  const color = String(value || "").trim();
  return color || fallback;
};

const drawText = (ctx, { text, x, y, align, letterSpacing, method }) => {
  if (letterSpacing <= 0) {
    ctx[method](text, x, y);
    return;
  }

  const originalAlign = ctx.textAlign;
  ctx.textAlign = "left";
  let cursor = resolveLetterSpacedStartX(ctx, text, x, align, letterSpacing);
  for (const char of Array.from(text)) {
    ctx[method](char, cursor, y);
    cursor += Number(ctx.measureText(char)?.width || 0) + letterSpacing;
  }
  ctx.textAlign = originalAlign;
};
