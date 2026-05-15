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
  liquid_wobble: `#version 300 es
precision mediump float;

uniform vec2 u_resolution;
uniform float u_time;
uniform float u_amplitude;
uniform float u_bass;
uniform float u_mid;
uniform float u_high;
uniform float u_beat;
uniform float u_beat_pulse;
uniform float u_bpm;
uniform float u_fft[32];
uniform float u_fft_size;
uniform float u_param_wobble;
uniform float u_param_warp;
uniform float u_param_distortion;
uniform float u_visual_gain;
uniform float u_wobble_amount;

out vec4 outColor;

float blob(vec2 p, float r) {
  return smoothstep(r, r - 0.035, length(p));
}

float fftSample(float t) {
  float index = clamp(floor(t * 31.0), 0.0, 31.0);
  int i = int(index);
  return u_fft[i];
}

void main() {
  vec2 uv = gl_FragCoord.xy / max(u_resolution.xy, vec2(1.0));
  vec2 p = uv * 2.0 - 1.0;
  p.x *= u_resolution.x / max(u_resolution.y, 1.0);

  float visualGain = max(u_visual_gain, 1.0);
  float globalWobble = max(u_wobble_amount, 1.0);
  float amp = clamp(u_amplitude * visualGain * 2.4, 0.0, 2.0);
  float bass = clamp(u_bass * 2.2, 0.0, 2.0);
  float pulse = max(u_beat_pulse, u_beat);

  float angle = atan(p.y, p.x) / 6.28318530718 + 0.5;
  float spectrum = fftSample(angle);

  float wobble = (0.10 + u_param_wobble + amp * 0.25 + bass * 0.18 + spectrum * 0.18) * globalWobble;
  float warp = 1.0 + u_param_warp + u_mid * 2.4;
  float distortion = 0.7 + u_param_distortion + u_high * 2.0;

  p.x += sin(p.y * 5.0 * warp + u_time * (1.1 + u_high * 5.0) + spectrum * 2.5) * wobble;
  p.y += cos(p.x * 4.0 * warp - u_time * (0.9 + u_bass * 4.0) + spectrum * 3.0) * wobble;

  float r = 0.42 + bass * 0.16 + pulse * 0.12 + spectrum * 0.08;
  float shape = blob(p, r);
  float rings = sin(length(p) * (16.0 + distortion * 5.0) - u_time * (2.0 + u_high * 8.0));
  float glow = smoothstep(0.25, 1.0, shape + rings * 0.12);

  vec3 color = vec3(0.012, 0.018, 0.035);
  color += vec3(0.12, 0.72, 1.0) * glow * (0.45 + amp);
  color += vec3(0.95, 0.24, 0.82) * shape * (0.20 + bass);
  color += vec3(1.0, 0.95, 0.8) * pulse * 0.16;

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
  ruby_crystal: `#version 300 es
precision mediump float;
uniform vec2 u_resolution;
uniform float u_time;
uniform float u_amplitude;
uniform float u_bass;
uniform float u_mid;
uniform float u_high;
uniform float u_beat;
uniform float u_beat_pulse;
uniform float u_bpm;
uniform float u_param_facets;
uniform float u_param_refraction;
uniform float u_global_intensity;
uniform float u_global_color;
out vec4 outColor;

const float PI = 3.14159265359;
const float TAU = 6.28318530718;

float sdDiamond(vec2 p) {
  p = abs(p);
  return p.x * 0.78 + p.y - 0.72;
}

float line(float value, float width) {
  return 1.0 - smoothstep(0.0, width, abs(value));
}

vec3 rubyPalette(float t) {
  vec3 deep = vec3(0.12, 0.00, 0.035);
  vec3 red = vec3(0.92, 0.05, 0.18);
  vec3 pink = vec3(1.00, 0.28, 0.52);
  vec3 white = vec3(1.00, 0.86, 0.75);
  vec3 hot = mix(red, pink, smoothstep(0.18, 0.78, t));
  return mix(deep, mix(hot, white, smoothstep(0.72, 1.0, t)), smoothstep(0.0, 1.0, t));
}

