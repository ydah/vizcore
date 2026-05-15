import assert from "node:assert/strict";
import test from "node:test";

import {
  measureLetterSpacedText,
  normalizeLetterSpacing,
  normalizeFontFamily,
  normalizeTextAlign,
  normalizeTextLines,
  resolveLetterSpacedStartX,
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

test("normalizeTextLines trims empty lines and caps multiline content", () => {
  assert.deepEqual(normalizeTextLines(" Title \n\nSubtitle\r\n  "), ["Title", "Subtitle"]);
  assert.deepEqual(normalizeTextLines(""), []);
  assert.deepEqual(normalizeTextLines("1\n2\n3\n4\n5\n6\n7"), ["1", "2", "3", "4", "5", "6"]);
});

test("normalizeLetterSpacing clamps invalid or extreme values", () => {
  assert.equal(normalizeLetterSpacing("4.5"), 4.5);
  assert.equal(normalizeLetterSpacing(-2), 0);
  assert.equal(normalizeLetterSpacing(200), 96);
  assert.equal(normalizeLetterSpacing("bad"), 0);
});

test("letter-spaced text helpers measure and align glyph runs", () => {
  const ctx = { measureText: (char) => ({ width: char === "W" ? 20 : 10 }) };

  assert.equal(measureLetterSpacedText(ctx, "AW", 3), 33);
  assert.equal(resolveLetterSpacedStartX(ctx, "AW", 100, "left", 3), 100);
  assert.equal(resolveLetterSpacedStartX(ctx, "AW", 100, "center", 3), 83.5);
  assert.equal(resolveLetterSpacedStartX(ctx, "AW", 100, "right", 3), 67);
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
