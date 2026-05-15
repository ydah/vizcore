export const createLiveControlState = () => ({
  blackout: false,
  freeze: false,
});

export const toggleLiveControl = (state, key) => {
  const control = String(key || "");
  if (control !== "blackout" && control !== "freeze") {
    return { ...state };
  }

  return {
    ...state,
    [control]: !state?.[control],
  };
};

export const liveControlStatusText = (state) => {
  const values = [];
  if (state?.blackout) values.push("Blackout");
  if (state?.freeze) values.push("Freeze");
  return values.length ? `Live: ${values.join(" + ")}` : "Live: output";
};

export const shortcutActionForKey = (event) => {
  if (isEditableShortcutTarget(event?.target)) {
    return null;
  }

  const key = String(event?.key || "").toLowerCase();
  if (key === "b") return "blackout";
  if (key === "f") return "freeze";
  return null;
};

export const shortcutSceneIndexForKey = (event, sceneCount) => {
  if (isEditableShortcutTarget(event?.target)) {
    return null;
  }

  const index = Number.parseInt(String(event?.key || ""), 10) - 1;
  if (!Number.isInteger(index) || index < 0 || index >= 9 || index >= sceneCount) {
    return null;
  }

  return index;
};

export const isEditableShortcutTarget = (target) => {
  if (!target) {
    return false;
  }

  const tagName = String(target.tagName || "").toLowerCase();
  return tagName === "input"
    || tagName === "textarea"
    || tagName === "select"
    || target.isContentEditable === true;
};
