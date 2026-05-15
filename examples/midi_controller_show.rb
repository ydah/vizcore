# frozen_string_literal: true

# MIDI controller showcase: pads switch scenes, knobs control global shader uniforms.
Vizcore.define do
  set :global_intensity, 0.65
  set :global_color, 0.15

  midi :controller, device: :default

  scene :midi_warmup do
    layer :ribbon do
      shader :waveform_ribbon
      blend :screen
      effect :bloom
      map mid, to: :effect_intensity, range: 0.08..0.24
    end

    layer :title do
      type :text
      content "MIDI CONTROL"
      font_size 72
      color "#e8fbff"
      glow_strength 0.16
      blend :screen
      map beat_pulse, to: :glow_strength, range: 0.12..0.65
    end
  end

  scene :midi_drop do
    layer :stars do
      shader :starfield
      blend :screen
      effect :glitch
      map high, to: :effect_intensity, range: 0.1..0.65
    end

    layer :drop_text do
      type :text
      content "DROP"
      font_size 118
      color "#fff1d6"
      glow_strength 0.25
      blend :add
      map beat_pulse, to: :glow_strength, range: 0.25..1.0
    end
  end

  scene :midi_crystal do
    layer :crystal do
      shader :ruby_crystal
      facets 7.0
      refraction 0.44
      blend :screen
      map bass, to: :refraction, gain: 0.9, range: 0.32..0.82
      map mid, to: :facets, gain: 1.8, range: 5.0..10.0
    end
  end

  midi_map note: 36 do
    switch_scene :midi_warmup
  end

  midi_map note: 37 do
    switch_scene :midi_drop
  end

  midi_map note: 38 do
    switch_scene :midi_crystal
  end

  midi_map cc: 1 do |value|
    set :global_intensity, value / 127.0
  end

  midi_map cc: 2 do |value|
    set :global_color, value / 127.0
  end
end
