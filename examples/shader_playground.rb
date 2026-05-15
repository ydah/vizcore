# frozen_string_literal: true

# Minimal shader-focused scene for trying mapped parameters.
Vizcore.define do
  scene :shader_playground do
    layer :liquid do
      shader :liquid_wobble
      param :wobble, default: 0.35, range: 0.0..2.0, step: 0.05
      param :warp, default: 0.45, range: 0.0..3.0, step: 0.05
      param :distortion, default: 0.25, range: 0.0..2.0, step: 0.05
      blend :screen

      map amplitude, to: :wobble, gain: 2.2, range: 0.18..1.2, curve: :sqrt
      map bass, to: :warp, gain: 2.4, range: 0.25..2.2
      map treble, to: :distortion, gain: 2.0, range: 0.2..1.6
    end
  end
end
