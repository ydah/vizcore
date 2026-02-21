# frozen_string_literal: true

# {{project_name}} transition example.
Vizcore.define do
  scene :intro do
    layer :background do
      shader :neon_grid
      opacity 0.82
    end

    layer :geometry do
      type :wireframe_cube
      map fft_spectrum => :deform
      map amplitude => :rotation_speed
      map frequency_band(:high) => :color_shift
    end
  end

  scene :drop do
    layer :particles do
      type :particle_field
      count 3600
      map amplitude => :speed
      map frequency_band(:low) => :size
      map beat? => :flash
    end

    layer :title do
      type :text
      content "{{project_name}}"
      font_size 96
      map beat? => :flash
    end
  end

  transition from: :intro, to: :drop do
    trigger { beat_count >= 64 || frame_count >= 360 }
    effect :crossfade, duration: 1.4
  end
end