void main() {
  vec2 uv = gl_FragCoord.xy / max(u_resolution.xy, vec2(1.0));
  vec2 p = uv * 2.0 - 1.0;
  p.x *= u_resolution.x / max(u_resolution.y, 1.0);
  float globalIntensity = 1.0 + clamp(u_global_intensity, 0.0, 1.0) * 0.5;
  float globalColor = clamp(u_global_color, 0.0, 1.0);

  float facets = clamp(max(u_param_facets, 6.0), 4.0, 12.0);
  float refraction = max(u_param_refraction, 0.35);
  float tempo = max(u_bpm, 120.0) / 60.0;
  float pulse = max(u_beat, u_beat_pulse);
  float angle = atan(p.y, p.x);
  float radius = length(p);
  float spin = angle + u_time * (0.08 + tempo * 0.012) + u_mid * 0.55;
  vec2 warped = p;
  warped += vec2(cos(spin * facets), sin(spin * (facets - 1.0))) * (0.025 + u_bass * 0.055);

  float body = 1.0 - smoothstep(-0.04, 0.05, sdDiamond(warped * (0.95 - pulse * 0.08)));
  float edge = line(sdDiamond(warped), 0.035 + pulse * 0.02);
  float facetLines = line(sin(spin * facets + radius * (8.0 + u_high * 8.0)), 0.06);
  float crossCut = line(warped.x + warped.y * 0.42, 0.018) + line(warped.x - warped.y * 0.42, 0.018);
  float sparkle = pow(max(0.0, sin(spin * 3.0 + radius * 18.0 - u_time * (1.4 + u_high * 5.0))), 18.0);
  float light = clamp(body * (0.22 + facetLines * 0.34 + crossCut * 0.18) + edge * 0.9 + sparkle * (0.4 + u_high), 0.0, 1.5);
  float glow = exp(-abs(sdDiamond(warped)) * 8.0) * (0.18 + u_bass * 0.35 + pulse * 0.45);

  vec3 bg = vec3(0.018, 0.006, 0.018) + vec3(0.05, 0.00, 0.045) * (1.0 - smoothstep(0.0, 1.35, radius));
  vec3 accent = mix(vec3(1.0, 0.18, 0.32), vec3(0.12, 0.72, 1.0), globalColor);
  vec3 color = bg;
  color += rubyPalette(light + refraction * u_amplitude * 0.28) * body * globalIntensity;
  color += accent * glow * globalIntensity;
  color += mix(vec3(1.0, 0.82, 0.70), accent, 0.35) * sparkle * (0.4 + u_high) * globalIntensity;
  outColor = vec4(color, 1.0);
}
`,
  starfield: `#version 300 es
precision mediump float;
uniform vec2 u_resolution;
uniform float u_time;
uniform float u_amplitude;
uniform float u_bass;
uniform float u_mid;
uniform float u_high;
uniform float u_beat;
uniform float u_global_intensity;
uniform float u_global_color;
out vec4 outColor;

float hash11(float p) {
  return fract(sin(p * 127.1) * 43758.5453123);
}

float star(vec2 p, float size) {
  float d = length(p);
  float core = 1.0 - smoothstep(0.0, size, d);
  float rays = 1.0 - smoothstep(0.0, size * 3.0, abs(p.x) * abs(p.y));
  return core + rays * 0.08;
}

