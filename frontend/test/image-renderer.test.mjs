import assert from "node:assert/strict";
import test from "node:test";

import {
  isVideoSource,
  normalizeImageFit,
  normalizeInvert,
  normalizePlaybackRate,
  normalizeRotation,
  normalizeScale,
  resolveMediaDimensions,
  resolveImageRect,
  resolveMediaSource,
} from "../src/visuals/image-renderer.js";

test("resolveMediaSource trims empty sources", () => {
  assert.equal(resolveMediaSource(" data:image/svg+xml;base64,abc "), "data:image/svg+xml;base64,abc");
  assert.equal(resolveMediaSource(" "), null);
});

test("normalizeImageFit accepts contain cover and stretch", () => {
  assert.equal(normalizeImageFit("cover"), "cover");
  assert.equal(normalizeImageFit("stretch"), "stretch");
  assert.equal(normalizeImageFit("unknown"), "contain");
});

test("normalizers clamp image scale and rotation", () => {
  assert.equal(normalizeScale("2.5"), 2.5);
  assert.equal(normalizeScale(-1), 0.01);
  assert.equal(normalizeScale(99), 8);
  assert.equal(normalizeRotation("0.25"), 0.25);
  assert.equal(normalizeRotation("bad"), 0);
  assert.equal(normalizePlaybackRate("2.5"), 2.5);
  assert.equal(normalizePlaybackRate(9), 4);
  assert.equal(normalizePlaybackRate("bad"), 1);
  assert.equal(normalizeInvert("0.75"), 0.75);
  assert.equal(normalizeInvert(2), 1);
  assert.equal(normalizeInvert("bad"), 0);
});

test("resolveImageRect preserves aspect ratio for contain and cover", () => {
  assert.deepEqual(
    resolveImageRect({ canvasWidth: 800, canvasHeight: 400, imageWidth: 200, imageHeight: 100, fit: "contain" }),
    { width: 800, height: 400 }
  );
  assert.deepEqual(
    resolveImageRect({ canvasWidth: 800, canvasHeight: 400, imageWidth: 100, imageHeight: 200, fit: "cover" }),
    { width: 800, height: 1600 }
  );
  assert.deepEqual(
    resolveImageRect({ canvasWidth: 800, canvasHeight: 400, imageWidth: 100, imageHeight: 200, fit: "stretch", scale: 0.5 }),
    { width: 400, height: 200 }
  );
});

test("isVideoSource detects data URIs and video file extensions", () => {
  assert.equal(isVideoSource("data:video/mp4;base64,abc"), true);
  assert.equal(isVideoSource("assets/loop.webm"), true);
  assert.equal(isVideoSource("assets/noise.png"), false);
});

test("resolveMediaDimensions reads image and video dimensions", () => {
  assert.deepEqual(resolveMediaDimensions({ naturalWidth: 320, naturalHeight: 180 }), {
    width: 320,
    height: 180,
  });
  assert.deepEqual(resolveMediaDimensions({ tagName: "VIDEO", videoWidth: 640, videoHeight: 360 }), {
    width: 640,
    height: 360,
  });
});
