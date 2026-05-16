# frozen_string_literal: true

# vj_techno_warehouse.rb
#
# Genre   : Techno / Warehouse
# BPM     : 128-140
# Duration: long-loopable
# Audio   : --audio-source mic
#           --audio-source file --audio-file examples/assets/complex_demo_loop.wav
# Keys    : 1..4 scenes, B blackout, F freeze, Space tap-tempo
# MIDI    : note 36..39 = scenes, CC 1 = global intensity
#
# Keep particle counts near the comments below for laptops; raise them for LED walls.
Vizcore.define do
  set :global_intensity, 0.85
  audio_normalize mode: :adaptive, window: 4.0, target: 0.82, floor: 0.04
  bpm 134
  bpm_lock true
  tap_tempo key: :space

  theme :warehouse do
    palette "#050505", "#e8e8e8", "#ff003c"
    background "#000000"
  end

  style :hard_screen do
    blend :screen
    opacity 0.82
  end

  scene :loop do
    use_theme :warehouse

    layer :bg_grid do
      shader :neon_grid
      use_style :hard_screen
      effect :crt
      effect_intensity 0.08
      map bass, to: :effect_intensity, gain: 0.8, range: 0.05..0.22, curve: :sqrt
      map beat_pulse, to: :pulse, range: 0.08..0.32, attack: 1.0, release: 0.16
      map fft_spectrum => :deform
    end

    layer :floor_mesh do
      type :mesh
      geometry :icosahedron
      material :wireframe
      scale 0.72
      opacity 0.55
      map amplitude, to: :opacity, gain: 0.8, range: 0.38..0.72, curve: :sqrt
      map beat_confidence, to: :scale, gain: 0.28, range: 0.68..1.02
      map fft_spectrum => :deform
    end
  end

  scene :build do
    use_theme :warehouse

    layer :ribbon_pressure do
      type :waveform
      source :audio
      style :ribbon
      height 0.34
      opacity 0.78
      blend :screen
      map amplitude, to: :height, gain: 1.4, range: 0.22..0.72, curve: :sqrt, attack: 0.85, release: 0.2
      map kick, to: :color_shift, range: 0.0..0.9, attack: 1.0, release: 0.08
      map fft_spectrum => :deform
    end

    layer :strobe_particles do
      type :particle_field
      count 2600 # tune: 1800 for older laptops, 5000 for stronger GPUs
      size 2.0
      speed 1.3
      force_field :vortex
      blend :add
      react_to bass do
        change :speed, gain: 2.6, range: 0.6..4.4, curve: :sqrt
        change :opacity, gain: 0.9, range: 0.46..0.94
      end
      map beat_pulse, to: :sparkle, range: 0.1..1.0, attack: 1.0, release: 0.12
      map fft_spectrum => :deform
    end
  end

  scene :peak do
    use_theme :warehouse

    layer :crystal_shards do
      shader :ruby_crystal
      blend :screen
      facets 11.0
      refraction 0.62
      effect :chromatic
      effect_intensity 0.18
      map low, to: :refraction, gain: 1.0, range: 0.36..0.9, curve: :sqrt
      map kick, to: :effect_intensity, gain: 1.2, range: 0.16..0.72, attack: 1.0, release: 0.07
      map fft_spectrum => :deform
    end

    layer :peak_mesh do
      type :mesh
      geometry :icosahedron
      material :wireframe
      scale 0.96
      deform 0.22
      blend :add
      map amplitude, to: :deform, gain: 2.0, range: 0.12..1.25, curve: :sqrt
      map beat_confidence, to: :scale, gain: 0.35, range: 0.84..1.32
      map fft_spectrum => :color_shift
    end
  end

  scene :breakdown do
    use_theme :warehouse

    layer :vertical_spectrum do
      type :spectrogram
      scroll :vertical
      bins 96
      history 180
      gain 0.75
      opacity 0.74
      blend :screen
      effect :feedback
      effect_intensity 0.1
      map amplitude, to: :opacity, range: 0.32..0.88, attack: 0.55, release: 0.35
      map high, to: :gain, gain: 1.6, range: 0.55..1.75
      map beat_pulse, to: :effect_intensity, range: 0.04..0.32
      map fft_spectrum => :deform
    end
  end

  transition from: :loop, to: :build do
    on_bar 16
    effect :crossfade, duration: 1.0
  end

  transition from: :build, to: :peak do
    trigger { beat_count >= 32 || frame_count >= 480 }
    effect :flash, duration: 0.24
  end

  transition from: :breakdown, to: :loop do
    on_bar 16
    effect :crossfade, duration: 1.2
  end

  midi :controller, device: :default

  midi_map note: 36 do
    switch_scene :loop
  end

  midi_map note: 37 do
    switch_scene :build
  end

  midi_map note: 38 do
    switch_scene :peak
  end

  midi_map note: 39 do
    switch_scene :breakdown
  end

  midi_map cc: 1 do |value|
    set :global_intensity, value / 127.0
  end

  key "1" do
    switch_scene :loop
  end

  key "2" do
    switch_scene :build
  end

  key "3" do
    switch_scene :peak
  end

  key "4" do
    switch_scene :breakdown
  end

  key "b" do
    blackout
  end

  key "f" do
    freeze
  end
end
