# frozen_string_literal: true

Vizcore.define do
  scene :groove do
    layer :background do
      shader :spectrum_rings
      opacity 0.92
    end

    layer :particles do
      type :particle_field
      count 3200
      blend :add
      map amplitude => :speed
      map frequency_band(:low) => :size
    end

    layer :title do
      type :text
      content "FILE AUDIO DEMO"
      font_size 64
      color "#f2f7ff"
      glow_strength 0.22
    end
  end

  scene :drop do
    layer :flash do
      shader :glitch_flash
      map amplitude => :param_intensity
      map frequency_band(:high) => :param_flash
      opacity 0.9
    end

    layer :wireframe do
      type :wireframe_cube
      blend :add
      map fft_spectrum => :deform
      map frequency_band(:high) => :color_shift
      map amplitude => :rotation_speed
    end
  end

  transition from: :groove, to: :drop do
    trigger { beat_count >= 48 || frame_count >= 420 }
    effect :crossfade, duration: 1.0
  end

  transition from: :drop, to: :groove do
    trigger { beat_count >= 96 || frame_count >= 960 }
    effect :crossfade, duration: 1.0
  end
end