void main() {
  vec2 uv = gl_FragCoord.xy / max(u_resolution.xy, vec2(1.0));
  vec2 p = uv * 2.0 - 1.0;
  p.x *= u_resolution.x / max(u_resolution.y, 1.0);
  float globalIntensity = 1.0 + clamp(u_global_intensity, 0.0, 1.0) * 0.5;
  float globalColor = clamp(u_global_color, 0.0, 1.0);
  vec3 accentA = mix(vec3(0.20, 0.72, 1.0), vec3(1.0, 0.26, 0.58), globalColor);
  vec3 accentB = mix(vec3(1.0, 0.26, 0.58), vec3(1.0, 0.78, 0.24), globalColor);
  vec3 color = vec3(0.004, 0.008, 0.018);
  color += vec3(0.015, 0.02, 0.05) * (1.0 - smoothstep(0.0, 1.4, length(p)));

  float speed = 0.10 + u_bass * 0.65 + u_amplitude * 0.25;
  for (int i = 0; i < 56; i++) {
    float fi = float(i);
    vec2 seed = vec2(hash11(fi + 11.0), hash11(fi + 37.0)) * 2.0 - 1.0;
    float depth = fract(hash11(fi + 73.0) - u_time * speed * (0.35 + hash11(fi + 5.0)));
    vec2 pos = seed / max(depth, 0.08);
    float size = (1.0 - depth) * (0.004 + u_high * 0.011 + u_beat * 0.006);
    float trail = star(p - pos, size);
    vec3 tint = mix(accentA, accentB, hash11(fi + 101.0));
    color += tint * trail * (0.18 + (1.0 - depth) * 0.85 + u_beat * 0.5) * globalIntensity;
  }

  float warp = sin(length(p) * (12.0 + u_mid * 8.0) - u_time * (1.0 + u_high * 3.0));
  color += vec3(0.08, 0.10, 0.18) * smoothstep(0.94, 1.0, warp) * (0.08 + u_mid * 0.22);
  outColor = vec4(color, 1.0);
}
`,
  waveform_ribbon: `#version 300 es
precision mediump float;
uniform vec2 u_resolution;
uniform float u_time;
uniform float u_amplitude;
uniform float u_bass;
uniform float u_mid;
uniform float u_high;
uniform float u_beat;
uniform float u_beat_pulse;
uniform float u_fft[32];
uniform float u_global_intensity;
uniform float u_global_color;
out vec4 outColor;

float fftSample(float t) {
  float index = clamp(floor(t * 31.0), 0.0, 31.0);
  return u_fft[int(index)];
}

float line(float y, float center, float width) {
  return 1.0 - smoothstep(0.0, width, abs(y - center));
}

void main() {
  vec2 uv = gl_FragCoord.xy / max(u_resolution.xy, vec2(1.0));
  float globalIntensity = 1.0 + clamp(u_global_intensity, 0.0, 1.0) * 0.5;
  float globalColor = clamp(u_global_color, 0.0, 1.0);
  float spectrum = fftSample(uv.x);
  float phase = uv.x * 18.8495559215 + u_time * (1.2 + u_mid * 3.5);
  float center = 0.5 + sin(phase) * (0.035 + u_bass * 0.08) + sin(phase * 0.43 - u_time) * 0.035;
  float width = 0.018 + u_amplitude * 0.055 + spectrum * 0.16 + u_beat_pulse * 0.025;
  float primary = line(uv.y, center, width);
  float echoA = line(uv.y, center + 0.16 + u_high * 0.08, width * 0.62);
  float echoB = line(uv.y, center - 0.15 - u_bass * 0.06, width * 0.58);
  float grid = smoothstep(0.012, 0.0, abs(fract(uv.x * 32.0) - 0.5)) * 0.08;

  vec3 bg = vec3(0.006, 0.012, 0.026);
  bg += vec3(0.02, 0.03, 0.055) * smoothstep(0.9, 0.0, abs(uv.y - 0.5));
  vec3 primaryColor = mix(vec3(0.08, 0.92, 1.0), vec3(1.0, 0.18, 0.58), globalColor);
  vec3 echoColor = mix(vec3(1.0, 0.18, 0.58), vec3(0.95, 0.78, 0.28), globalColor);
  vec3 bassColor = mix(vec3(0.95, 0.78, 0.28), vec3(0.22, 0.78, 1.0), globalColor);
  vec3 ribbon = primaryColor * primary;
  ribbon += echoColor * echoA * (0.5 + u_high);
  ribbon += bassColor * echoB * (0.35 + u_bass);
  ribbon += vec3(0.7, 0.85, 1.0) * primary * u_beat * 0.35;

  vec3 color = bg + ribbon * (0.65 + spectrum * 0.75 + u_amplitude * 0.5) * globalIntensity;
  color += vec3(0.18, 0.28, 0.44) * grid * (0.2 + spectrum);
  outColor = vec4(color, 1.0);
}
`,
  unyo_geometry: `#version 300 es
