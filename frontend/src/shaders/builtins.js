const DEFAULT_FRAGMENT_SHADER = `#version 300 es
precision mediump float;
uniform vec2 u_resolution;
uniform float u_time;
uniform float u_amplitude;
uniform float u_bass;
uniform float u_mid;
uniform float u_high;
uniform float u_beat;
uniform float u_bpm;
out vec4 outColor;

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution.xy;
  float pulse = 0.5 + 0.5 * sin(u_time * 1.8 + uv.x * 5.0);
  vec3 color = vec3(0.08, 0.12, 0.24);
  color += vec3(u_bass, u_mid, u_high) * 0.25;
  color += pulse * (0.08 + u_amplitude * 0.25);
  color += vec3(u_beat * 0.15);
  outColor = vec4(color, 1.0);
}
`;

export const BUILTIN_FRAGMENT_SHADERS = {
  default: DEFAULT_FRAGMENT_SHADER,
  gradient_pulse: `#version 300 es
precision mediump float;
uniform vec2 u_resolution;
uniform float u_time;
uniform float u_amplitude;
uniform float u_bass;
uniform float u_mid;
uniform float u_high;
uniform float u_beat;
out vec4 outColor;

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution.xy;
  vec3 baseA = vec3(0.04, 0.08, 0.15);
  vec3 baseB = vec3(0.20 + u_high * 0.35, 0.16 + u_mid * 0.3, 0.28 + u_bass * 0.25);
  float sweep = 0.5 + 0.5 * sin(u_time * 2.4 + uv.y * 8.0);
  float flash = u_beat * 0.35;
  vec3 color = mix(baseA, baseB, uv.y + sweep * 0.2);
  color += vec3(flash + u_amplitude * 0.2);
  outColor = vec4(color, 1.0);
}
`,
  bass_tunnel: `#version 300 es
precision mediump float;
uniform vec2 u_resolution;
uniform float u_time;
uniform float u_bass;
uniform float u_mid;
uniform float u_high;
uniform float u_amplitude;
out vec4 outColor;

void main() {
  vec2 uv = (gl_FragCoord.xy / u_resolution.xy) * 2.0 - 1.0;
  uv.x *= u_resolution.x / max(u_resolution.y, 1.0);
  float r = length(uv);
  float angle = atan(uv.y, uv.x);
  float tunnel = sin(angle * 6.0 + u_time * (2.0 + u_bass * 6.0));
  float rings = smoothstep(0.8, 0.0, abs(r - (0.3 + 0.2 * tunnel)));
  vec3 color = vec3(0.03, 0.05, 0.08);
  color += vec3(0.65, 0.45, 0.2) * rings * (0.4 + u_bass * 0.8);
  color += vec3(0.2, 0.55, 0.9) * (1.0 - r) * (0.2 + u_high * 0.6);
  color += u_amplitude * 0.08;
  outColor = vec4(color, 1.0);
}
`,
  neon_grid: `#version 300 es
precision mediump float;
uniform vec2 u_resolution;
uniform float u_time;
uniform float u_bass;
uniform float u_mid;
uniform float u_high;
uniform float u_beat;
out vec4 outColor;

float line(float p, float width) {
  return smoothstep(width, 0.0, abs(fract(p) - 0.5));
}

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution.xy;
  float zoom = 8.0 + u_bass * 12.0;
  float move = u_time * (0.5 + u_mid * 2.0);
  float gx = line(uv.x * zoom + move, 0.03);
  float gy = line(uv.y * zoom - move, 0.03);
  float glow = max(gx, gy);
  vec3 color = vec3(0.01, 0.02, 0.04);
  color += vec3(0.1, 0.95, 0.85) * glow * (0.5 + u_high * 0.7);
  color += vec3(u_beat * 0.2);
  outColor = vec4(color, 1.0);
}
`,
  kaleidoscope: `#version 300 es
precision mediump float;
uniform vec2 u_resolution;
uniform float u_time;
uniform float u_amplitude;
uniform float u_bass;
uniform float u_mid;
uniform float u_high;
out vec4 outColor;

void main() {
  vec2 uv = (gl_FragCoord.xy / u_resolution.xy) * 2.0 - 1.0;
  uv.x *= u_resolution.x / max(u_resolution.y, 1.0);
  float slices = 6.0 + floor(u_mid * 6.0);
  float angle = atan(uv.y, uv.x);
  float radius = length(uv);
  angle = mod(angle, 6.28318530718 / slices);
  angle = abs(angle - 3.14159265359 / slices);
  vec2 p = vec2(cos(angle), sin(angle)) * radius;
  float wave = sin(p.x * 16.0 + u_time * (1.5 + u_high * 5.0));
  vec3 color = vec3(0.04, 0.02, 0.08);
  color += vec3(0.8, 0.3, 0.95) * (0.5 + 0.5 * wave) * (0.3 + u_amplitude * 0.7);
  color += vec3(0.2, 0.6, 0.95) * (1.0 - radius) * (0.2 + u_bass * 0.6);
  outColor = vec4(color, 1.0);
}
`,
  spectrum_rings: `#version 300 es
precision mediump float;
uniform vec2 u_resolution;
uniform float u_time;
uniform float u_bass;
uniform float u_mid;
uniform float u_high;
uniform float u_bpm;
out vec4 outColor;

void main() {
  vec2 uv = (gl_FragCoord.xy / u_resolution.xy) * 2.0 - 1.0;
  uv.x *= u_resolution.x / max(u_resolution.y, 1.0);
  float r = length(uv);
  float bpmPhase = u_time * (u_bpm / 60.0);
  float rings = sin((r * 18.0) - bpmPhase * 6.28318530718);
  float pulse = smoothstep(0.15, 0.0, abs(rings));
  vec3 color = vec3(0.02, 0.02, 0.05);
  color += vec3(0.95, 0.3, 0.22) * pulse * (0.2 + u_bass * 0.9);
  color += vec3(0.2, 0.55, 0.95) * pulse * (0.2 + u_mid * 0.6);
  color += vec3(0.8, 0.85, 1.0) * pulse * (0.1 + u_high * 0.4);
  outColor = vec4(color, 1.0);
}
`,
  audio_bars: `#version 300 es
precision mediump float;
uniform vec2 u_resolution;
uniform float u_time;
uniform float u_amplitude;
uniform float u_bass;
uniform float u_mid;
uniform float u_high;
uniform float u_beat;
uniform float u_param_bar_count;
uniform float u_param_floor_glow;
out vec4 outColor;

float hash11(float p) {
  return fract(sin(p * 127.1) * 43758.5453123);
}

void main() {
  vec2 uv = gl_FragCoord.xy / max(u_resolution.xy, vec2(1.0));
  float bars = floor(max(u_param_bar_count, 18.0));
  float col = uv.x * bars;
  float id = floor(col);
  float x = fract(col) - 0.5;
  float gap = 0.13;
  float barMask = smoothstep(0.48, 0.48 - 0.02, abs(x)) * (1.0 - smoothstep(0.48 - gap, 0.48 - gap - 0.02, abs(x)));

  float n = hash11(id + 1.7);
  float region = id / max(bars - 1.0, 1.0);
  float lowW = 1.0 - smoothstep(0.0, 0.42, region);
  float highW = smoothstep(0.58, 1.0, region);
  float midW = max(0.0, 1.0 - lowW - highW);
  float ripple = 0.5 + 0.5 * sin(u_time * (1.8 + n * 2.4) + id * (0.35 + n * 0.4));
  float spark = 0.5 + 0.5 * sin(u_time * 7.0 + id * 1.31);
  float height = 0.05
    + u_amplitude * (0.14 + n * 0.18)
    + lowW * u_bass * (0.22 + 0.14 * ripple)
    + midW * u_mid * (0.20 + 0.12 * ripple)
    + highW * u_high * (0.18 + 0.16 * ripple)
    + u_beat * (0.04 + 0.04 * spark);
  height = clamp(height, 0.03, 0.95);

  float fill = smoothstep(0.0, 0.01, height - uv.y);
  float topGlow = exp(-abs(uv.y - height) * 180.0) * 0.4;
  float floorGlow = exp(-uv.y * 20.0) * (0.08 + max(u_param_floor_glow, 0.0));

  vec3 bg = vec3(0.012, 0.018, 0.032);
  bg += vec3(0.02, 0.03, 0.055) * floorGlow;

  vec3 barA = vec3(0.09, 0.88, 0.95);
  vec3 barB = vec3(0.92, 0.32, 1.0);
  vec3 barColor = mix(barA, barB, smoothstep(0.2, 0.95, region));
  barColor *= 0.65 + 0.75 * (lowW * u_bass + midW * u_mid + highW * u_high + u_amplitude * 0.35);
  barColor += vec3(0.9, 0.95, 1.0) * topGlow;

  float active = barMask * fill;
  vec3 color = bg + barColor * active;
  color += barColor * barMask * topGlow * 0.45;

  outColor = vec4(color, 1.0);
}
`,
  glitch_flash: `#version 300 es
precision mediump float;
uniform vec2 u_resolution;
uniform float u_time;
uniform float u_amplitude;
uniform float u_beat;
uniform float u_high;
uniform float u_param_intensity;
out vec4 outColor;

float random(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution.xy;
  float intensity = max(u_param_intensity, 0.15 + u_amplitude * 0.8);
  float line = step(0.92, fract(uv.y * (20.0 + u_high * 90.0) + u_time * 6.0));
  float noise = random(vec2(floor(uv.y * 140.0), floor(u_time * 8.0)));
  float flash = min(1.0, u_beat * 1.3 + noise * intensity * 0.35);
  vec3 color = vec3(0.03, 0.04, 0.08);
  color += vec3(0.1, 0.9, 0.95) * line * intensity;
  color += vec3(0.95, 0.2, 0.4) * flash;
  outColor = vec4(color, 1.0);
}
`
};

export const getBuiltinShader = (name) => {
  const key = String(name || "").trim();
  if (!key) {
    return BUILTIN_FRAGMENT_SHADERS.default;
  }
  return BUILTIN_FRAGMENT_SHADERS[key] || BUILTIN_FRAGMENT_SHADERS.default;
};
