# frozen_string_literal: true

# vj_glitch_industrial.rb
#
# Genre   : Glitch / Industrial / Noise
# BPM     : n/a
# Duration: scan, tear, white_out
# Audio   : --audio-source mic
#           --audio-source file --audio-file examples/assets/complex_demo_loop.wav
# Keys    : 1 scan, 2 tear, X white_out, B blackout, F freeze
# MIDI    : note 36..38 = scenes, note 41 = white_out, CC 1 = global intensity
Vizcore.define do
  set :global_intensity, 0.84
  audio_normalize mode: :adaptive, window: 2.0, target: 0.88, floor: 0.02

  theme :factory_noise do
    palette "#f8fafc", "#71717a", "#ef4444", "#111827"
    background "#000000"
  end

  style :abrasive do
    blend :difference
    opacity 0.74
  end

  scene :scan do
    use_theme :factory_noise

    layer :scanner_waterfall do
      type :spectrogram
      scroll :vertical
      bins 128
      history 90
      gain 0.9
      use_style :abrasive
      effect :glitch
      effect_intensity 0.18
      map amplitude, to: :opacity, gain: 0.9, range: 0.36..0.92, curve: :sqrt
      map onset(:high), to: :effect_intensity, gain: 2.4, range: 0.12..0.94, attack: 1.0, release: 0.04
      map fft_spectrum => :deform
    end

    layer :scanline_text do
      type :text
      content "SCAN"
      font_size 76
      color "#f8fafc"
      blend :multiply
      shadow color: "#ef4444", blur: 10
      glow_strength 0.08
      map high, to: :glow_strength, gain: 2.6, range: 0.06..0.7
      map beat_pulse, to: :letter_spacing, gain: 18.0, min: 0.0, max: 22.0
      map fft_spectrum => :deform
    end
  end

  scene :tear do
    use_theme :factory_noise

    layer :feedback_tear do
      shader :liquid_wobble
      opacity 0.86
      blend :difference
      effect :feedback
      effect_intensity 0.28
      wobble 0.54
      warp 1.1
      map amplitude, to: :wobble, gain: 3.2, range: 0.28..1.8, curve: :sqrt
      map onset(:high), to: :effect_intensity, gain: 2.2, range: 0.18..1.0, attack: 1.0, release: 0.05
      map fft_spectrum => :deform
    end

    layer :tear_mesh do
      type :mesh
      geometry :octahedron
      material :wireframe
      scale 0.9
      deform 0.36
      blend :multiply
      map low, to: :scale, gain: 0.8, range: 0.75..1.42
      map beat_confidence, to: :deform, gain: 1.3, range: 0.22..1.0
      map fft_spectrum => :color_shift
    end
  end

  scene :white_out do
    use_theme :factory_noise

    layer :white_flash do
      shader :glitch_flash
      opacity 0.94
      blend :add
      effect :crt
      effect_intensity 0.42
      map amplitude, to: :opacity, gain: 1.2, range: 0.52..1.0, curve: :sqrt
      map onset(:high), to: :effect_intensity, gain: 3.0, range: 0.22..1.0, attack: 1.0, release: 0.03
      map fft_spectrum => :deform
    end

    layer :warning_text do
      type :text
      content "WHITE OUT"
      font_size 96
      color "#000000"
      blend :difference
      glow_strength 0.48
      map mid, to: :glow_strength, gain: 2.5, range: 0.28..1.0
      map beat_pulse, to: :font_size, gain: 26.0, min: 90.0, max: 132.0
      map fft_spectrum => :deform
    end
  end

  transition from: :scan, to: :tear do
    trigger { seconds >= 36 || beat_count >= 32 }
    effect :crossfade, duration: 0.35
  end

  transition from: :tear, to: :scan do
    trigger { seconds >= 48 || beat_count >= 48 }
    effect :flash, duration: 0.18
  end

  midi :controller, device: :default

  midi_map note: 36 do
    switch_scene :scan
  end

  midi_map note: 37 do
    switch_scene :tear
  end

  midi_map note: 38 do
    switch_scene :white_out
  end

  midi_map note: 41 do
    switch_scene :white_out
  end

  midi_map cc: 1 do |value|
    set :global_intensity, value / 127.0
  end

  key "1" do
    switch_scene :scan
  end

  key "2" do
    switch_scene :tear
  end

  key "x" do
    switch_scene :white_out
  end

  key "b" do
    blackout
  end

  key "f" do
    freeze
  end
end
