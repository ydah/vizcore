export const normalizeRuntimeControlPreset = (value) => {
  const input = value && typeof value === "object" ? value : {};
  return {
    visualSettings: objectValue(input.visual_settings) || objectValue(input.visualSettings) || null,
    midiLearnBindings: objectValue(input.midi_learn_bindings) || objectValue(input.midiLearnBindings) || null,
    sceneOverrides: normalizeSceneOverrides(
      input.scene_overrides || input.sceneOverrides || null
    ),
  };
};

const objectValue = (value) => {
  return value && typeof value === "object" && !Array.isArray(value) ? value : null;
};

const normalizeSceneOverrides = (value) => {
  if (!value || typeof value !== "object") {
    return {};
  }

  const output = {};
  for (const [rawSceneName, rawOverride] of Object.entries(value)) {
    const sceneName = String(rawSceneName || "").trim();
    if (!sceneName) {
      continue;
    }

    const override = normalizeSceneOverride(rawOverride);
    if (!override) {
      continue;
    }

    output[sceneName] = override;
  }

  return output;
};

const normalizeSceneOverride = (value) => {
  const input = value && typeof value === "object" && !Array.isArray(value) ? value : {};
  const visualSettings = objectValue(input.visual_settings) || objectValue(input.visualSettings);
  const midiLearnBindings = objectValue(input.midi_learn_bindings) || objectValue(input.midiLearnBindings);
  if (!visualSettings && !midiLearnBindings) {
    return null;
  }

  const output = {};
  if (visualSettings) {
    output.visualSettings = visualSettings;
  }
  if (midiLearnBindings) {
    output.midiLearnBindings = midiLearnBindings;
  }
  return output;
};
