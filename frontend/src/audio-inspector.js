export const BAND_KEYS = ["sub", "low", "mid", "high"];
export const DEFAULT_FFT_BINS = 16;

export const buildAudioInspectorState = (audio, fftBins = DEFAULT_FFT_BINS) => {
  const bands = BAND_KEYS.reduce((result, key) => {
    result[key] = clamp01(audio?.bands?.[key]);
    return result;
  }, {});

  return {
    amplitude: clamp01(audio?.amplitude),
    bands,
    fft: normalizeFft(audio?.fft, fftBins),
    bpm: Number(audio?.bpm || 0),
    beat: !!audio?.beat,
    beatPulse: clamp01(audio?.beat_pulse),
    beatPhase: clamp01(audio?.beat_phase),
    barPhase: clamp01(audio?.bar_phase),
    barCount: Math.max(0, Number(audio?.bar_count || 0) || 0),
    phraseCount: Math.max(0, Number(audio?.phrase_count || 0) || 0),
    peakFrequency: Math.max(0, Number(audio?.peak_frequency || 0) || 0),
  };
};

export const formatMeterValue = (value, digits = 2) => {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) {
    return Number(0).toFixed(digits);
  }
  return numeric.toFixed(digits);
};

const normalizeFft = (value, size) => {
  const input = Array.isArray(value) || ArrayBuffer.isView(value) ? Array.from(value) : [];
  return Array.from({ length: size }, (_entry, index) => clamp01(input[index]));
};

const clamp01 = (value) => {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) {
    return 0;
  }
  return Math.min(Math.max(numeric, 0), 1);
};
