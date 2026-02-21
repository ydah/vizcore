#version 300 es
precision mediump float;

uniform vec2 u_resolution;
uniform float u_time;
uniform float u_amplitude;
uniform float u_bass;
uniform float u_param_intensity;
uniform float u_param_bass;
uniform float u_param_flash;
out vec4 outColor;

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution.xy;
  vec2 centered = uv * 2.0 - 1.0;
  centered.x *= u_resolution.x / max(u_resolution.y, 1.0);

  float intensity = max(u_param_intensity, u_amplitude);
  float bass = max(u_param_bass, u_bass);
  float wave = sin(centered.x * 9.0 + u_time * (2.4 + bass * 7.0));
  float glow = smoothstep(0.18 + intensity * 0.2, 0.0, abs(centered.y - wave * 0.34));

  vec3 color = vec3(0.02, 0.03, 0.08);
  color += vec3(0.25, 0.72, 0.95) * glow * (0.35 + intensity * 0.9);
  color += vec3(0.95, 0.28, 0.44) * u_param_flash * 0.3;
  outColor = vec4(color, 1.0);
}
