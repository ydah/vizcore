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

  render({ count, speed, size, audio, time }) {
    const particleCount = clampInt(count, 200, 20_000);
    this.ensureParticles(particleCount);
    this.updateParticles(speed, audio, time);
    this.draw(size, audio);
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

  updateParticles(speed, audio, time) {
    const motion = 0.4 + clampNumber(speed, 0, 4);
    const beatBoost = audio?.beat ? 1.4 : 1.0;
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

  draw(size, audio) {
    const gl = this.gl;
    const pointSize = 1.5 + clampNumber(size, 0, 32);
    const amplitude = clampNumber(audio?.amplitude, 0, 1);
    const bass = clampNumber(audio?.bands?.low, 0, 1);
    const high = clampNumber(audio?.bands?.high, 0, 1);

    gl.useProgram(this.program);
    gl.bindBuffer(gl.ARRAY_BUFFER, this.buffer);
    gl.bufferData(gl.ARRAY_BUFFER, this.positions, gl.DYNAMIC_DRAW);
    gl.enableVertexAttribArray(this.positionLocation);
    gl.vertexAttribPointer(this.positionLocation, 2, gl.FLOAT, false, 0, 0);

    gl.uniform1f(this.pointSizeLocation, pointSize);
    gl.uniform3f(
      this.colorLocation,
      0.35 + bass * 0.45,
      0.55 + high * 0.35,
      0.95 + amplitude * 0.05
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
