import test from "node:test";
import assert from "node:assert/strict";

import { resolveParticleForces } from "../src/visuals/particle-system.js";

const audio = {
  amplitude: 0.7,
  beat_pulse: 1,
  bands: { low: 0.8, mid: 0.5, high: 0.3 },
};

test("resolveParticleForces returns finite force values", () => {
  const force = resolveParticleForces({
    x: 0.5,
    y: 0.2,
    index: 1,
    time: 1,
    forceField: "vortex",
    turbulence: 1,
    bassExplosion: 1,
    audio,
  });

  assert.equal(force.length, 2);
  assert.ok(force.every(Number.isFinite));
});

test("vortex force adds tangential motion", () => {
  const [fx, fy] = resolveParticleForces({
    x: 0.5,
    y: 0,
    index: 1,
    time: 1,
    forceField: "vortex",
    turbulence: 0,
    bassExplosion: 0,
    audio,
  });

  assert.ok(Math.abs(fx) < 0.000001);
  assert.ok(fy > 0);
});

test("pulse force pushes outward", () => {
  const [fx, fy] = resolveParticleForces({
    x: 0.5,
    y: 0,
    index: 1,
    time: 1,
    forceField: "pulse",
    turbulence: 0,
    bassExplosion: 1,
    audio,
  });

  assert.ok(fx > 0);
  assert.equal(Math.abs(fy) < 0.000001, true);
});
