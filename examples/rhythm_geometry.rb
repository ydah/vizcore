# frozen_string_literal: true

# Recommended audio file for this scene:
#   examples/assets/complex_demo_loop.wav
# Drum-only sync check:
#   spec/fixtures/audio/kick_120bpm.wav
# Motion is gated by audio level, so silence holds the shape still.
Vizcore.define do
  scene :rhythm_geometry do
    layer :morphing_geometry do
      shader :unyo_geometry
      sides 7.0
      scale 1.02
      wobble 0.72
      twist 0.84
      pulse 0.0
      kick 0.0
      snare 0.0
      line_glow 0.38
      effect :bloom
      effect_intensity 0.42

      map beat_count => :seed
      map beat_pulse, to: :pulse, range: 0.0..1.65, attack: 1.0, release: 0.14
      map amplitude, to: :scale, gain: 0.7, range: 0.82..1.25, curve: :sqrt, attack: 0.95, release: 0.18
      map frequency_band(:low), to: :kick, gain: 3.8, range: 0.0..1.45, curve: :sqrt, attack: 1.0, release: 0.08
      map frequency_band(:low), to: :wobble, gain: 3.0, range: 0.45..1.7, curve: :sqrt, attack: 0.95, release: 0.16
      map frequency_band(:mid), to: :twist, gain: 2.4, range: 0.55..2.4, curve: :sqrt
      map frequency_band(:high), to: :snare, gain: 2.2, range: 0.0..1.1, curve: :sqrt, attack: 1.0, release: 0.12
      map frequency_band(:high), to: :line_glow, gain: 2.0, range: 0.28..1.3
      map frequency_band(:high), to: :effect_intensity, gain: 1.4, range: 0.24..0.78
    end
  end
end
