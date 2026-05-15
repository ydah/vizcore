# frozen_string_literal: true

# {{project_name}} Ruby conference visual starter.
Vizcore.define do
  scene :rubykaigi do
    layer :ruby_grid do
      shader :neon_grid
      opacity 0.72
      blend :screen
      map frequency_band(:mid) => :intensity
    end

    layer :ruby_pulse do
      type :wireframe_cube
      blend :add
      map amplitude => :rotation_speed, range: 0.5..3.2
      map fft_spectrum => :deform
      map frequency_band(:high) => :color_shift
    end

    layer :title do
      type :text
      content "{{project_name}}"
      font_size 88
      color "#e11d48"
      glow_strength 0.35
      map beat? => :flash
    end
  end
end
