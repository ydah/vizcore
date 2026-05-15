# frozen_string_literal: true

# Ruby-themed showcase using crystal, text, and particle layers.
Vizcore.define do
  scene :ruby_crystal do
    layer :crystal_core do
      shader :ruby_crystal
      facets 6.0
      refraction 0.48
      blend :screen

      map bass, to: :refraction, gain: 0.8, range: 0.28..0.78, curve: :sqrt
      map mid, to: :facets, gain: 2.0, range: 5.0..10.0
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
