import test from "node:test";
import assert from "node:assert/strict";

import { mappingTargetOptions, mappingTargetSignature } from "../src/mapping-target-selector.js";

test("mappingTargetOptions lists layer, shape, and custom shape targets", () => {
  const options = mappingTargetOptions([
    {
      name: "generated",
      param_schema: [{ name: "intensity" }],
      params: {
        shapes: [{ id: "ring", kind: "circle" }],
        custom_shape_controls: [
          {
            index: 0,
            name: "orbit",
            params: { radius: 80 },
            param_schema: [{ name: "twist" }],
          },
        ],
      },
    },
  ]);
  const targets = options.map((option) => option.target);

  assert.ok(targets.includes("intensity"));
  assert.ok(targets.includes("shapes.0.radius"));
  assert.ok(targets.includes("shapes.0.transform.rotate"));
  assert.ok(targets.includes("custom_shapes.0.params.radius"));
  assert.ok(targets.includes("custom_shapes.0.params.twist"));
});

test("mappingTargetSignature tracks selectable target identity", () => {
  const options = mappingTargetOptions([{ name: "logo", params: { shapes: [{ kind: "rect" }] } }]);

  assert.equal(mappingTargetSignature(options).includes("logo:shapes.0.width"), true);
});
