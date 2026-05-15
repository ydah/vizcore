# Vizcore [![Gem Version](https://badge.fury.io/rb/vizcore.svg)](https://badge.fury.io/rb/vizcore) [![CI](https://github.com/ydah/vizcore/actions/workflows/main.yml/badge.svg)](https://github.com/ydah/vizcore/actions/workflows/main.yml)

Vizcore is a Ruby gem for building audio-reactive visuals with a Ruby DSL. Define scenes in pure Ruby, stream frames to the browser over WebSocket, and react to audio, beat, and MIDI in real time.

## Installation

```bash
gem install vizcore
```

Or add to your Gemfile:

```bash
bundle add vizcore
```

**System dependencies:**

macOS:
```bash
brew install portaudio ffmpeg   # ffmpeg only needed for MP3/FLAC input
brew install fftw               # optional: faster FFT
```

Ubuntu/Debian:
```bash
sudo apt install -y libportaudio2 libportaudio-dev ffmpeg
sudo apt install -y libfftw3-dev   # optional: faster FFT
```

## Quick Start

```bash
vizcore doctor
vizcore demo
vizcore start examples/basic.rb
```

Then open `http://127.0.0.1:4567`.


## Scene DSL

Scenes are written in plain Ruby. Layers map audio analysis values to visual parameters:

```ruby
Vizcore.define do
  scene :intro do
    layer :wireframe do
      type :wireframe_cube
      map amplitude => :rotation_speed
      map fft_spectrum => :deform
      map frequency_band(:high) => :color_shift
    end
  end

  scene :drop do
    layer :particles do
      type :particle_field
      count 3600
      map amplitude => :speed
      map frequency_band(:low) => :size
    end

    layer :title do
      type :text
      content "DROP"
      font_size 96
      map beat? => :flash
    end
  end

  transition from: :intro, to: :drop do
    trigger { beat_count >= 64 }
    effect :crossfade, duration: 1.4
  end
end
```

Mapping options can exaggerate small analysis values, clamp them into useful visual ranges, and smooth changes over time:

```ruby
layer :liquid do
  shader :liquid_wobble
  wobble 0.25
  warp 0.45

  map amplitude, to: :wobble, gain: 3.5, range: 0.12..1.4, curve: :sqrt
  map frequency_band(:low), to: :warp, gain: 2.2, range: 0.25..2.4
  map beat_pulse, to: :effect_intensity, range: 0.08..0.35
end
```

Available transform options are `gain`, `range`, `min`, `max`, `curve`, `attack`, and `release`. `curve` supports `:linear`, `:sqrt`, and `:square`. Existing mappings such as `map amplitude => :speed` continue to work.

For a more music-oriented style, `react_to` groups the same mappings by source:

```ruby
layer :particles do
  type :particle_field

  react_to bass do
    change :size, gain: 4.0, range: 2.0..8.0, curve: :sqrt
  end

  react_to beat do
    trigger :burst
  end
end
```

`react_to` is additive syntax; it serializes to the same mapping model as `map`.

Layers can choose their compositing mode with `blend`. Supported modes are `:alpha` / `:normal`, `:add`, `:multiply`, `:screen`, and `:difference`:

```ruby
layer :sparks do
  type :particle_field
  blend :screen
  map treble, to: :sparkle
end
```

Frequency bands can be written with musical aliases when that reads better in a scene:

```ruby
map bass, to: :size      # same as frequency_band(:low)
map mid, to: :twist
map treble, to: :sparkle # same as frequency_band(:high)
```

### Custom GLSL Shaders

```ruby
layer :wave_shader do
  type :shader
  glsl "shaders/custom_wave.frag"
  map amplitude => :param_intensity
  map frequency_band(:low) => :param_bass
  map beat? => :param_flash
end
```

Custom fragment shaders must be GLSL ES 3.00 and can use these audio uniforms:

- `u_amplitude`
- `u_bass` / `u_mid` / `u_high`
- `u_beat`
- `u_beat_pulse`
- `u_bpm`
- `u_fft[32]`
- `u_fft_size`
- `u_param_<name>`

For backward compatibility, a DSL target like `:param_intensity` is also exposed as `u_param_intensity`.

### MIDI Scene Switching

```ruby
Vizcore.define do
  midi :controller, device: :default

  scene :warmup do
    layer :grid do
      shader :neon_grid
      map frequency_band(:mid) => :intensity
    end
  end

  midi_map note: 36 do
    switch_scene :impact
  end

  midi_map cc: 1 do |value|
    set :global_intensity, value / 127.0
  end
end
```

## CLI

```bash
vizcore start SCENE_FILE [--host 127.0.0.1] [--port 4567] [--audio-source mic|file|dummy] [--audio-file PATH] [--audio-device INDEX_OR_NAME] [--noise-gate RMS] [--projector]
vizcore demo [--host 127.0.0.1] [--port 4567] [--projector]
vizcore doctor
vizcore validate SCENE_FILE
vizcore inspect SCENE_FILE
vizcore new PROJECT_NAME
vizcore devices [audio|midi]
```

### Audio Sources

| Source | Description |
|--------|-------------|
| `mic` | Live microphone input (default) |
| `file` | File playback — `.wav` directly, `.mp3`/`.flac` via `ffmpeg` |
| `dummy` | Silent source for layout testing |

```bash
# Microphone
vizcore start scene.rb --audio-source mic

# Specific microphone device
vizcore devices audio
vizcore start scene.rb --audio-source mic --audio-device 5

# Raise this if a quiet room still moves the visual
vizcore start scene.rb --audio-source mic --audio-device 5 --noise-gate 0.03

# WAV file
vizcore start scene.rb --audio-source file --audio-file track.wav

# MP3/FLAC (requires ffmpeg)
vizcore start scene.rb --audio-source file --audio-file set.mp3
```

When using file source, the HUD exposes **Play Audio** / **Pause Audio** controls and shows BPM, Beat, and Beat Count.

The browser HUD also includes an Audio Inspector with amplitude, sub/low/mid/high meters, FFT preview bars, a performance monitor for FPS/frame/latency/drop/audio/shader/reconnect health, shader compile error overlay, emergency Blackout/Freeze controls, and Visual Gain, Bass Boost, Smoothing, Beat Hold, and Wobble controls for adapting visual response to different tracks and input levels. Use `--projector` or open `/projector` when the browser output should hide operator UI, and open `/control` for a separate operator panel.

`vizcore demo` starts a bundled scene with bundled audio, so it is the quickest way to verify a fresh installation.

## Requirements

- Ruby `>= 3.2`
- `portaudio` for microphone input
- `ffmpeg` on `PATH` when using `.mp3` or `.flac` file input
- `fftw3` (optional) — Vizcore falls back to pure-Ruby FFT automatically when unavailable

## Examples

| File | Description |
|------|-------------|
| `examples/basic.rb` | Single wireframe cube layer |
| `examples/intro_drop.rb` | Beat-triggered scene transition |
| `examples/file_audio_demo.rb` | File audio source walkthrough |
| `examples/complex_audio_showcase.rb` | Dense multi-layer showcase |
| `examples/rhythm_geometry.rb` | Single large morphing geometric pattern scene with drum-reactive motion |
| `examples/midi_scene_switch.rb` | MIDI-driven scene switching |
| `examples/custom_shader.rb` | Custom GLSL shader with audio mapping |
| `examples/unyo_liquid.rb` | Organic liquid wobble scene with FFT blob and particles |

## Development

```bash
bundle exec rspec
npm --prefix frontend test
```


## License

MIT
