# frozen_string_literal: true

Vizcore.define do
  scene :unyo do
    layer :liquid do
      shader :liquid_wobble
      opacity 1.0
      blend :alpha
      effect :feedback
      effect_intensity 0.14
      wobble 0.25
      warp 0.45
      distortion 0.25

      map amplitude, to: :wobble, gain: 3.5, range: 0.12..1.4, curve: :sqrt, attack: 0.9, release: 0.18
      map frequency_band(:low), to: :warp, gain: 2.2, range: 0.25..2.4, attack: 0.8, release: 0.2
      map frequency_band(:high), to: :distortion, gain: 1.8, range: 0.1..1.6
      map beat_pulse, to: :effect_intensity, range: 0.08..0.35, attack: 1.0, release: 0.2
    end

    layer :particles do
      type :particle_field
      count 7000
      blend :add
      opacity 0.55
      size 2.8
      force_field :vortex
      turbulence 0.55
      bass_explosion 0.9
      sparkle 0.35

      map amplitude, to: :speed, gain: 4.0, range: 0.4..4.0, curve: :sqrt
      map frequency_band(:low), to: :size, gain: 6.0, range: 2.0..8.0, curve: :sqrt
      map beat_pulse, to: :bass_explosion, gain: 1.2, range: 0.3..1.8
    end

    layer :blob_outline do
      type :radial_blob
      blend :add
      opacity 0.65
      segments 192
      radius 0.42
      wobble 0.2

      map fft_spectrum => :spectrum
      map amplitude, to: :wobble, gain: 2.8, range: 0.08..0.75, curve: :sqrt
      map frequency_band(:low), to: :radius, gain: 0.8, range: 0.36..0.72
    end

    layer :title do
      type :text
      content "UNYO"
      font_size 72
      color "#f8fbff"
      glow_strength 0.08
      map beat_pulse, to: :glow_strength, range: 0.08..0.42, attack: 1.0, release: 0.2
    end
  end
end
