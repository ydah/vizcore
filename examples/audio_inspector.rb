# frozen_string_literal: true

# Visualizes the same audio features shown in the HUD inspector.
Vizcore.define do
  scene :audio_inspector do
    layer :bars do
      shader :audio_bars
      param :bar_count, default: 32.0, range: 12.0..64.0, step: 1.0
      param :floor_glow, default: 0.18, range: 0.0..1.0, step: 0.02
      blend :screen
      map amplitude, to: :floor_glow, gain: 1.6, range: 0.08..0.5
    end

    layer :peak_blob do
      type :radial_blob
      radius 0.28
      wobble 0.35
      blend :add
      map amplitude, to: :radius, range: 0.22..0.58, curve: :sqrt
      map fft_spectrum => :spectrum
      map treble, to: :wobble, range: 0.2..1.2
    end

    layer :label do
      type :text
      content "AUDIO"
      font_size 76
      glow_strength 0.2
      map beat_pulse, to: :glow_strength, range: 0.12..0.8
    end
  end
end
