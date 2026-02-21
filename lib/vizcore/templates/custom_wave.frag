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
  float wave = sin(centered.x * 10.0 + u_time * (2.0 + bass * 8.0));
  float band = smoothstep(0.15 + intensity * 0.25, 0.0, abs(centered.y - wave * 0.3));

  vec3 color = vec3(0.02, 0.04, 0.10);
  color += vec3(0.25, 0.75, 0.95) * band * (0.4 + intensity * 0.8);
  color += vec3(0.95, 0.35, 0.45) * u_param_flash * 0.25;

  outColor = vec4(color, 1.0);
}
