# frozen_string_literal: true

# External-track preset for EDM / festival house / big-room style songs.
# Usage:
#   vizcore start examples/presets/edm.rb --audio-source file --audio-file path/to/track.wav
Vizcore.define do
  scene :build do
    layer :tunnel do
      shader :bass_tunnel
      opacity 0.96
      effect :feedback
      effect_intensity 0.45
      map frequency_band(:low) => :rotation_speed
      map frequency_band(:mid) => :effect_intensity
    end

    layer :grid do
      shader :neon_grid
      opacity 0.38
      blend :add
      vj_effect :mirror
      effect_intensity 0.25
      map frequency_band(:high) => :effect_intensity
    end

    layer :particles do
      type :particle_field
      count 6000
      blend :add
      size 3.2
      vj_effect :color_shift
      effect_intensity 0.35
      map amplitude => :speed
      map frequency_band(:low) => :size
      map frequency_band(:high) => :effect_intensity
    end

    layer :wireframe do
      type :wireframe_cube
      blend :add
      map fft_spectrum => :deform
      map frequency_band(:high) => :color_shift
      map frequency_band(:mid) => :rotation_speed
    end

    layer :title do
      type :text
      content "BUILD"
      font_size 56
      color "#e8fbff"
      glow_strength 0.1
      map beat? => :glow_strength
    end
  end

  scene :drop do
    layer :kaleido do
      shader :kaleidoscope
      opacity 0.98
      effect :glitch
      effect_intensity 0.7
      map frequency_band(:low) => :rotation_speed
      map frequency_band(:high) => :effect_intensity
    end

    layer :flash do
      shader :glitch_flash
      opacity 0.7
      blend :add
      map amplitude => :param_intensity
      map frequency_band(:high) => :param_flash
    end

    layer :storm do
      type :particle_field
      count 11_000
      blend :add
      size 5.4
      vj_effect :pixelate
      effect_intensity 0.55
      map amplitude => :speed
      map frequency_band(:low) => :size
      map frequency_band(:mid) => :effect_intensity
    end

    layer :wireframe do
      type :wireframe_cube
      blend :add
      map fft_spectrum => :deform
      map frequency_band(:high) => :color_shift
      map frequency_band(:low) => :rotation_speed
    end

    layer :title do
      type :text
      content "DROP"
      font_size 96
      color "#f7ffff"
      glow_strength 0.22
      map beat? => :glow_strength
    end
  end

  transition from: :build, to: :drop do
    trigger { beat_count >= 32 || frame_count >= 900 }
    effect :crossfade, duration: 1.0
  end
end
