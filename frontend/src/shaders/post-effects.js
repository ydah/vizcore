export const POST_EFFECT_SHADERS = {
  bloom: `#version 300 es
precision mediump float;
in vec2 v_uv;
uniform sampler2D u_texture;
uniform vec2 u_resolution;
uniform float u_time;
uniform float u_intensity;
out vec4 outColor;

void main() {
  vec2 texel = 1.0 / max(u_resolution, vec2(1.0));
  vec4 base = texture(u_texture, v_uv);
  vec4 blur = vec4(0.0);
  blur += texture(u_texture, v_uv + texel * vec2( 1.0,  0.0));
  blur += texture(u_texture, v_uv + texel * vec2(-1.0,  0.0));
  blur += texture(u_texture, v_uv + texel * vec2( 0.0,  1.0));
  blur += texture(u_texture, v_uv + texel * vec2( 0.0, -1.0));
  blur *= 0.25;
  float glow = max(0.0, dot(base.rgb, vec3(0.333)) - 0.35);
  vec3 color = base.rgb + blur.rgb * glow * (0.4 + u_intensity * 1.5);
  outColor = vec4(color, base.a);
}
`,
  glitch: `#version 300 es
precision mediump float;
in vec2 v_uv;
uniform sampler2D u_texture;
uniform float u_time;
uniform float u_intensity;
out vec4 outColor;

float rand(vec2 p) {
  return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void main() {
  float line = floor(v_uv.y * 120.0 + u_time * 7.0);
  float jitter = (rand(vec2(line, u_time)) - 0.5) * 0.02 * (0.5 + u_intensity);
  vec2 uv = vec2(v_uv.x + jitter, v_uv.y);
  vec4 color = texture(u_texture, uv);
  color.r = texture(u_texture, uv + vec2(0.003 * u_intensity, 0.0)).r;
  color.b = texture(u_texture, uv - vec2(0.003 * u_intensity, 0.0)).b;
  outColor = color;
}
`,
  chromatic: `#version 300 es
precision mediump float;
in vec2 v_uv;
uniform sampler2D u_texture;
uniform float u_intensity;
out vec4 outColor;

void main() {
  vec2 shift = vec2(0.004 * (0.3 + u_intensity), 0.0);
  float r = texture(u_texture, v_uv + shift).r;
  float g = texture(u_texture, v_uv).g;
  float b = texture(u_texture, v_uv - shift).b;
  float a = texture(u_texture, v_uv).a;
  outColor = vec4(r, g, b, a);
}
`,
  feedback: `#version 300 es
precision mediump float;
in vec2 v_uv;
uniform sampler2D u_texture;
uniform float u_time;
uniform float u_intensity;
out vec4 outColor;

void main() {
  vec2 center = v_uv - vec2(0.5);
  float zoom = 1.0 + 0.01 * (0.5 + u_intensity);
  vec2 uv = center / zoom + vec2(0.5);
  vec4 base = texture(u_texture, uv);
  float flicker = 0.96 + 0.04 * sin(u_time * 4.0);
  outColor = vec4(base.rgb * flicker, base.a);
}
`
};

export const getPostEffectShader = (name) => {
  const key = String(name || "").trim().toLowerCase();
  return POST_EFFECT_SHADERS[key] || null;
};
