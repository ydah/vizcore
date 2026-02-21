export const VJ_EFFECT_SHADERS = {
  mirror: `#version 300 es
precision mediump float;
in vec2 v_uv;
uniform sampler2D u_texture;
uniform float u_intensity;
out vec4 outColor;

void main() {
  vec2 uv = v_uv;
  if (uv.x > 0.5) {
    uv.x = 1.0 - uv.x;
  }
  vec4 left = texture(u_texture, uv);
  vec4 base = texture(u_texture, v_uv);
  float mixAmount = clamp(0.4 + u_intensity * 0.6, 0.0, 1.0);
  outColor = mix(base, left, mixAmount);
}
`,
  color_shift: `#version 300 es
precision mediump float;
in vec2 v_uv;
uniform sampler2D u_texture;
uniform float u_intensity;
out vec4 outColor;

void main() {
  vec2 shift = vec2(0.008 * (0.2 + u_intensity), 0.0);
  float r = texture(u_texture, v_uv + shift).r;
  float g = texture(u_texture, v_uv).g;
  float b = texture(u_texture, v_uv - shift).b;
  float a = texture(u_texture, v_uv).a;
  outColor = vec4(r, g, b, a);
}
`,
  pixelate: `#version 300 es
precision mediump float;
in vec2 v_uv;
uniform sampler2D u_texture;
uniform vec2 u_resolution;
uniform float u_intensity;
out vec4 outColor;

void main() {
  float blocks = mix(260.0, 40.0, clamp(u_intensity, 0.0, 1.0));
  vec2 grid = vec2(blocks, blocks * (u_resolution.y / max(u_resolution.x, 1.0)));
  vec2 uv = floor(v_uv * grid) / grid;
  outColor = texture(u_texture, uv);
}
`
};

export const getVJEffectShader = (name) => {
  const key = String(name || "").trim().toLowerCase();
  return VJ_EFFECT_SHADERS[key] || null;
};
