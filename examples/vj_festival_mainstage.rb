# frozen_string_literal: true

# vj_festival_mainstage.rb
#
# Genre   : EDM / Festival mainstage
# BPM     : 124-132
# Duration: opener, warmup, build, drop, outro
# Audio   : --audio-source mic
#           --audio-source file --audio-file examples/assets/complex_demo_loop.wav
# Keys    : 1..5 scenes, B blackout, F freeze, Space tap-tempo
# MIDI    : note 36..40 = scenes, CC 1 = global intensity
#
# Manifest: examples/vj_festival_mainstage.yml shows a reusable file-audio setup.
Vizcore.define do
  set :global_intensity, 0.92
  audio_normalize mode: :adaptive, window: 3.0, target: 0.88, floor: 0.04
  bpm 128
  bpm_lock true
  tap_tempo key: :space

  theme :mainstage do
    palette "#ffffff", "#00f5ff", "#ff2f92", "#fffb00"
    background "#020617"
  end

  style :stage_glow do
    blend :screen
    opacity 0.82
  end

  scene :opener do
    use_theme :mainstage

    layer :opener_logo_slot do
      type :text
      content "MAIN STAGE"
      font "Inter"
      font_size 78
      align :center
      color "#ffffff"
      stroke width: 2, color: "#020617"
      shadow color: "#00f5ff", blur: 20
      glow_strength 0.24
      use_style :stage_glow
      map amplitude, to: :glow_strength, gain: 1.4, range: 0.18..0.88, curve: :sqrt
      map beat_pulse, to: :font_size, gain: 20.0, min: 72.0, max: 106.0
      map fft_spectrum => :deform
    end

    layer :countdown_rings do
      type :shape
      blend :add
      opacity 0.52
      circle x: 640, y: 360, radius: 130, count: 6 do
        stroke 3
        map low, to: :radius, gain: 120.0, min: 110.0, max: 230.0
        map beat_pulse, to: :stroke, gain: 5.0, min: 2.0, max: 8.0
      end
    end
  end

  scene :warmup do
    use_theme :mainstage

    layer :warmup_grid do
      shader :neon_grid
      use_style :stage_glow
      effect :bloom
      effect_intensity 0.16
      map amplitude, to: :effect_intensity, gain: 1.1, range: 0.12..0.52, curve: :sqrt
      map beat_pulse, to: :pulse, range: 0.12..0.62
      map fft_spectrum => :deform
    end

    layer :warmup_cube do
      type :wireframe_cube
      opacity 0.64
      blend :add
      map bass, to: :rotation_speed, gain: 2.0, range: 0.18..3.2
      map kick, to: :scale, gain: 0.55, range: 0.82..1.4
      map fft_spectrum => :deform
    end
  end

  scene :build do
    use_theme :mainstage

    layer :riser_tunnel do
      shader :bass_tunnel
      use_style :stage_glow
      effect :motion_blur
      effect_intensity 0.18
      map amplitude, to: :warp, gain: 2.2, range: 0.18..1.8, curve: :sqrt
      map beat_pulse, to: :effect_intensity, range: 0.12..0.55, attack: 1.0, release: 0.1
      map fft_spectrum => :deform
    end

    layer :riser_particles do
      type :particle_field
      count 3600 # tune: 2400 on laptops, 7000 on mainstage GPUs
      force_field :fountain
      speed 1.6
      size 2.2
      blend :add
      map high, to: :speed, gain: 3.8, range: 0.8..7.2, curve: :sqrt
      map kick, to: :bass_explosion, gain: 1.2, range: 0.2..1.5, attack: 1.0, release: 0.08
      map fft_spectrum => :deform
    end
  end

  scene :drop, extends: :build do
    use_theme :mainstage

    group :foreground do
      blend :add
      opacity 0.84

      layer :drop_crystal do
        shader :ruby_crystal
        facets 10.0
        refraction 0.68
        effect :chromatic
        effect_intensity 0.2
        map low, to: :refraction, gain: 1.2, range: 0.42..1.0, curve: :sqrt
        map beat_pulse, to: :effect_intensity, range: 0.16..0.86, attack: 1.0, release: 0.08
        map fft_spectrum => :deform
      end

      layer :drop_title do
        type :text
        content "DROP"
        font_size 132
        align :center
        color "#ffffff"
        glow_strength 0.42
        shadow color: "#ff2f92", blur: 26
        map amplitude, to: :glow_strength, gain: 1.4, range: 0.3..1.0
        map kick, to: :font_size, gain: 36.0, min: 120.0, max: 172.0
        map fft_spectrum => :deform
      end
    end
  end

  scene :outro do
    use_theme :mainstage

    layer :afterglow do
      shader :waveform_ribbon
      blend :screen
      opacity 0.56
      effect :feedback
      effect_intensity 0.1
      map amplitude, to: :opacity, gain: 0.7, range: 0.3..0.72
      map beat_pulse, to: :effect_intensity, range: 0.06..0.24
      map fft_spectrum => :deform
    end

    layer :thanks_text do
      type :text
      content "THANK YOU"
      font_size 70
      align :center
      color "#ffffff"
      glow_strength 0.18
      blend :screen
      map mid, to: :glow_strength, gain: 1.4, range: 0.12..0.58
      map beat_pulse, to: :letter_spacing, gain: 12.0, min: 0.0, max: 18.0
      map fft_spectrum => :deform
    end
  end

  transition from: :opener, to: :warmup do
    on_bar 8
    effect :crossfade, duration: 0.8
  end

  transition from: :warmup, to: :build do
    on_bar 16
    effect :crossfade, duration: 0.75
  end

  transition from: :build, to: :drop do
    trigger { beat_count >= 32 || frame_count >= 480 }
    effect :flash, duration: 0.3
  end

  transition from: :drop, to: :outro do
    on_bar 32
    effect :crossfade, duration: 1.0
  end

  midi :controller, device: :default

  midi_map note: 36 do
    switch_scene :opener
  end

  midi_map note: 37 do
    switch_scene :warmup
  end

  midi_map note: 38 do
    switch_scene :build
  end

  midi_map note: 39 do
    switch_scene :drop
  end

  midi_map note: 40 do
    switch_scene :outro
  end

  midi_map cc: 1 do |value|
    set :global_intensity, value / 127.0
  end

  key "1" do
    switch_scene :opener
  end

  key "2" do
    switch_scene :warmup
  end

  key "3" do
    switch_scene :build
  end

  key "4" do
    switch_scene :drop
  end

  key "5" do
    switch_scene :outro
  end

  key "b" do
    blackout
  end

  key "f" do
    freeze
  end
end
