export const BAND_KEYS = ["sub", "low", "mid", "high"];
export const DEFAULT_FFT_BINS = 16;

export const buildAudioInspectorState = (audio, fftBins = DEFAULT_FFT_BINS) => {
  const bands = BAND_KEYS.reduce((result, key) => {
    result[key] = clamp01(audio?.bands?.[key]);
    return result;
  }, {});
  const bandPeaks = BAND_KEYS.reduce((result, key) => {
    result[key] = clamp01(audio?.band_peaks?.[key]);
    return result;
  }, {});

  return {
    amplitude: clamp01(audio?.amplitude),
    bands,
    bandPeaks,
    fft: normalizeFft(audio?.fft, fftBins),
    bpm: Number(audio?.bpm || 0),
    beat: !!audio?.beat,
    beatPulse: clamp01(audio?.beat_pulse),
    beatPhase: clamp01(audio?.beat_phase),
    barPhase: clamp01(audio?.bar_phase),
    barCount: Math.max(0, Number(audio?.bar_count || 0) || 0),
    phraseCount: Math.max(0, Number(audio?.phrase_count || 0) || 0),
    peakFrequency: Math.max(0, Number(audio?.peak_frequency || 0) || 0),
    hiragana: normalizeHiragana(audio?.japanese_hiragana),
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

const normalizeHiragana = (value) => {
  const source = value && typeof value === "object" ? value : null;
  const candidates = Array.isArray(source?.candidates) ? source.candidates : [];
  return {
    enabled: !!source,
    text: stringValue(source?.text),
    confidence: clamp01(source?.confidence),
    vowel: stringValue(source?.vowel),
    vowelConfidence: clamp01(source?.vowel_confidence),
    consonant: stringValue(source?.consonant),
    consonantConfidence: clamp01(source?.consonant_confidence),
    stable: !!source?.stable,
    silence: !!source?.silence,
    candidates: candidates.slice(0, 3).map((candidate) => ({
      text: stringValue(candidate?.text),
      confidence: clamp01(candidate?.confidence),
    })).filter((candidate) => candidate.text),
  };
};

const stringValue = (value) => {
  if (value === null || value === undefined) {
    return "";
  }
  return String(value);
};

const clamp01 = (value) => {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) {
    return 0;
  }
  return Math.min(Math.max(numeric, 0), 1);
};