precision mediump float;

uniform vec2 u_resolution;
uniform float u_time;
uniform float u_amplitude;
uniform float u_bass;
uniform float u_mid;
uniform float u_high;
uniform float u_beat;
uniform float u_beat_pulse;
uniform float u_bpm;
uniform float u_fft[32];
uniform float u_param_seed;
uniform float u_param_sides;
uniform float u_param_scale;
uniform float u_param_wobble;
uniform float u_param_twist;
uniform float u_param_pulse;
uniform float u_param_kick;
uniform float u_param_snare;
uniform float u_param_line_glow;

out vec4 outColor;

const float PI = 3.14159265359;
const float TAU = 6.28318530718;

float hash11(float p) {
  return fract(sin(p * 127.1) * 43758.5453123);
}

float fftSample(float t) {
  float index = clamp(floor(fract(t) * 31.0), 0.0, 31.0);
  return u_fft[int(index)];
}

mat2 rotate2d(float angle) {
  float s = sin(angle);
  float c = cos(angle);
  return mat2(c, -s, s, c);
}

float sdRegularPolygon(vec2 p, float radius, float sides) {
  float angle = PI / sides;
  float sector = TAU / sides;
  vec2 axis = vec2(cos(angle), sin(angle));
  float folded = mod(atan(p.x, p.y), sector) - angle;
  vec2 q = length(p) * vec2(cos(folded), abs(sin(folded)));
  return dot(q - vec2(radius, 0.0), axis);
}

vec3 palette(float t) {
  vec3 cyan = vec3(0.02, 0.88, 0.98);
  vec3 pink = vec3(1.00, 0.20, 0.58);
  vec3 amber = vec3(1.00, 0.76, 0.22);
  vec3 green = vec3(0.26, 0.96, 0.54);
  vec3 first = mix(cyan, pink, smoothstep(0.0, 0.45, t));
  vec3 second = mix(amber, green, smoothstep(0.55, 1.0, t));
  return mix(first, second, smoothstep(0.35, 0.75, t));
}

