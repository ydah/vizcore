# frozen_string_literal: true

# nebula_ribbon_bloom.rb
#
# Genre   : Ambient / Chill Room
# BPM     : none, or 60-90 when a pulse appears
# Duration: slow rotation between two long scenes
# Audio   : --audio-source mic
#           --audio-source file --audio-file examples/assets/complex_demo_loop.wav
# Keys    : 1 bloom, 2 nebula, B blackout, F freeze
# MIDI    : note 36..37 = scenes, CC 1 = global intensity
Vizcore.define do
  set :global_intensity, 0.7
  audio_normalize mode: :adaptive, window: 8.0, target: 0.72, floor: 0.03

  theme :chill_room do
    palette "#1e293b", "#64748b", "#a5b4fc", "#f8fafc"
    background "#020617"
  end

  style :soft_screen do
    blend :screen
    opacity 0.52
  end

  scene :bloom do
    use_theme :chill_room

    layer :slow_ribbon do
      shader :waveform_ribbon
      use_style :soft_screen
      effect :bloom
      effect_intensity 0.18
      map amplitude, to: :opacity, gain: 0.85, range: 0.28..0.86, curve: :sqrt, attack: 0.18, release: 0.72
      map beat_pulse, to: :effect_intensity, range: 0.12..0.34, attack: 0.24, release: 0.82
      map fft_spectrum => :deform
    end

    layer :breathing_halo do
      type :radial_blob
      opacity 0.46
      blend :add
      segments 192
      radius 0.42
      wobble 0.18
      map amplitude, to: :wobble, gain: 1.3, range: 0.08..0.48, curve: :sqrt, attack: 0.2, release: 0.82
      map beat_confidence, to: :radius, gain: 0.14, range: 0.38..0.54
      map fft_spectrum => :deform
    end
  end

  scene :nebula do
    use_theme :chill_room

    layer :deep_spectrum do
      type :spectrogram
      scroll :horizontal
      bins 80
      history 220
      gain 0.62
      opacity 0.5
      blend :screen
      effect :motion_blur
      effect_intensity 0.12
      map amplitude, to: :opacity, gain: 0.7, range: 0.22..0.68, attack: 0.18, release: 0.76
      map beat_pulse, to: :effect_intensity, range: 0.08..0.26, release: 0.82
      map fft_spectrum => :deform
    end

    layer :nebula_points do
      type :particle_field
      count 1200
      speed 0.18
      size 2.6
      force_field :drift
      turbulence 0.12
      opacity 0.42
      blend :add
      map amplitude, to: :speed, gain: 0.9, range: 0.08..0.72, curve: :sqrt, attack: 0.22, release: 0.84
      map low, to: :size, gain: 2.2, range: 1.8..5.2
      map fft_spectrum => :deform
    end
  end

  transition from: :bloom, to: :nebula do
    trigger { seconds >= 90 || beat_count >= 96 }
    effect :crossfade, duration: 3.0
  end

  transition from: :nebula, to: :bloom do
    trigger { seconds >= 90 || beat_count >= 96 }
    effect :crossfade, duration: 3.0
  end

  midi :controller, device: :default

  midi_map note: 36 do
    switch_scene :bloom
  end

  midi_map note: 37 do
    switch_scene :nebula
  end

  midi_map cc: 1 do |value|
    set :global_intensity, value / 127.0
  end

  key "1" do
    switch_scene :bloom
  end

  key "2" do
    switch_scene :nebula
  end

  key "b" do
    blackout
  end

  key "f" do
    freeze
  end
end
