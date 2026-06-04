# frozen_string_literal: true

Vizcore.define do
  experimental_japanese_hiragana \
    enabled: true,
    min_confidence: 0.32,
    update: :frame,
    hold_ms: 240,
    silence_clear_ms: 700,
    candidates: 3,
    debug: true

  audio_normalize mode: :adaptive, window: 2.5, target: 0.78, floor: 0.04, scale_bands: false, scale_fft: false, band_gate: 0.02

  theme :kana_neon do
    palette "#24f6ff", "#ff2bbd", "#f8fafc", "#caff2e"
    background "#020617"
  end

  scene :kana_echo do
    use_theme :kana_neon

    layer :kana_text do
      type :text
      content "声"
      font "Noto Sans JP"
      font_size 168
      align :center
      color "#f8fafc"
      stroke width: 2, color: "#020617"
      shadow color: "#24f6ff", blur: 36
      glow_strength 0.32
      blend :add

      map hiragana, to: :content, fallback: "…"
      map hiragana_confidence, to: :opacity, range: 0.12..1.0
      map hiragana_confidence, to: :glow_strength, range: 0.12..0.85
      map beat_pulse, to: :letter_spacing, min: 0, max: 18
    end

    layer :voice_ring do
      type :radial_blob
      opacity 0.35
      blend :add
      radius 0.32
      wobble 0.12

      map amplitude, to: :radius, range: 0.25..0.72, curve: :sqrt
      map hiragana_confidence, to: :wobble, range: 0.08..0.45
      map fft_spectrum => :deform
    end
  end
end
