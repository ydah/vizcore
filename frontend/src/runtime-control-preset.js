export const normalizeRuntimeControlPreset = (value) => {
  const input = value && typeof value === "object" ? value : {};
  return {
    visualSettings: objectValue(input.visual_settings) || objectValue(input.visualSettings) || null,
    midiLearnBindings: objectValue(input.midi_learn_bindings) || objectValue(input.midiLearnBindings) || null,
  };
};

const objectValue = (value) => {
  return value && typeof value === "object" && !Array.isArray(value) ? value : null;
};
