# frozen_string_literal: true

Vizcore.define do
  scene :groove do
    layer :background do
      shader :bass_tunnel
      opacity 1.0
      effect :feedback
      effect_intensity 0.72
      rotation_speed 1.4
    end

    layer :wireframe do
      type :wireframe_cube
      blend :add
      map fft_spectrum => :deform
      map frequency_band(:mid) => :color_shift
      map frequency_band(:low) => :rotation_speed
    end

    layer :particles do
      type :particle_field
      count 4200
      blend :add
      size 3.8
      effect :chromatic
      effect_intensity 0.7
      map amplitude => :speed
      map frequency_band(:low) => :size
      map frequency_band(:high) => :effect_intensity
    end

    layer :title do
      type :text
      content "FILE AUDIO DEMO"
      font_size 64
      color "#f2f7ff"
      glow_strength 0.18
      map beat? => :glow_strength
    end
  end

  scene :drop do
    layer :background do
      shader :kaleidoscope
      opacity 0.95
      effect :glitch
      effect_intensity 0.86
      rotation_speed 2.4
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
      content "DROP"
      font_size 92
      color "#eaffff"
      glow_strength 0.32
      map beat? => :glow_strength
    end
  end

  transition from: :groove, to: :drop do
    trigger { beat_count >= 32 || frame_count >= 720 }
    effect :crossfade, duration: 1.0
  end
end
