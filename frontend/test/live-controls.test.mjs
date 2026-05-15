import test from "node:test";
import assert from "node:assert/strict";

import {
  createLiveControlState,
  isEditableShortcutTarget,
  liveControlStatusText,
  shortcutActionForKey,
  shortcutSceneIndexForKey,
  toggleLiveControl,
} from "../src/live-controls.js";

test("createLiveControlState starts with live output enabled", () => {
  assert.deepEqual(createLiveControlState(), { blackout: false, freeze: false });
});

test("toggleLiveControl toggles known controls without mutating input", () => {
  const state = createLiveControlState();
  const next = toggleLiveControl(state, "blackout");

  assert.deepEqual(state, { blackout: false, freeze: false });
  assert.deepEqual(next, { blackout: true, freeze: false });
  assert.deepEqual(toggleLiveControl(next, "freeze"), { blackout: true, freeze: true });
});

test("toggleLiveControl ignores unknown controls", () => {
  const state = { blackout: true, freeze: false };
  const next = toggleLiveControl(state, "unknown");

  assert.notEqual(next, state);
  assert.deepEqual(next, state);
});

test("liveControlStatusText summarizes active emergency controls", () => {
  assert.equal(liveControlStatusText({ blackout: false, freeze: false }), "Live: output");
  assert.equal(liveControlStatusText({ blackout: true, freeze: false }), "Live: Blackout");
  assert.equal(liveControlStatusText({ blackout: true, freeze: true }), "Live: Blackout + Freeze");
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

test("isEditableShortcutTarget detects editable controls", () => {
  assert.equal(isEditableShortcutTarget(null), false);
  assert.equal(isEditableShortcutTarget({ tagName: "textarea" }), true);
  assert.equal(isEditableShortcutTarget({ tagName: "select" }), true);
  assert.equal(isEditableShortcutTarget({ tagName: "DIV", isContentEditable: true }), true);
});
