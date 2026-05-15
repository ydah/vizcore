# frozen_string_literal: true

# Parser-themed visual sketch: token flow, AST energy, and reduce flashes.
Vizcore.define do
  scene :parser_visualizer do
    layer :token_stream do
      shader :waveform_ribbon
      blend :screen
      effect :crt
      effect_intensity 0.18
      map amplitude, to: :effect_intensity, range: 0.08..0.32
    end

    layer :ast_nodes do
      type :particle_field
      count 2200
      force_field :vortex
      turbulence 0.28
      blend :add
      map bass, to: :size, gain: 3.0, range: 1.8..6.5, curve: :sqrt
      map mid, to: :speed, gain: 2.0, range: 0.4..4.2
      map hihat, to: :sparkle, gain: 2.2, range: 0.0..1.0
    end

    layer :reduce_flash do
      shader :ruby_crystal
      facets 7.0
      refraction 0.42
      blend :add
      effect :bloom
      map kick, to: :effect_intensity, gain: 2.0, range: 0.05..0.55
      map beat_pulse, to: :refraction, range: 0.32..0.86
    end

    layer :parser_label do
      type :text
      content "SHIFT  ->  REDUCE  ->  ACCEPT"
      font "IBM Plex Mono"
      font_size 58
      align :center
      fill "#d9ffe8"
      stroke width: 2, color: "#06111f"
      glow_strength 0.26
      blend :screen
      map beat_pulse, to: :glow_strength, range: 0.18..0.9
    end
  end
end
