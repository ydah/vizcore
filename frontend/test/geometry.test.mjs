import test from "node:test";
import assert from "node:assert/strict";

import {
  buildPresetMeshLines,
  buildRadialBlobLines,
  buildShapeLines,
  buildWaveformLines,
  estimateDeformFromSpectrum,
  normalizeWaveformStyle,
} from "../src/visuals/geometry.js";

test("buildRadialBlobLines returns line segment coordinates", () => {
  const points = buildRadialBlobLines({
    time: 1.0,
    params: { segments: 32, radius: 0.4, wobble: 0.2 },
    audio: {
      amplitude: 0.5,
      bands: { low: 0.7, mid: 0.2, high: 0.1 },
      fft: Array.from({ length: 32 }, () => 0.2),
    },
  });

  assert.equal(points.length, 32 * 4);
  assert.ok(points.every((value) => Number.isFinite(value)));
});

test("buildPresetMeshLines returns icosahedron wireframe coordinates", () => {
  const points = buildPresetMeshLines({
    rotationY: 0.25,
    rotationX: 0.15,
    deform: 0.4,
    params: { geometry: "icosahedron", scale: 1.2 },
  });

  assert.equal(points.length, 30 * 4);
  assert.ok(points.every((value) => Number.isFinite(value)));
  assert.ok(points.every((value) => value >= -1 && value <= 1));
});

test("buildPresetMeshLines supports compact mesh presets", () => {
  const tetrahedron = buildPresetMeshLines({ params: { geometry: "tetrahedron" } });
  const octahedron = buildPresetMeshLines({ params: { geometry: "octahedron" } });
  const cube = buildPresetMeshLines({ params: { geometry: "cube" } });

  assert.equal(tetrahedron.length, 6 * 4);
  assert.equal(octahedron.length, 12 * 4);
  assert.equal(cube.length, 12 * 4);
});

test("estimateDeformFromSpectrum averages numeric spectrum values", () => {
  const deform = estimateDeformFromSpectrum([0.2, 0.4]);

  assert.ok(Math.abs(deform - 0.3) < 0.00001);
});

test("buildWaveformLines returns finite line coordinates", () => {
  const points = buildWaveformLines({
    time: 0.5,
    params: { detail: 32, height: 0.5, style: "line" },
    audio: {
      amplitude: 0.6,
      fft: Array.from({ length: 32 }, (_, index) => index / 32),
    },
  });

  assert.equal(points.length, (32 - 1) * 4);
  assert.ok(points.every((value) => Number.isFinite(value)));
  assert.ok(points.every((value) => value >= -1 && value <= 1));
});

test("buildWaveformLines adds mirrored and ribbon segments", () => {
  const line = buildWaveformLines({
    params: { detail: 24, style: "line" },
    audio: { amplitude: 0.4, fft: [0.2, 0.4, 0.6] },
  });
  const ribbon = buildWaveformLines({
    params: { detail: 24, style: "ribbon" },
    audio: { amplitude: 0.4, fft: [0.2, 0.4, 0.6] },
  });

  assert.ok(ribbon.length > line.length);
});

test("normalizeWaveformStyle resolves supported styles", () => {
  assert.equal(normalizeWaveformStyle("mirror"), "mirror");
  assert.equal(normalizeWaveformStyle("ribbon"), "ribbon");
  assert.equal(normalizeWaveformStyle("unknown"), "line");
});

test("buildShapeLines returns circle and line coordinates", () => {
  const points = buildShapeLines({
    params: {
      shapes: [
        { kind: "circle", count: 2, radius: 120, segments: 24 },
        { kind: "line", x1: 0, y1: 360, x2: 1280, y2: 360 },
      ],
    },
  });

  assert.equal(points.length, (2 * 24 * 4) + 4);
  assert.ok(points.every((value) => Number.isFinite(value)));
});

test("buildShapeLines flattens extended shape primitives", () => {
  const points = buildShapeLines({
    params: {
      shape_schema_version: 2,
      shapes: [
        { kind: "rect", width: 320, height: 160, transform: { translate: { x: 40, y: 0 }, scale: 1.1 } },
        { kind: "polygon", points: [[0, 120], [-104, -60], [104, -60]] },
        { kind: "polyline", points: [[-120, 0], [0, 80], [120, 0]] },
        { kind: "path", detail: 8, commands: [["M", 0, 100], ["Q", 80, 140, 120, 40], ["Z"]] },
        { kind: "star", points: 5, radius: 80, inner_radius: 32 },
      ],
    },
  });

  assert.equal(points.length, 112);
  assert.ok(points.every((value) => Number.isFinite(value)));
  assert.ok(points.every((value) => value >= -1.2 && value <= 1.2));
});

test("buildShapeLines flattens arc path commands", () => {
  const points = buildShapeLines({
    params: {
      shape_schema_version: 2,
      shapes: [
        { kind: "path", detail: 16, commands: [["M", 0, 0], ["A", 50, 50, 0, 0, 1, 100, 0]] },
      ],
    },
  });

  assert.equal(points.length, 32);
  assert.ok(points.every((value) => Number.isFinite(value)));
  assert.notEqual(points[3], 0);
});

test("buildShapeLines respects path max_segments", () => {
  const points = buildShapeLines({
    params: {
      shape_schema_version: 2,
      shapes: [
        {
          kind: "path",
          detail: 16,
          max_segments: 3,
          commands: [["M", 0, 0], ["C", 20, 80, 80, -80, 100, 0], ["L", 120, 0]],
        },
      ],
    },
  });

  assert.equal(points.length, 12);
  assert.ok(points.every((value) => Number.isFinite(value)));
});

test("buildShapeLines ignores unknown shapes", () => {
  assert.deepEqual(buildShapeLines({ params: { shapes: [{ kind: "triangle" }] } }), []);
});
