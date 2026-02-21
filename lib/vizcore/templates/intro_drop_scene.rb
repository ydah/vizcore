# frozen_string_literal: true

# {{project_name}} transition example.
Vizcore.define do
  scene :intro do
    layer :background do
      shader :gradient_pulse
      map frequency_band(:low) => :intensity
      map beat? => :flash
    end

    layer :geometry do
      type :wireframe_cube
      map fft_spectrum => :deform
      map amplitude => :rotation_speed
    end
  end

  scene :drop do
    layer :particles do
      type :particle_field
      count 5000
      map amplitude => :speed
      map frequency_band(:high) => :size
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
    trigger { beat_count >= 64 }
    effect :crossfade, duration: 2.0
  end
end
