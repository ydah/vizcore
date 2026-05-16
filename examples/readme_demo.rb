# frozen_string_literal: true

# Minimal scene used to generate docs/assets/vizcore-demo.gif.
# It intentionally shows one idea: detected beats expand the rings.
Vizcore.define do
  scene :readme_demo do
    layer :beat_rings do
      palette "#24f6ff", "#ff2bbd", "#caff2e"

      circle count: 4 do
        radius 92
        stroke 3
        map beat_pulse, to: :radius, gain: 160.0, min: 56, max: 164, attack: 1.0, release: 0.2
      end
    end
  end
end
