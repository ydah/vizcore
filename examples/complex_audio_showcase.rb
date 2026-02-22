# frozen_string_literal: true

# Recommended audio file for this scene:
#   examples/assets/complex_demo_loop.wav
Vizcore.define do
  scene :build do
    layer :rings do
      shader :spectrum_rings
      opacity 0.96
      effect :feedback
      effect_intensity 0.35
      map frequency_band(:low) => :rotation_speed
      map frequency_band(:mid) => :effect_intensity
    end

    layer :grid do
      shader :neon_grid
      opacity 0.45
      blend :add
      vj_effect :mirror
      effect_intensity 0.35
      map frequency_band(:high) => :effect_intensity
    end

    layer :particles do
      type :particle_field
      count 5200
      blend :add
      size 2.8
      effect :chromatic
      effect_intensity 0.4
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
      content "SYNCED SHOWCASE"
      font_size 56
      color "#e8f8ff"
      glow_strength 0.12
      map beat? => :glow_strength
    end
  end

  scene :drop do
    layer :bg do
      shader :kaleidoscope
      opacity 0.98
      effect :glitch
      effect_intensity 0.65
      map frequency_band(:low) => :rotation_speed
      map frequency_band(:high) => :effect_intensity
    end

    layer :flash do
      shader :glitch_flash
      opacity 0.8
      blend :add
      map amplitude => :param_intensity
      map frequency_band(:high) => :param_flash
    end

    layer :storm do
      type :particle_field
      count 9000
      blend :add
      size 4.8
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
      font_size 94
      color "#f2fdff"
      glow_strength 0.25
      map beat? => :glow_strength
    end
  end

  transition from: :build, to: :drop do
    trigger { beat_count >= 24 || frame_count >= 900 }
    effect :crossfade, duration: 1.0
  end
end
