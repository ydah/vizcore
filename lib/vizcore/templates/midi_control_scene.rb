# frozen_string_literal: true

# {{project_name}} MIDI mapping example.
Vizcore.define do
  midi :controller, device: :default

  scene :warmup do
    layer :warm_bg do
      shader :neon_grid
      map frequency_band(:mid) => :intensity
    end
  end

  scene :impact do
    layer :impact_bg do
      shader :glitch_flash
      map beat? => :flash
      map amplitude => :effect_intensity
    end
  end

  midi_map note: 36 do
    switch_scene :impact
  end

  midi_map note: 38 do
    switch_scene :warmup
  end

  midi_map cc: 1 do |value|
    set :global_intensity, value / 127.0
  end
end
