# frozen_string_literal: true

# External-track preset for lo-fi hiphop / chill beats.
# Works well with softer transients and mid-range textures.
Vizcore.define do
  scene :lofi_room do
    layer :background do
      shader :gradient_pulse
      opacity 1.0
      effect :bloom
      effect_intensity 0.28
      rotation_speed 0.35
      map frequency_band(:low) => :effect_intensity
    end

    layer :rings do
      shader :spectrum_rings
      opacity 0.34
      effect :chromatic
      effect_intensity 0.18
      map frequency_band(:mid) => :effect_intensity
    end

    layer :dust do
      type :particle_field
      count 2200
      blend :add
      size 2.1
      opacity 0.65
      map amplitude => :speed
      map frequency_band(:high) => :size
    end

    layer :wireframe do
      type :wireframe_cube
      opacity 0.32
      map fft_spectrum => :deform
      map frequency_band(:mid) => :color_shift
      map amplitude => :rotation_speed
    end

    layer :title do
      type :text
      content "LO-FI"
      font_size 54
      color "#edf4ff"
      glow_strength 0.08
      map beat? => :glow_strength
    end
  end
end
