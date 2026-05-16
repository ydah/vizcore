# frozen_string_literal: true

# vj_synthwave_retro.rb
#
# Genre   : Synthwave / Retro 80s
# BPM     : 100-120
# Duration: sunset, highway, laser
# Audio   : --audio-source mic
#           --audio-source file --audio-file examples/assets/complex_demo_loop.wav
# Keys    : 1 sunset, 2 highway, 3 laser, B blackout, F freeze, Space tap-tempo
# MIDI    : note 36..38 = scenes, CC 1 = global intensity
Vizcore.define do
  set :global_intensity, 0.86
  audio_normalize mode: :adaptive, window: 3.5, target: 0.82, floor: 0.04
  bpm 112
  tap_tempo key: :space

  theme :retro_neon do
    palette "#ff006e", "#8338ec", "#3a86ff", "#ffbe0b"
    background "#070019"
  end

  style :neon_lines do
    blend :add
    opacity 0.72
  end

  scene :sunset do
    use_theme :retro_neon

    layer :sun_disc do
      type :shape
      use_style :neon_lines
      circle x: 640, y: 250, radius: 170, count: 8 do
        stroke 3
        map amplitude, to: :radius, gain: 80.0, min: 150.0, max: 230.0, curve: :sqrt
        map beat_pulse, to: :stroke, gain: 4.0, min: 2.0, max: 7.0
      end
    end

    layer :sunset_spectrum do
      type :spectrogram
      scroll :horizontal
      bins 64
      history 140
      gain 0.7
      opacity 0.36
      blend :screen
      effect :bloom
      effect_intensity 0.14
      map high, to: :gain, gain: 1.4, range: 0.52..1.55
      map beat_pulse, to: :effect_intensity, range: 0.1..0.42
      map fft_spectrum => :deform
    end
  end

  scene :highway do
    use_theme :retro_neon

    layer :road_grid do
      type :shape
      use_style :neon_lines
      line x1: 110, y1: 680, x2: 640, y2: 360 do
        stroke 2
        map amplitude, to: :stroke, gain: 5.0, min: 1.0, max: 8.0
      end
      line x1: 1170, y1: 680, x2: 640, y2: 360 do
        stroke 2
        map beat_pulse, to: :stroke, gain: 5.0, min: 1.0, max: 8.0
      end
      line x1: 0, y1: 610, x2: 1280, y2: 610 do
        stroke 2
        map fft_spectrum => :y1
      end
      line x1: 0, y1: 520, x2: 1280, y2: 520 do
        stroke 2
        map mid, to: :stroke, gain: 5.0, min: 1.0, max: 7.0
      end
    end

    layer :highway_grid_shader do
      shader :neon_grid
      blend :screen
      opacity 0.58
      effect :chromatic
      effect_intensity 0.16
      map low, to: :effect_intensity, gain: 1.4, range: 0.1..0.5
      map beat_pulse, to: :pulse, range: 0.12..0.72
      map fft_spectrum => :deform
    end
  end

  scene :laser do
    use_theme :retro_neon

    layer :laser_fan do
      type :shape
      use_style :neon_lines
      line x1: 120, y1: 100, x2: 1180, y2: 650 do
        stroke 4
        map amplitude, to: :stroke, gain: 7.0, min: 2.0, max: 12.0
      end
      line x1: 1180, y1: 100, x2: 120, y2: 650 do
        stroke 4
        map beat_pulse, to: :stroke, gain: 8.0, min: 2.0, max: 13.0
      end
      line x1: 640, y1: 0, x2: 640, y2: 720 do
        stroke 3
        map fft_spectrum => :x1
      end
    end

    layer :laser_glow do
      shader :glitch_flash
      blend :add
      opacity 0.46
      effect :bloom
      effect_intensity 0.24
      vj_effect :color_shift
      map high, to: :effect_intensity, gain: 2.1, range: 0.18..0.84
      map kick, to: :opacity, gain: 1.1, range: 0.34..0.92
      map fft_spectrum => :deform
    end
  end

  transition from: :sunset, to: :highway do
    on_bar 8
    effect :crossfade, duration: 0.8
  end

  transition from: :highway, to: :laser do
    on_bar 8
    effect :flash, duration: 0.25
  end

  midi :controller, device: :default

  midi_map note: 36 do
    switch_scene :sunset
  end

  midi_map note: 37 do
    switch_scene :highway
  end

  midi_map note: 38 do
    switch_scene :laser
  end

  midi_map cc: 1 do |value|
    set :global_intensity, value / 127.0
  end

  key "1" do
    switch_scene :sunset
  end

  key "2" do
    switch_scene :highway
  end

  key "3" do
    switch_scene :laser
  end

  key "b" do
    blackout
  end

  key "f" do
    freeze
  end
end
