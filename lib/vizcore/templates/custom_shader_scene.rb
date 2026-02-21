# frozen_string_literal: true

# {{project_name}} custom GLSL shader example.
Vizcore.define do
  scene :shader_art do
    layer :kaleidoscope do
      type :shader
      glsl "../shaders/custom_wave.frag"
      map amplitude => :param_intensity
      map frequency_band(:low) => :param_bass
      map beat? => :param_flash
      vj_effect "pixelate"
      effect_intensity 0.2
    end

    layer :title do
      type :text
      content "{{project_name}}"
      font_size 84
      glow_strength 0.08
      color "#f5f9ff"
    end
  end
end
