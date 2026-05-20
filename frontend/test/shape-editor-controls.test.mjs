import test from "node:test";
import assert from "node:assert/strict";

import {
  applyShapeEditorOverrides,
  normalizeShapeEditorPatch,
  pruneShapeEditorOverrides,
  shapeEditorEntries,
} from "../src/shape-editor-controls.js";

test("shapeEditorEntries builds editable shape rows", () => {
  const entries = shapeEditorEntries([
    {
      name: "logo",
      params: {
        shapes: [
          {
            id: "ring",
            kind: "circle",
            radius: 80,
            fill: "#22d3ee",
            stroke_color: "#ffffff",
            stroke_width: 2,
            transform: { translate: { x: 12, y: -4 }, rotate: 15, scale: { x: 1.2, y: 0.8 } },
          },
        ],
      },
    },
  ]);

  assert.equal(entries.length, 1);
  assert.equal(entries[0].key, "0:logo:shapes.0");
  assert.equal(entries[0].label, "logo.ring");
  assert.deepEqual(entries[0].values, {
    kind: "circle",
    translateX: 12,
    translateY: -4,
    rotate: 15,
    scaleX: 1.2,
    scaleY: 0.8,
    opacity: 1,
    fill: "#22d3ee",
    fillEnabled: true,
    strokeColor: "#ffffff",
    strokeColorEnabled: true,
    strokeWidth: 2,
  });
});

test("applyShapeEditorOverrides merges primitive, style, and transform edits", () => {
  const layers = [
    {
      name: "logo",
      params: {
        shapes: [{ kind: "circle", radius: 80, transform: { translate: { x: 0, y: 0 } } }],
      },
    },
  ];
  const patch = normalizeShapeEditorPatch({
    kind: "rect",
    translateX: 20,
    translateY: 10,
    rotate: 30,
    scaleX: 1.5,
    scaleY: 0.5,
    opacity: 0.6,
    fill: "#ff0000",
    fillEnabled: true,
    strokeColor: "#00ff00",
    strokeColorEnabled: true,
    strokeWidth: 3,
  });

  const next = applyShapeEditorOverrides(layers, { "0:logo": { 0: patch } });

  assert.deepEqual(next[0].params.shapes[0], {
    kind: "rect",
    radius: 80,
    opacity: 0.6,
    fill: "#ff0000",
    stroke_color: "#00ff00",
    stroke_width: 3,
    transform: {
      translate: { x: 20, y: 10 },
      rotate: 30,
      scale: { x: 1.5, y: 0.5 },
    },
  });
  assert.equal(layers[0].params.shapes[0].kind, "circle");
});

test("pruneShapeEditorOverrides keeps only visible shape edits", () => {
  const next = pruneShapeEditorOverrides(
    {
      "0:logo": { 0: { kind: "rect" }, 2: { kind: "star" } },
      "1:gone": { 0: { kind: "line" } },
    },
    [{ layerKey: "0:logo", shapeIndex: 0 }]
  );

  assert.deepEqual(next, { "0:logo": { 0: { kind: "rect" } } });
});
