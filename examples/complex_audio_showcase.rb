# frozen_string_literal: true

# Recommended audio file for this scene:
#   examples/assets/complex_demo_loop.wav
Vizcore.define do
  scene :build do
    layer :rings do
      shader :spectrum_rings
      opacity 0.88
      effect :feedback
      effect_intensity 0.08
      map frequency_band(:low) => :rotation_speed
    end

    layer :grid do
      shader :neon_grid
      opacity 0.28
      blend :add
      vj_effect :mirror
      effect_intensity 0.18
      map frequency_band(:high) => :effect_intensity
    end

    layer :particles do
      type :particle_field
      count 3800
      blend :add
      opacity 0.74
      size 2.2
      map amplitude => :speed
      map frequency_band(:low) => :size
    end

    layer :wireframe do
      type :wireframe_cube
      blend :add
      opacity 0.9
      map fft_spectrum => :deform
      map frequency_band(:high) => :color_shift
      map frequency_band(:mid) => :rotation_speed
    end

    layer :title do
      type :text
      content "SYNCED SHOWCASE"
      font_size 56
      color "#e8f8ff"
      glow_strength 0.12
      map beat? => :glow_strength
    end
  end

  scene :lift do
    layer :background do
      shader :bass_tunnel
      opacity 0.94
      effect :feedback
      effect_intensity 0.16
      map frequency_band(:low) => :rotation_speed
      map frequency_band(:mid) => :effect_intensity
    end

    layer :grid do
      shader :neon_grid
      opacity 0.34
      blend :add
      vj_effect :color_shift
      effect_intensity 0.22
      map frequency_band(:high) => :effect_intensity
    end

    layer :particles do
      type :particle_field
      count 6800
      blend :add
      size 3.6
      effect :chromatic
      effect_intensity 0.18
      map amplitude => :speed
      map frequency_band(:low) => :size
      map frequency_band(:high) => :effect_intensity
    end

    layer :wireframe do
      type :wireframe_cube
      blend :add
      opacity 0.78
      map fft_spectrum => :deform
      map frequency_band(:high) => :color_shift
      map frequency_band(:low) => :rotation_speed
    end

    layer :title do
      type :text
      content "LIFT"
      font_size 72
      color "#eefbff"
      glow_strength 0.16
      map beat? => :glow_strength
    end
  end

  scene :drop do
    layer :bg do
      shader :kaleidoscope
      opacity 0.98
      effect :glitch
      effect_intensity 0.65
      map frequency_band(:low) => :rotation_speed
      map frequency_band(:high) => :effect_intensity
    end

    layer :flash do
      shader :glitch_flash
      opacity 0.8
      blend :add
      map amplitude => :param_intensity
      map frequency_band(:high) => :param_flash
    end

    layer :storm do
      type :particle_field
      count 9000
      blend :add
      size 4.8
      vj_effect :pixelate
      effect_intensity 0.55
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
      content "DROP"
      font_size 94
      color "#f2fdff"
      glow_strength 0.25
      map beat? => :glow_strength
    end
  end

  scene :afterglow do
    layer :bars do
      shader :audio_bars
      opacity 1.0
      effect :bloom
      effect_intensity 0.18
      bar_count 28
      floor_glow 0.12
      map frequency_band(:low) => :effect_intensity
    end

    layer :dust do
      type :particle_field
      count 2200
      blend :add
      opacity 0.38
      size 1.9
      map amplitude => :speed
      map frequency_band(:high) => :size
    end

    layer :wireframe do
      type :wireframe_cube
      blend :add
      opacity 0.24
      map fft_spectrum => :deform
      map frequency_band(:mid) => :color_shift
      map amplitude => :rotation_speed
    end

    layer :title do
      type :text
      content "AFTERGLOW"
      font_size 52
      color "#edf5ff"
      glow_strength 0.08
      map beat? => :glow_strength
    end
  end

  scene :breakdown do
    layer :background do
      shader :neon_grid
      opacity 0.22
      effect :bloom
      effect_intensity 0.12
      rotation_speed 0.18
      map frequency_band(:mid) => :effect_intensity
    end

    layer :rings do
      shader :spectrum_rings
      opacity 0.26
      effect :feedback
      effect_intensity 0.06
      map frequency_band(:low) => :rotation_speed
    end

    layer :dust do
      type :particle_field
      count 1800
      blend :add
      opacity 0.46
      size 1.8
      map amplitude => :speed
      map frequency_band(:high) => :size
    end

    layer :wireframe do
      type :wireframe_cube
      opacity 0.22
      map fft_spectrum => :deform
      map frequency_band(:mid) => :color_shift
      map amplitude => :rotation_speed
    end

    layer :title do
      type :text
      content "BREAKDOWN"
      font_size 46
      color "#e6f0ff"
      glow_strength 0.06
      map beat? => :glow_strength
    end
  end

  transition from: :build, to: :lift do
    trigger { beat_count >= 24 || frame_count >= 900 }
    effect :crossfade, duration: 0.9
  end

  transition from: :lift, to: :drop do
    trigger { beat_count >= 16 || frame_count >= 540 }
    effect :crossfade, duration: 1.0
  end

  transition from: :drop, to: :afterglow do
    trigger { beat_count >= 24 || frame_count >= 900 }
    effect :crossfade, duration: 1.1
  end

  transition from: :afterglow, to: :breakdown do
    trigger { beat_count >= 12 || frame_count >= 420 }
    effect :crossfade, duration: 1.0
  end

  transition from: :breakdown, to: :build do
    trigger { beat_count >= 16 || frame_count >= 720 }
    effect :crossfade, duration: 1.2
  end
end
