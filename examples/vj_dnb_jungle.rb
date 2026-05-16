# frozen_string_literal: true

# vj_dnb_jungle.rb
#
# Genre   : Drum & Bass / Jungle
# BPM     : 170-180
# Duration: 3-scene break workout
# Audio   : --audio-source mic
#           --audio-source file --audio-file examples/assets/complex_demo_loop.wav
# Keys    : 1 rollers, 2 amen, 3 reese, B blackout, F freeze, Space tap-tempo
# MIDI    : note 36..38 = scenes, note 40 = reese, CC 1 = global intensity
Vizcore.define do
  set :global_intensity, 0.88
  audio_normalize mode: :adaptive, window: 2.5, target: 0.86, floor: 0.04
  bpm 176
  bpm_lock true
  tap_tempo key: :space

  theme :jungle_neon do
    palette "#00f5d4", "#00bbf9", "#f15bb5", "#fee440"
    background "#030712"
  end

  style :fast_add do
    blend :add
    opacity 0.76
  end

  scene :rollers do
    use_theme :jungle_neon

    layer :star_tunnel do
      shader :starfield
      blend :screen
      effect :motion_blur
      effect_intensity 0.16
      map amplitude, to: :warp, gain: 1.8, range: 0.18..1.3, curve: :sqrt
      map beat_pulse, to: :effect_intensity, range: 0.12..0.42, attack: 1.0, release: 0.08
      map fft_spectrum => :deform
    end

    layer :rolling_particles do
      type :particle_field
      count 4200 # tune: 2600 for laptops, 6000 for stage machines
      force_field :flow
      speed 2.6
      size 1.6
      use_style :fast_add
      react_to amplitude do
        change :speed, gain: 3.6, range: 1.2..7.2, curve: :sqrt
        change :size, gain: 2.4, range: 1.2..4.6
      end
      map hihat, to: :sparkle, gain: 2.8, range: 0.1..1.0, attack: 1.0, release: 0.05
      map fft_spectrum => :deform
    end
  end

  scene :amen do
    use_theme :jungle_neon

    layer :kick_cube do
      type :wireframe_cube
      opacity 0.6
      blend :add
      map kick, to: :scale, gain: 0.9, range: 0.74..1.46, curve: :sqrt, attack: 1.0, release: 0.08
      map low, to: :rotation_speed, gain: 1.4, range: 0.12..2.4
      map fft_spectrum => :deform
    end

    layer :snare_cube do
      type :wireframe_cube
      opacity 0.48
      blend :difference
      map snare, to: :color_shift, gain: 2.2, range: 0.1..1.0, attack: 1.0, release: 0.06
      map mid, to: :rotation_speed, gain: 1.6, range: 0.2..2.8
      map fft_spectrum => :deform
    end

    layer :hat_text do
      type :text
      content "176 BPM"
      font "Inter"
      font_size 52
      align :center
      color "#eaffff"
      glow_strength 0.18
      blend :screen
      map hihat, to: :glow_strength, gain: 2.8, range: 0.16..0.95, attack: 1.0, release: 0.05
      map beat_pulse, to: :letter_spacing, gain: 18.0, min: 0.0, max: 24.0
      map fft_spectrum => :deform
    end
  end

  scene :reese do
    use_theme :jungle_neon

    layer :reese_warp do
      shader :bass_tunnel
      blend :screen
      effect :feedback
      effect_intensity 0.18
      map bass, to: :warp, gain: 3.0, range: 0.2..2.2, curve: :sqrt
      map kick, to: :effect_intensity, gain: 1.1, range: 0.12..0.62, attack: 1.0, release: 0.1
      map fft_spectrum => :deform
    end

    layer :chromatic_noise do
      shader :glitch_flash
      blend :add
      effect :chromatic
      effect_intensity 0.22
      opacity 0.58
      map amplitude, to: :opacity, gain: 0.8, range: 0.34..0.84
      map onset(:high), to: :effect_intensity, gain: 2.4, range: 0.12..0.9, attack: 1.0, release: 0.05
      map fft_spectrum => :deform
    end
  end

  transition from: :rollers, to: :amen do
    trigger { beat_count >= 32 || frame_count >= 360 }
    effect :crossfade, duration: 0.45
  end

  transition from: :amen, to: :rollers do
    trigger { beat_count >= 64 || frame_count >= 720 }
    effect :flash, duration: 0.18
  end

  midi :controller, device: :default

  midi_map note: 36 do
    switch_scene :rollers
  end

  midi_map note: 37 do
    switch_scene :amen
  end

  midi_map note: 38 do
    switch_scene :reese
  end

  midi_map note: 40 do
    switch_scene :reese
  end

  midi_map cc: 1 do |value|
    set :global_intensity, value / 127.0
  end

  key "1" do
    switch_scene :rollers
  end

  key "2" do
    switch_scene :amen
  end

  key "3" do
    switch_scene :reese
  end

  key "b" do
    blackout
  end

  key "f" do
    freeze
  end
end
