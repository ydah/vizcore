# frozen_string_literal: true

# External-track preset for techno / hard groove / minimal techno.
# Designed for steady kicks and repetitive hats with strong low-end pulse.
Vizcore.define do
  scene :drive do
    layer :tunnel do
      shader :bass_tunnel
      opacity 0.98
      effect :glitch
      effect_intensity 0.35
      map frequency_band(:low) => :rotation_speed
      map frequency_band(:high) => :effect_intensity
    end

    layer :grid do
      shader :neon_grid
      opacity 0.5
      blend :add
      vj_effect :mirror
      effect_intensity 0.4
      map frequency_band(:mid) => :effect_intensity
    end

    layer :strobe do
      shader :glitch_flash
      opacity 0.58
      blend :add
      map amplitude => :param_intensity
      map frequency_band(:high) => :param_flash
    end

    layer :particles do
      type :particle_field
      count 7600
      blend :add
      size 3.4
      vj_effect :pixelate
      effect_intensity 0.42
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
      content "TECHNO"
      font_size 58
      color "#ecffff"
      glow_strength 0.14
      map beat? => :glow_strength
    end
  end
end
