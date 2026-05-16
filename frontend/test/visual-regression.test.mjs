import assert from "node:assert/strict";
import test from "node:test";

import {
  buildPresetMeshLines,
  buildShapeLines,
} from "../src/visuals/geometry.js";
import {
  lineSegmentsFingerprint,
  rasterizeLineSegments,
} from "../src/visual-regression.js";

test("rasterizeLineSegments marks finite pixels for a diagonal line", () => {
  const pixels = rasterizeLineSegments([-1, -1, 1, 1], { width: 16, height: 16 });
  const active = pixels.reduce((count, value) => count + (value > 0 ? 1 : 0), 0);

  assert.equal(active, 16);
});

test("lineSegmentsFingerprint keeps mesh geometry stable", () => {
  const points = buildPresetMeshLines({
    rotationY: 0.3,
    rotationX: 0.2,
    deform: 0.25,
    params: { geometry: "octahedron", scale: 1.1 },
  });

  assert.equal(lineSegmentsFingerprint(points), "a72ccfe9");
});

test("lineSegmentsFingerprint keeps declarative shapes stable", () => {
  const points = buildShapeLines({
    params: {
      shapes: [
        { kind: "circle", radius: 80, segments: 24 },
        { kind: "line", x1: 0, y1: 360, x2: 1280, y2: 360 },
      ],
    },
  });

  assert.equal(lineSegmentsFingerprint(points), "3399a274");
});
