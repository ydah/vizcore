import assert from "node:assert/strict";
import test from "node:test";

import {
  normalizeFontFamily,
  normalizeTextAlign,
  resolveTextX
} from "../src/visuals/text-renderer.js";

test("normalizeTextAlign accepts supported canvas alignments", () => {
  assert.equal(normalizeTextAlign("left"), "left");
  assert.equal(normalizeTextAlign("right"), "right");
  assert.equal(normalizeTextAlign("center"), "center");
  assert.equal(normalizeTextAlign("unsupported"), "center");
});

test("resolveTextX positions text by alignment", () => {
  assert.equal(resolveTextX(1000, "left"), 120);
  assert.equal(resolveTextX(1000, "center"), 500);
  assert.equal(resolveTextX(1000, "right"), 880);
});

test("normalizeFontFamily appends fallback fonts", () => {
  assert.equal(
    normalizeFontFamily("Inter Black"),
    "\"Inter Black\", \"IBM Plex Sans\", \"Noto Sans JP\", sans-serif"
  );
  assert.equal(
    normalizeFontFamily("\"Noto Sans JP\", sans-serif"),
    "\"Noto Sans JP\", sans-serif, \"IBM Plex Sans\", \"Noto Sans JP\", sans-serif"
  );
});
