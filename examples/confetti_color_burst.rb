# frozen_string_literal: true

# confetti_color_burst.rb
#
# Genre   : J-POP / Idol live
# BPM     : 130-180
# Duration: verse, pre-chorus, chorus, bridge
# Audio   : --audio-source mic
#           --audio-source file --audio-file examples/assets/complex_demo_loop.wav
# Keys    : 1..4 scenes, T palette scene, B blackout, F freeze, Space tap-tempo
# MIDI    : note 36..39 = scenes, CC 1 = global intensity
#
# Logo slot: place your own SVG at examples/assets/your_logo.svg and add an svg
# layer in :verse. No logo asset is bundled here.
Vizcore.define do
  set :global_intensity, 0.9
  audio_normalize mode: :adaptive, window: 3.0, target: 0.84, floor: 0.04
  bpm 154
  tap_tempo key: :space

  theme :idol_pastel do
    palette "#ff7eb6", "#7afcff", "#feff9c", "#fff4f4", "#bdb2ff", "#caffbf"
    background "#090a1f"
  end

  theme :idol_vivid do
    palette "#ff006e", "#3a86ff", "#ffbe0b", "#06d6a0", "#ffffff"
    background "#030712"
  end

  style :penlight do
    blend :add
    opacity 0.76
  end

  scene :verse do
    use_theme :idol_pastel

    layer :color_base do
      shader :gradient_pulse
      blend :screen
      opacity 0.48
      map amplitude, to: :effect_intensity, gain: 0.7, range: 0.08..0.32
      map beat_pulse, to: :pulse, range: 0.08..0.36, attack: 1.0, release: 0.16
      map fft_spectrum => :deform
    end

    layer :logo_placeholder do
      type :text
      content "YOUR LOGO"
      font "Inter"
      font_size 46
      align :center
      color "#fff4f4"
      glow_strength 0.14
      blend :screen
      # Replace this text with:
      # type :svg
      # file "assets/your_logo.svg"
      map low, to: :glow_strength, gain: 1.4, range: 0.12..0.56
      map beat_pulse, to: :font_size, gain: 10.0, min: 42.0, max: 56.0
      map fft_spectrum => :deform
    end
  end

  scene :pre_chorus do
    use_theme :idol_pastel

    layer :spark_grid do
      shader :neon_grid
      use_style :penlight
      effect :bloom
      effect_intensity 0.18
      map high, to: :effect_intensity, gain: 1.6, range: 0.14..0.62
      map beat_pulse, to: :pulse, range: 0.15..0.8, attack: 1.0, release: 0.12
      map fft_spectrum => :deform
    end

    layer :pastel_particles do
      type :particle_field
      count 2400
      force_field :fountain
      size 2.6
      use_style :penlight
      map amplitude, to: :speed, gain: 2.6, range: 0.4..4.8, curve: :sqrt
      map hihat, to: :sparkle, gain: 2.2, range: 0.2..1.0, attack: 1.0, release: 0.06
      map fft_spectrum => :deform
    end
  end

  scene :chorus do
    use_theme :idol_vivid

    layer :chorus_burst do
      shader :kaleidoscope
      blend :screen
      opacity 0.92
      effect :bloom
      effect_intensity 0.3
      vj_effect :mirror
      map amplitude, to: :effect_intensity, gain: 1.6, range: 0.22..0.95, curve: :sqrt
      map beat_pulse, to: :zoom, range: 0.12..1.0, attack: 1.0, release: 0.12
      map fft_spectrum => :deform
    end

    layer :chorus_confetti do
      type :particle_field
      count 5200 # tune: lower to 3000 when FPS drops
      force_field :burst
      size 3.0
      speed 2.4
      blend :add
      map high, to: :sparkle, gain: 2.8, range: 0.2..1.0
      map kick, to: :bass_explosion, gain: 1.6, range: 0.4..2.0, attack: 1.0, release: 0.08
      map fft_spectrum => :deform
    end
  end

  scene :bridge do
    use_theme :idol_pastel

    layer :bridge_ribbon do
      shader :waveform_ribbon
      blend :screen
      opacity 0.6
      effect :motion_blur
      effect_intensity 0.12
      map amplitude, to: :opacity, gain: 0.8, range: 0.34..0.76, curve: :sqrt
      map beat_pulse, to: :effect_intensity, range: 0.08..0.28
      map fft_spectrum => :deform
    end

    layer :bridge_title do
      type :text
      content "BRIDGE"
      font_size 64
      color "#ffffff"
      glow_strength 0.18
      blend :screen
      map mid, to: :glow_strength, gain: 1.8, range: 0.14..0.72
      map beat_pulse, to: :letter_spacing, gain: 12.0, min: 0.0, max: 18.0
      map fft_spectrum => :deform
    end
  end

  transition from: :verse, to: :pre_chorus do
    on_bar 8
    effect :crossfade, duration: 0.65
  end

  transition from: :pre_chorus, to: :chorus do
    on_bar 8
    effect :flash, duration: 0.28
  end

  transition from: :chorus, to: :bridge do
    on_bar 16
    effect :crossfade, duration: 0.8
  end

  midi :controller, device: :default

  midi_map note: 36 do
    switch_scene :verse
  end

  midi_map note: 37 do
    switch_scene :pre_chorus
  end

  midi_map note: 38 do
    switch_scene :chorus
  end

  midi_map note: 39 do
    switch_scene :bridge
  end

  midi_map cc: 1 do |value|
    set :global_intensity, value / 127.0
  end

  key "1" do
    switch_scene :verse
  end

  key "2" do
    switch_scene :pre_chorus
  end

  key "3" do
    switch_scene :chorus
  end

  key "4" do
    switch_scene :bridge
  end

  key "t" do
    switch_scene :chorus
  end

  key "b" do
    blackout
  end

  key "f" do
    freeze
  end
end
