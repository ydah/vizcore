import test from "node:test";
import assert from "node:assert/strict";

import {
  createLiveControlState,
  isTapTempoShortcut,
  isEditableShortcutTarget,
  keyboardActionForKey,
  normalizeLiveControlPayload,
  liveControlStatusText,
  normalizeKeyboardMappings,
  shortcutActionForKey,
  shortcutSceneIndexForKey,
  toggleLiveControl,
} from "../src/live-controls.js";

test("createLiveControlState starts with live output enabled", () => {
  assert.deepEqual(createLiveControlState(), {
    blackout: { enabled: false },
    freeze: { enabled: false },
  });
});

test("normalizeLiveControlPayload parses blackout color", () => {
  assert.deepEqual(
    normalizeLiveControlPayload({ value: true, color: "#3366ff", fade: 0.25 }),
    { enabled: true, fade: 0.25, color: [0.2, 0.4, 1] },
  );
});

test("normalizeLiveControlPayload parses blackout color with alpha", () => {
  assert.deepEqual(
    normalizeLiveControlPayload({ value: true, color: "#3366ff80", fade: 0.25 }),
    { enabled: true, fade: 0.25, color: [0.2, 0.4, 1, 0.5019607843137255] },
  );
});

test("normalizeLiveControlPayload parses blackout color array with alpha", () => {
  assert.deepEqual(
    normalizeLiveControlPayload({ value: true, color: [51, 102, 255, 128], fade: 0.25 }),
    { enabled: true, fade: 0.25, color: [0.2, 0.4, 1, 0.5019607843137255] },
  );
});

test("normalizeLiveControlPayload parses mixed-range blackout colors", () => {
  assert.deepEqual(
    normalizeLiveControlPayload({ value: true, color: [0.2, 0.4, 1, 128], fade: 0.25 }),
    { enabled: true, fade: 0.25, color: [0.2, 0.4, 1, 0.5019607843137255] },
  );
});

test("normalizeLiveControlPayload parses 4-digit hex colors", () => {
  assert.deepEqual(
    normalizeLiveControlPayload({ value: true, color: "#0f08" }),
    { enabled: true, color: [0, 1, 0, 0.5333333333333333] },
  );
});

test("toggleLiveControl toggles known controls without mutating input", () => {
  const state = createLiveControlState();
  const next = toggleLiveControl(state, "blackout");

  assert.deepEqual(state, {
    blackout: { enabled: false },
    freeze: { enabled: false },
  });
  assert.deepEqual(next, { blackout: { enabled: true }, freeze: { enabled: false } });
  assert.deepEqual(toggleLiveControl(next, "freeze"), {
    blackout: { enabled: true },
    freeze: { enabled: true },
  });
});

test("toggleLiveControl ignores unknown controls", () => {
  const state = { blackout: true, freeze: false };
  const next = toggleLiveControl(state, "unknown");

  assert.notEqual(next, state);
  assert.deepEqual(next, state);
});

test("liveControlStatusText summarizes active emergency controls", () => {
  assert.equal(liveControlStatusText({ blackout: { enabled: false }, freeze: { enabled: false } }), "Live: output");
  assert.equal(liveControlStatusText({ blackout: { enabled: true }, freeze: { enabled: false } }), "Live: Blackout");
  assert.equal(liveControlStatusText({ blackout: { enabled: true }, freeze: { enabled: true } }), "Live: Blackout + Freeze");
});

test("shortcutActionForKey maps live shortcuts outside editable fields", () => {
  assert.equal(shortcutActionForKey({ key: "b", target: { tagName: "DIV" } }), "blackout");
  assert.equal(shortcutActionForKey({ key: "F", target: { tagName: "DIV" } }), "freeze");
  assert.equal(shortcutActionForKey({ key: "x", target: { tagName: "DIV" } }), null);
  assert.equal(shortcutActionForKey({ key: "b", target: { tagName: "INPUT" } }), null);
});

test("shortcutSceneIndexForKey maps number keys to available scene indexes", () => {
  assert.equal(shortcutSceneIndexForKey({ key: "1", target: { tagName: "DIV" } }, 3), 0);
  assert.equal(shortcutSceneIndexForKey({ key: "3", target: { tagName: "DIV" } }, 3), 2);
  assert.equal(shortcutSceneIndexForKey({ key: "4", target: { tagName: "DIV" } }, 3), null);
  assert.equal(shortcutSceneIndexForKey({ key: "0", target: { tagName: "DIV" } }, 9), null);
  assert.equal(shortcutSceneIndexForKey({ key: "1", target: { tagName: "INPUT" } }, 3), null);
});

test("keyboardActionForKey resolves configured runtime key mappings", () => {
  const mappings = normalizeKeyboardMappings([
    { key: "D", action: { type: "switch_scene", scene: "drop" } },
    { key: " ", action: { type: "live_control", control: "freeze" } },
    { key: "x", action: { type: "unknown" } },
  ]);

  assert.deepEqual(
    keyboardActionForKey({ key: "d", target: { tagName: "DIV" } }, mappings),
    { type: "switch_scene", scene: "drop" },
  );
  assert.deepEqual(
    keyboardActionForKey({ key: "Spacebar", target: { tagName: "DIV" } }, mappings),
    { type: "live_control", control: "freeze" },
  );
  assert.equal(keyboardActionForKey({ key: "x", target: { tagName: "DIV" } }, mappings), null);
  assert.equal(keyboardActionForKey({ key: "d", target: { tagName: "INPUT" } }, mappings), null);
});

test("keyboardActionForKey preserves switch_scene transition effect", () => {
  const mappings = normalizeKeyboardMappings([
    {
      key: "D",
      action: { type: "switch_scene", scene: "drop", effect: { name: "crossfade", options: { duration: 0.5 } } },
    },
  ]);

  assert.deepEqual(
    keyboardActionForKey({ key: "d", target: { tagName: "DIV" } }, mappings),
    { type: "switch_scene", scene: "drop", effect: { name: "crossfade", options: { duration: 0.5 } } },
  );
});

test("isTapTempoShortcut matches configured keys outside editable fields", () => {
  assert.equal(isTapTempoShortcut({ key: "T", target: { tagName: "DIV" } }, "t"), true);
  assert.equal(isTapTempoShortcut({ key: " ", target: { tagName: "DIV" } }, "space"), true);
  assert.equal(isTapTempoShortcut({ key: "Spacebar", target: { tagName: "DIV" } }, "space"), true);
  assert.equal(isTapTempoShortcut({ key: "x", target: { tagName: "DIV" } }, "t"), false);
  assert.equal(isTapTempoShortcut({ key: "T", target: { tagName: "INPUT" } }, "t"), false);
  assert.equal(isTapTempoShortcut({ key: "T", target: { tagName: "DIV" } }, null), false);
});

test("isEditableShortcutTarget detects editable controls", () => {
  assert.equal(isEditableShortcutTarget(null), false);
  assert.equal(isEditableShortcutTarget({ tagName: "textarea" }), true);
  assert.equal(isEditableShortcutTarget({ tagName: "select" }), true);
  assert.equal(isEditableShortcutTarget({ tagName: "DIV", isContentEditable: true }), true);
});
