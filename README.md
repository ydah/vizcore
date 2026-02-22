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
vizcore start examples/basic.rb
```

Then open `http://127.0.0.1:4567`.

For full setup, device listing, and troubleshooting, see [GETTING_STARTED.md](docs/GETTING_STARTED.md).

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
vizcore start SCENE_FILE [--host 127.0.0.1] [--port 4567] [--audio-source mic|file|dummy] [--audio-file PATH]
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

# WAV file
vizcore start scene.rb --audio-source file --audio-file track.wav

# MP3/FLAC (requires ffmpeg)
vizcore start scene.rb --audio-source file --audio-file set.mp3
```

When using file source, the HUD exposes **Play Audio** / **Pause Audio** controls and shows BPM, Beat, and Beat Count.

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
| `examples/midi_scene_switch.rb` | MIDI-driven scene switching |
| `examples/custom_shader.rb` | Custom GLSL shader with audio mapping |

## Development

```bash
bundle exec rspec
```


## License

MIT
