# frozen_string_literal: true

Vizcore.define do
  scene :shader_art do
    layer :wave_shader do
      type :shader
      glsl "shaders/custom_wave.frag"
      map amplitude => :param_intensity
      map frequency_band(:low) => :param_bass
      map beat? => :param_flash
      vj_effect "mirror"
      effect_intensity 0.15
    end

    layer :title do
      type :text
      content "VIZCORE"
      font_size 84
      glow_strength 0.08
      color "#f8fbff"
    end
  end
end
