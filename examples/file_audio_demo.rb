# frozen_string_literal: true

Vizcore.define do
  scene :groove do
    layer :background do
      shader :neon_grid
      opacity 1.0
    end

    layer :wireframe do
      type :wireframe_cube
      blend :add
      map fft_spectrum => :deform
      map frequency_band(:high) => :color_shift
      map amplitude => :rotation_speed
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
    layer :background do
      shader :kaleidoscope
      opacity 0.95
    end

    layer :wireframe do
      type :wireframe_cube
      blend :add
      map fft_spectrum => :deform
      map frequency_band(:high) => :color_shift
      map amplitude => :rotation_speed
    end
    layer :title do
      type :text
      content "DROP"
      font_size 92
      color "#eaffff"
      glow_strength 0.32
    end
  end

  transition from: :groove, to: :drop do
    trigger { beat_count >= 32 || frame_count >= 720 }
    effect :crossfade, duration: 1.0
  end
end
