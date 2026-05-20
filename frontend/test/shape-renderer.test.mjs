import assert from "node:assert/strict";
import test from "node:test";

import {
  resolveShapeCanvasLength,
  resolveShapeCanvasPoint,
  resolveShapeStyle,
  shapeCoordinateContext,
  shouldStrokeShape
} from "../src/visuals/shape-renderer.js";
import { describeSvgArc, svgArcPoint, svgArcSegmentCount } from "../src/visuals/svg-arc.js";

const canvas = { width: 1280, height: 720 };

test("shapeCoordinateContext keeps legacy layers compatible", () => {
  assert.deepEqual(shapeCoordinateContext({}), { units: "legacy" });
  assert.deepEqual(shapeCoordinateContext({ shape_schema_version: 2 }), { units: "logical" });
  assert.deepEqual(shapeCoordinateContext({ units: "ndc" }), { units: "ndc" });
});

test("resolveShapeCanvasPoint maps logical ndc and legacy coordinates", () => {
  assert.deepEqual(resolveShapeCanvasPoint(0, 0, { units: "logical" }, canvas), [640, 360]);
  assert.deepEqual(resolveShapeCanvasPoint(100, 80, { units: "logical" }, canvas), [740, 280]);
  assert.deepEqual(resolveShapeCanvasPoint(0.5, -0.5, { units: "ndc" }, canvas), [960, 540]);
  assert.deepEqual(resolveShapeCanvasPoint(1280, 360, { units: "legacy" }, canvas), [1280, 360]);
});

test("resolveShapeCanvasLength supports normalized and logical lengths", () => {
  assert.equal(resolveShapeCanvasLength(0.5, { units: "ndc" }, canvas), 180);
  assert.equal(resolveShapeCanvasLength(120, { units: "logical" }, canvas), 120);
});

test("resolveShapeStyle normalizes paint stroke and opacity", () => {
  assert.deepEqual(resolveShapeStyle({ fill: "transparent", stroke: 3, opacity: 2 }, "#fff"), {
    fill: null,
    strokeColor: "#fff",
    strokeWidth: 3,
    opacity: 1,
    dash: []
  });
  assert.deepEqual(resolveShapeStyle({ fill: "#0f0", stroke_width: 0, dash: [4, "bad"] }, "#fff"), {
    fill: "#0f0",
    strokeColor: "#fff",
    strokeWidth: 0,
    opacity: 1,
    dash: [4, 0]
  });
});

test("shouldStrokeShape preserves outline defaults", () => {
  assert.equal(shouldStrokeShape({ fill: "#0f0" }, "rect"), false);
  assert.equal(shouldStrokeShape({ fill: "#0f0", stroke_width: 2 }, "rect"), true);
  assert.equal(shouldStrokeShape({ fill: "#0f0" }, "line"), true);
});

test("describeSvgArc converts endpoint arcs to center parameters", () => {
  const arc = describeSvgArc({
    from: [0, 0],
    to: [100, 0],
    rx: 50,
    ry: 50,
    largeArc: false,
    sweep: true
  });

  assert.ok(arc);
  assert.equal(Math.round(arc.cx), 50);
  assert.equal(Math.round(arc.cy), 0);
  assert.equal(arc.rx, 50);
  assert.equal(arc.ry, 50);
  assert.equal(svgArcSegmentCount(arc, 16), 8);
  assert.ok(Math.abs(svgArcPoint(arc, 1)[0] - 100) < 1e-9);
  assert.ok(Math.abs(svgArcPoint(arc, 1)[1]) < 1e-9);
});
