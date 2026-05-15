# frozen_string_literal: true

# File-audio friendly intro -> build -> drop flow.
Vizcore.define do
  scene :intro do
    layer :grid do
      shader :neon_grid
      opacity 0.75
      map mid, to: :effect_intensity, range: 0.08..0.28
    end

    layer :title do
      type :text
      content "INTRO"
      font_size 84
      map beat_pulse, to: :glow_strength, range: 0.12..0.65
    end
  end

  scene :build do
    layer :rings do
      shader :spectrum_rings
      blend :screen
      map bass, to: :effect_intensity, gain: 1.4, range: 0.16..0.5
    end

    layer :particles do
      type :particle_field
      count 2200
      blend :add
      map amplitude, to: :speed, range: 0.4..3.2
      map treble, to: :sparkle, range: 0.0..0.9
    end
  end

  scene :drop do
    layer :tunnel do
      shader :bass_tunnel
      blend :screen
    end

    layer :flash do
      shader :glitch_flash
      blend :add
      map beat_pulse, to: :intensity, range: 0.2..1.0, attack: 1.0, release: 0.08
    end

    layer :drop_text do
      type :text
      content "DROP"
      font_size 122
      blend :screen
      map beat_pulse, to: :glow_strength, range: 0.3..1.0
    end
  end

  transition from: :intro, to: :build do
    trigger { beat_count >= 32 || frame_count >= 240 }
    effect :crossfade, duration: 1.0
  end

  transition from: :build, to: :drop do
    trigger { beat_count >= 64 || frame_count >= 480 }
    effect :flash, duration: 0.35
  end
end
