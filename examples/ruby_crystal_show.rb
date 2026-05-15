# frozen_string_literal: true

# Ruby-themed showcase using existing geometry, text, and particle layers.
Vizcore.define do
  scene :ruby_crystal do
    layer :crystal_core do
      shader :unyo_geometry
      sides 6.0
      scale 0.96
      wobble 0.62
      twist 0.78
      line_glow 0.42
      blend :screen

      map beat_count => :seed
      map bass, to: :kick, gain: 3.0, range: 0.0..1.4, curve: :sqrt
      map bass, to: :scale, gain: 0.5, range: 0.82..1.22, curve: :sqrt
      map mid, to: :twist, gain: 2.0, range: 0.55..2.2
      map treble, to: :snare, gain: 2.2, range: 0.0..1.1, curve: :sqrt
      map beat_pulse, to: :pulse, range: 0.0..1.6, attack: 1.0, release: 0.12
    end

    layer :gem_sparks do
      type :particle_field
      count 2600
      blend :add
      map amplitude, to: :speed, gain: 2.6, range: 0.2..4.8, curve: :sqrt
      map bass, to: :size, gain: 3.2, range: 1.8..7.0
      map treble, to: :sparkle, gain: 2.6, range: 0.0..1.0
    end

    layer :ruby_title do
      type :text
      content "RUBY"
      font_size 118
      color "#ff335f"
      glow_strength 0.35
      blend :screen
      map beat_pulse, to: :glow_strength, range: 0.24..0.9
    end
  end
end
