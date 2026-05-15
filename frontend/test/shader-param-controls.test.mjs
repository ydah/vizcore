import test from "node:test";
import assert from "node:assert/strict";

import {
  applyShaderParamOverrides,
  pruneShaderParamOverrides,
  shaderParamControlEntries,
} from "../src/shader-param-controls.js";

test("shaderParamControlEntries builds numeric controls from layer schemas", () => {
  const entries = shaderParamControlEntries([
    {
      name: "liquid",
      params: { wobble: 0.4 },
      param_schema: [
        { name: "wobble", default: 0.3, min: 0, max: 2, step: 0.05 },
        { name: "", default: 1 },
      ],
    },
  ]);

  assert.deepEqual(entries, [
    {
      key: "0:liquid:wobble",
      layerKey: "0:liquid",
      layerName: "liquid",
      paramName: "wobble",
      label: "liquid.wobble",
      min: 0,
      max: 2,
      step: 0.05,
      value: 0.4,
    },
  ]);
});

test("shaderParamControlEntries prefers browser overrides and clamps values", () => {
  const entries = shaderParamControlEntries(
    [
      {
        name: "liquid",
        params: { wobble: 0.4 },
        param_schema: [{ name: "wobble", default: 0.3, min: 0, max: 2, step: 0.05 }],
      },
    ],
    { "0:liquid": { wobble: 4 } }
  );

  assert.equal(entries[0].value, 2);
});

test("applyShaderParamOverrides merges overrides without mutating layers", () => {
  const layers = [{ name: "liquid", params: { wobble: 0.4, warp: 0.2 } }];
  const next = applyShaderParamOverrides(layers, { "0:liquid": { wobble: 0.9 } });

  assert.deepEqual(next[0].params, { wobble: 0.9, warp: 0.2 });
  assert.deepEqual(layers[0].params, { wobble: 0.4, warp: 0.2 });
});

test("pruneShaderParamOverrides keeps only visible finite params", () => {
  const entries = [
    { layerKey: "0:liquid", paramName: "wobble" },
  ];
  const next = pruneShaderParamOverrides(
    {
      "0:liquid": { wobble: 0.9, warp: 0.2 },
      "1:gone": { amount: 1 },
    },
    entries
  );

  assert.deepEqual(next, { "0:liquid": { wobble: 0.9 } });
});
