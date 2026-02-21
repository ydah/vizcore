# frozen_string_literal: true

Vizcore.define do
  scene :intro do
    layer :background do
      shader :gradient_pulse
      map frequency_band(:low) => :intensity
      map beat? => :flash
    end

    layer :wireframe do
      type :wireframe_cube
      map amplitude => :rotation_speed
      map fft_spectrum => :deform
    end
  end

  scene :drop do
    layer :particles do
      type :particle_field
      count 6000
      map amplitude => :speed
      map frequency_band(:high) => :size
    end
  end

  transition from: :intro, to: :drop do
    trigger { beat_count >= 64 }
    effect :crossfade, duration: 1.8
  end
end