void main() {
  vec2 uv = gl_FragCoord.xy / max(u_resolution.xy, vec2(1.0));
  vec2 p = uv * 2.0 - 1.0;
  p.x *= u_resolution.x / max(u_resolution.y, 1.0);

  float seed = floor(max(u_param_seed, 0.0));
  float sideDrift = floor(mod(seed, 5.0));
  float sides = clamp(floor(max(u_param_sides, 7.0) + sideDrift - 2.0), 4.0, 12.0);
  float scale = clamp(max(u_param_scale, 0.95), 0.55, 1.45);
  float rawPulse = clamp(max(max(u_param_pulse, u_beat_pulse), u_beat), 0.0, 1.8);
  float rawKick = clamp(max(u_param_kick, u_bass * 1.15), 0.0, 1.8);
  float rawSnare = clamp(max(u_param_snare, u_high * 0.9), 0.0, 1.4);
  float soundEnergy = max(max(u_amplitude, rawKick * 0.7), rawSnare * 0.55);
  float soundGate = smoothstep(0.006, 0.035, soundEnergy);
  float motionTime = u_time * soundGate;
  float pulse = rawPulse * soundGate;
  float kick = rawKick * soundGate;
  float snare = rawSnare * soundGate;
  float drumHit = max(pulse, kick);
  float wobble = max(u_param_wobble, 0.3) + kick * 0.35;
  float twist = max(u_param_twist, 0.35) + snare * 0.38;
  float lineGlow = max(u_param_line_glow, 0.16);
  float tempo = max(u_bpm, 120.0) / 60.0;

  vec2 bodyDrift = vec2(
    sin(motionTime * (0.65 + tempo * 0.08) + seed * 1.7),
    cos(motionTime * (0.58 + tempo * 0.07) + seed * 1.1)
  ) * soundGate * (0.035 + drumHit * 0.075);
  p -= bodyDrift;

  float radius = length(p);
  float angle = atan(p.y, p.x);
  float spectrum = fftSample(angle / TAU + 0.5 + seed * 0.017);
  float activeSpectrum = spectrum * soundGate;
  float breathing = 1.0 + drumHit * 0.22 + u_bass * soundGate * 0.12 + activeSpectrum * 0.09;
  float organic = sin(angle * (sides + 1.0) + motionTime * (1.0 + u_mid * 2.2) + seed);
  organic += sin(angle * (sides * 2.0 - 1.0) - motionTime * (0.8 + u_high * 2.8 + snare * 1.4) + seed * 0.7) * (0.55 + kick * 0.45);
  organic += activeSpectrum * (1.1 + drumHit * 0.7);

  float twistAngle = radius * twist * (0.9 + u_mid * 1.7 + drumHit * 0.55) + organic * wobble * 0.14;
  vec2 warped = rotate2d(twistAngle) * p;
  warped *= 1.0 + organic * wobble * 0.095 + kick * 0.025;

  float baseRadius = 0.60 * scale * breathing;
  float d = sdRegularPolygon(warped, baseRadius, sides);
  float inside = 1.0 - smoothstep(-0.006, 0.024, d);
  float edge = smoothstep(0.025, 0.0, abs(d));
  float glow = exp(-abs(d) * 13.0) * (0.18 + drumHit * 0.68 + u_amplitude * 0.32);

  float warpedAngle = atan(warped.y, warped.x);
  float warpedRadius = length(warped);
  float spokes = smoothstep(0.06, 0.0, abs(sin(warpedAngle * sides + motionTime * (0.7 + u_high * 1.6 + snare * 1.2))));
  float rings = smoothstep(0.055, 0.0, abs(sin(warpedRadius * (24.0 + sides * 1.7 + kick * 7.0) - motionTime * tempo * (1.7 + drumHit * 1.1))));
  float core = smoothstep(0.14, 0.0, abs(warpedRadius - baseRadius * (0.32 + drumHit * 0.11)));
  float innerLines = inside * max(spokes * 0.72, max(rings * 0.5, core * 0.62)) * lineGlow;

  vec3 bg = vec3(0.012, 0.016, 0.028);
  bg += vec3(0.018, 0.024, 0.040) * smoothstep(1.25, 0.05, length(p));
  bg += vec3(0.04, 0.028, 0.065) * (0.06 + u_mid * 0.12) * smoothstep(1.0, 0.0, radius);

  vec3 shapeColor = palette(fract(seed * 0.071 + warpedAngle / TAU + u_high * 0.16));
  vec3 innerColor = palette(fract(seed * 0.11 + 0.45 + warpedRadius));
  shapeColor *= 0.78 + u_amplitude * 0.42 + drumHit * 0.46 + snare * 0.18;

  vec3 color = bg;
  color += shapeColor * glow;
  color += shapeColor * edge * (1.2 + drumHit * 0.72);
  color += innerColor * innerLines * (0.8 + u_high * 0.75 + snare * 0.35);
  color += shapeColor * inside * 0.10;
  color += vec3(1.0, 0.96, 0.86) * drumHit * 0.06;

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
