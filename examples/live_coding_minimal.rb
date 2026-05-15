# frozen_string_literal: true

# Short scene intended for live-coding demos.
Vizcore.define do
  scene :main do
    layer :pulse do
      type :radial_blob
      radius 0.34
      wobble 0.2
      map amplitude, to: :radius, range: 0.22..0.7, curve: :sqrt
      map fft_spectrum => :spectrum
    end

    layer :beat_label do
      type :text
      content "VIZCORE"
      font_size 86
      glow_strength 0.2
      map beat_pulse, to: :glow_strength, range: 0.12..0.85
    end
  end
end
