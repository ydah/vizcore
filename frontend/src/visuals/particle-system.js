const PARTICLE_VERTEX_SHADER = `#version 300 es
in vec2 a_position;
uniform float u_point_size;
void main() {
  gl_Position = vec4(a_position, 0.0, 1.0);
  gl_PointSize = u_point_size;
}
`;

const PARTICLE_FRAGMENT_SHADER = `#version 300 es
precision mediump float;
uniform vec3 u_color;
out vec4 outColor;

void main() {
  vec2 center = gl_PointCoord - vec2(0.5, 0.5);
  float distance = length(center);
  float alpha = smoothstep(0.55, 0.0, distance);
  outColor = vec4(u_color, alpha);
}
`;

export const resolveParticleForces = ({ x, y, index, time, forceField, turbulence, bassExplosion, audio }) => {
  const bass = clampNumber(audio?.bands?.low, 0, 1);
  const mid = clampNumber(audio?.bands?.mid, 0, 1);
  const high = clampNumber(audio?.bands?.high, 0, 1);
  const pulse = clampNumber(audio?.beat_pulse || (audio?.beat ? 1 : 0), 0, 1);
  const field = String(forceField || "drift").toLowerCase();

  let fx = 0;
  let fy = 0;

  const radius = Math.max(0.001, Math.hypot(x, y));
  const nx = x / radius;
  const ny = y / radius;

  if (field === "vortex") {
    const strength = 0.00018 + mid * 0.00065;
    fx += -ny * strength;
    fy += nx * strength;
  } else if (field === "pulse") {
    const strength = (bass * 0.0007 + pulse * 0.0012) * (1 + clampNumber(bassExplosion, 0, 3));
    fx += nx * strength;
    fy += ny * strength;
  }

  const turb = clampNumber(turbulence, 0, 3);
  if (turb > 0) {
    const noise = Math.sin(time * (1.7 + high * 3.0) + index * 12.9898);
    fx += Math.cos(noise * 6.28318530718) * turb * 0.00018;
    fy += Math.sin(noise * 6.28318530718) * turb * 0.00018;
  }

  return [fx, fy];
};

export class ParticleSystem {
  constructor(gl, shaderManager) {
    this.gl = gl;
    this.shaderManager = shaderManager;
    this.program = this.shaderManager.getProgram(
      "particle-field",
      PARTICLE_VERTEX_SHADER,
      PARTICLE_FRAGMENT_SHADER
    );
    this.positionLocation = this.gl.getAttribLocation(this.program, "a_position");
    this.pointSizeLocation = this.gl.getUniformLocation(this.program, "u_point_size");
    this.colorLocation = this.gl.getUniformLocation(this.program, "u_color");
    this.buffer = this.gl.createBuffer();

    this.count = 0;
    this.positions = new Float32Array(0);
    this.velocities = new Float32Array(0);
  }

  render({ count, speed, size, forceField, turbulence, bassExplosion, sparkle, audio, time }) {
    const particleCount = clampInt(count, 200, 20_000);
    this.ensureParticles(particleCount);
    this.updateParticles({ speed, forceField, turbulence, bassExplosion, audio, time });
    this.draw({ size, sparkle, audio });
  }

  ensureParticles(nextCount) {
    if (this.count === nextCount) {
      return;
    }

    this.count = nextCount;
    this.positions = new Float32Array(this.count * 2);
    this.velocities = new Float32Array(this.count * 2);

    for (let index = 0; index < this.count; index += 1) {
      const x = pseudoRandom(index * 17.13) * 2 - 1;
      const y = pseudoRandom(index * 31.91) * 2 - 1;
      const vx = (pseudoRandom(index * 71.17) * 2 - 1) * 0.004;
      const vy = (pseudoRandom(index * 91.37) * 2 - 1) * 0.004;
      this.positions[index * 2] = x;
      this.positions[index * 2 + 1] = y;
      this.velocities[index * 2] = vx;
      this.velocities[index * 2 + 1] = vy;
    }
  }

  updateParticles({ speed, forceField, turbulence, bassExplosion, audio, time }) {
    const motion = 0.4 + clampNumber(speed, 0, 4);
    const beatBoost = audio?.beat || audio?.beat_pulse ? 1.4 : 1.0;
    const drift = 0.0008 + clampNumber(audio?.amplitude, 0, 1) * 0.0018;

    for (let index = 0; index < this.count; index += 1) {
      const i = index * 2;
      let x = this.positions[i];
      let y = this.positions[i + 1];
      let vx = this.velocities[i];
      let vy = this.velocities[i + 1];

      const swirl = Math.sin(time * 0.8 + index * 0.013) * drift;
      vx += swirl * 0.01;
      vy -= swirl * 0.01;

      const [fx, fy] = resolveParticleForces({ x, y, index, time, forceField, turbulence, bassExplosion, audio });
      vx += fx;
      vy += fy;
      vx = clampNumber(vx * 0.997, -0.035, 0.035);
      vy = clampNumber(vy * 0.997, -0.035, 0.035);

      x += vx * motion * beatBoost;
      y += vy * motion * beatBoost;

      if (x > 1 || x < -1) {
        vx *= -1;
        x = clampNumber(x, -1, 1);
      }
      if (y > 1 || y < -1) {
        vy *= -1;
        y = clampNumber(y, -1, 1);
      }

      this.positions[i] = x;
      this.positions[i + 1] = y;
      this.velocities[i] = vx;
      this.velocities[i + 1] = vy;
    }
  }

  draw({ size, sparkle, audio }) {
    const gl = this.gl;
    const amplitude = clampNumber(audio?.amplitude, 0, 1);
    const bass = clampNumber(audio?.bands?.low, 0, 1);
    const high = clampNumber(audio?.bands?.high, 0, 1);
    const sparkleAmount = clampNumber(sparkle, 0, 3) * high;
    const pointSize = 1.5 + clampNumber(size, 0, 32) + sparkleAmount * 1.5;

    gl.useProgram(this.program);
    gl.bindBuffer(gl.ARRAY_BUFFER, this.buffer);
    gl.bufferData(gl.ARRAY_BUFFER, this.positions, gl.DYNAMIC_DRAW);
    gl.enableVertexAttribArray(this.positionLocation);
    gl.vertexAttribPointer(this.positionLocation, 2, gl.FLOAT, false, 0, 0);

    gl.uniform1f(this.pointSizeLocation, pointSize);
    gl.uniform3f(
      this.colorLocation,
      0.35 + bass * 0.45,
      0.55 + high * 0.35 + sparkleAmount * 0.08,
      0.95 + amplitude * 0.05 + sparkleAmount * 0.05
    );
    gl.drawArrays(gl.POINTS, 0, this.count);
  }
}

const clampInt = (value, min, max) => {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) {
    return min;
  }
  return Math.round(Math.min(Math.max(numeric, min), max));
};

const clampNumber = (value, min, max) => {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) {
    return min;
  }
  return Math.min(Math.max(numeric, min), max);
};

const pseudoRandom = (seed) => {
  const value = Math.sin(seed * 12.9898) * 43758.5453;
  return value - Math.floor(value);
};
