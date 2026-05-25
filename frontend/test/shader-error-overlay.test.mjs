import test from "node:test";
import assert from "node:assert/strict";

import {
  SHADER_ERROR_EVENT,
  buildShaderErrorDetail,
  formatShaderErrorMessage,
  formatShaderErrorTitle,
} from "../src/shader-error-overlay.js";

test("buildShaderErrorDetail normalizes layer shader errors", () => {
  const detail = buildShaderErrorDetail({
    layer: { name: "wave", glsl: "shaders/bad.frag" },
    error: new Error("ERROR: 0:12: syntax error"),
    phase: "custom-shader",
  });

  assert.equal(SHADER_ERROR_EVENT, "vizcore:shader-error");
  assert.deepEqual(detail, {
    name: "wave",
    shader: "shaders/bad.frag",
    phase: "custom-shader",
    event: "shader_failed",
    message: "ERROR: 0:12: syntax error",
  });
});

test("shader error formatters produce compact overlay text", () => {
  const detail = {
    name: "wave",
    shader: "shaders/bad.frag",
    phase: "custom-shader",
    message: "compile failed",
  };

  assert.equal(formatShaderErrorTitle(detail), "wave (shaders/bad.frag)");
  assert.equal(formatShaderErrorMessage(detail), "[custom-shader] compile failed");
});
