# frozen_string_literal: true

# Kansai RubyKaigi visual: ruby crystal, water ripple, geometric pattern, and title.
Vizcore.define do
  scene :kansai_rubykaigi do
    layer :lake_ripple do
      shader :liquid_wobble
      wobble 0.18
      warp 0.32
      distortion 0.16
      opacity 0.86
      blend :screen
      effect :feedback
      effect_intensity 0.08

      map bass, to: :wobble, gain: 0.9, range: 0.12..0.58, curve: :sqrt
      map mid, to: :warp, gain: 1.2, range: 0.22..1.45
      map high, to: :effect_intensity, range: 0.04..0.22
    end

    layer :kyoto_pattern do
      shader :kaleidoscope
      opacity 0.34
      blend :add
      vj_effect :mirror
      effect_intensity 0.18

      map mid, to: :effect_intensity, gain: 1.2, range: 0.08..0.42
    end

    layer :ruby_glow do
      shader :ruby_crystal
      facets 8.0
      refraction 0.52
      opacity 0.82
      blend :screen
      effect :bloom

      map bass, to: :refraction, gain: 0.9, range: 0.34..0.86, curve: :sqrt
      map beat_pulse, to: :effect_intensity, range: 0.12..0.72
    end

    layer :spark_line do
      type :particle_field
      count 1800
      force_field :vortex
      turbulence 0.18
      blend :add

      map amplitude, to: :speed, gain: 2.2, range: 0.25..4.2, curve: :sqrt
      map bass, to: :size, gain: 2.0, range: 1.4..5.4
      map hihat, to: :sparkle, gain: 2.4, range: 0.0..1.0
    end

    layer :event_title do
      type :text
      content "KANSAI RUBYKAIGI"
      font "IBM Plex Sans"
      font_size 66
      align :center
      color "#fff4e6"
      stroke width: 2, color: "#120617"
      shadow color: "#ff335f", blur: 20
      glow_strength 0.28
      blend :screen

      map beat_pulse, to: :glow_strength, range: 0.2..0.92
    end
  end
end
