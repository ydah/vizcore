import test from "node:test";
import assert from "node:assert/strict";

import {
  customShapeParamControlEntries,
  customShapeParamMessage,
  pruneCustomShapeParamOverrides,
} from "../src/custom-shape-param-controls.js";

test("customShapeParamControlEntries builds controls from dynamic custom shape metadata", () => {
  const entries = customShapeParamControlEntries([
    {
      name: "generated",
      params: {
        custom_shape_controls: [
          {
            index: 0,
            name: "orbit",
            params: { radius: 80 },
            param_schema: [{ name: "radius", default: 64, min: 10, max: 200, step: 1 }],
            shape_indices: [0, 1],
          },
        ],
      },
    },
  ]);

  assert.deepEqual(entries, [
    {
      key: "0:generated:custom_shapes.0.params.radius",
      layerKey: "0:generated",
      layerName: "generated",
      customShapeIndex: 0,
      customShapeName: "orbit",
      paramName: "radius",
      label: "generated.orbit.radius",
      target: "custom_shapes.0.params.radius",
      min: 10,
      max: 200,
      step: 1,
      value: 80,
    },
  ]);
});

test("customShapeParamControlEntries prefers local overrides", () => {
  const entries = customShapeParamControlEntries(
    [
      {
        name: "generated",
        params: {
          custom_shape_controls: [{ index: 0, name: "orbit", params: { radius: 80 } }],
        },
      },
    ],
    { "0:generated": { 0: { radius: 400 } } }
  );

  assert.equal(entries[0].value, 160);
});

test("pruneCustomShapeParamOverrides keeps visible finite params", () => {
  const next = pruneCustomShapeParamOverrides(
    {
      "0:generated": { 0: { radius: 88, twist: 2 }, 1: { radius: 10 } },
    },
    [{ layerKey: "0:generated", customShapeIndex: 0, paramName: "radius" }]
  );

  assert.deepEqual(next, { "0:generated": { 0: { radius: 88 } } });
});

test("customShapeParamMessage clamps outgoing values", () => {
  const payload = customShapeParamMessage(
    { layerName: "generated", customShapeIndex: 0, paramName: "radius", min: 10, max: 200, value: 80 },
    500
  );

  assert.deepEqual(payload, {
    layer: "generated",
    custom_shape_index: 0,
    param: "radius",
    value: 200,
  });
});
