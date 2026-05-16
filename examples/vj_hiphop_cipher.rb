# frozen_string_literal: true

# vj_hiphop_cipher.rb
#
# Genre   : HipHop / Cipher
# BPM     : 85-100
# Duration: performer-friendly intro, verse, hook
# Audio   : --audio-source mic
#           --audio-source file --audio-file examples/assets/complex_demo_loop.wav
# Keys    : 1 intro, V verse, H hook, B blackout, F freeze, Space tap-tempo
# MIDI    : note 36..38 = scenes, CC 1 = global intensity
Vizcore.define do
  set :global_intensity, 0.78
  audio_normalize mode: :adaptive, window: 3.5, target: 0.78, floor: 0.05
  bpm 92
  tap_tempo key: :space

  theme :cipher_blacktop do
    palette "#0f172a", "#f8fafc", "#facc15", "#ef4444"
    background "#020617"
  end

  style :stage_text do
    blend :screen
    opacity 0.88
  end

  scene :intro do
    use_theme :cipher_blacktop

    layer :mic_check_title do
      type :text
      content "MIC CHECK"
      font "Inter"
      font_size 92
      align :center
      color "#f8fafc"
      stroke width: 2, color: "#020617"
      shadow color: "#facc15", blur: 18
      glow_strength 0.18
      use_style :stage_text
      map amplitude, to: :glow_strength, gain: 1.3, range: 0.14..0.72, curve: :sqrt
      map beat_pulse, to: :letter_spacing, gain: 10.0, min: 0.0, max: 14.0
      map fft_spectrum => :deform
    end

    layer :intro_pulse do
      type :radial_blob
      opacity 0.34
      blend :add
      radius 0.34
      wobble 0.12
      map low, to: :radius, gain: 0.4, range: 0.3..0.68
      map kick, to: :wobble, gain: 0.8, range: 0.08..0.52, attack: 1.0, release: 0.12
      map fft_spectrum => :deform
    end
  end

  scene :verse do
    use_theme :cipher_blacktop

    layer :quiet_backline do
      type :waveform
      source :audio
      style :ribbon
      height 0.12
      opacity 0.36
      blend :screen
      map amplitude, to: :height, gain: 0.8, range: 0.08..0.28, curve: :sqrt, release: 0.34
      map beat_pulse, to: :opacity, range: 0.28..0.52, attack: 1.0, release: 0.18
      map fft_spectrum => :deform
    end

    layer :cipher_dots do
      type :shape
      opacity 0.42
      blend :add
      circle x: 240, y: 520, radius: 22, count: 3 do
        stroke 2
        map mid, to: :radius, gain: 36.0, min: 18.0, max: 56.0
        map beat_pulse, to: :stroke, gain: 4.0, min: 1.0, max: 6.0
      end
      circle x: 1040, y: 180, radius: 18, count: 2 do
        stroke 2
        map fft_spectrum => :radius
      end
    end
  end

  scene :hook do
    use_theme :cipher_blacktop

    layer :hook_color do
      shader :gradient_pulse
      blend :screen
      opacity 0.86
      effect :bloom
      effect_intensity 0.24
      map amplitude, to: :effect_intensity, gain: 1.2, range: 0.18..0.72, curve: :sqrt
      map beat_pulse, to: :pulse, range: 0.1..1.0, attack: 1.0, release: 0.14
      map fft_spectrum => :deform
    end

    layer :hook_text do
      type :text
      content "HOOK"
      font "Inter"
      font_size 116
      align :center
      color "#facc15"
      shadow color: "#ef4444", blur: 24
      glow_strength 0.32
      blend :add
      map high, to: :glow_strength, gain: 2.0, range: 0.24..1.0
      map beat_pulse, to: :font_size, gain: 32.0, min: 104.0, max: 140.0
      map fft_spectrum => :deform
    end
  end

  transition from: :intro, to: :verse do
    trigger { beat_count >= 16 || frame_count >= 240 }
    effect :crossfade, duration: 0.7
  end

  transition from: :verse, to: :hook do
    trigger { beat_count >= 48 || frame_count >= 720 }
    effect :flash, duration: 0.2
  end

  midi :controller, device: :default

  midi_map note: 36 do
    switch_scene :intro
  end

  midi_map note: 37 do
    switch_scene :verse
  end

  midi_map note: 38 do
    switch_scene :hook
  end

  midi_map cc: 1 do |value|
    set :global_intensity, value / 127.0
  end

  key "1" do
    switch_scene :intro
  end

  key "v" do
    switch_scene :verse
  end

  key "h" do
    switch_scene :hook
  end

  key "b" do
    blackout
  end

  key "f" do
    freeze
  end
end
