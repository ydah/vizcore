# Vizcore [![Gem Version](https://badge.fury.io/rb/vizcore.svg)](https://badge.fury.io/rb/vizcore) [![CI](https://github.com/ydah/vizcore/actions/workflows/main.yml/badge.svg)](https://github.com/ydah/vizcore/actions/workflows/main.yml)

Vizcore is a Ruby gem for building audio-reactive visuals with a Ruby DSL. Define scenes in Ruby, stream them to the browser, and react to audio, beat, MIDI, OSC, and live operator controls.

## Installation

```bash
gem install vizcore
```

Or add it to a project:

```bash
bundle add vizcore
```

System dependencies:

```bash
# macOS
brew install portaudio ffmpeg
brew install fftw # optional, faster FFT

# Ubuntu/Debian
sudo apt install -y libportaudio2 libportaudio-dev ffmpeg
sudo apt install -y libfftw3-dev # optional, faster FFT
```

`ffmpeg` is only required for MP3/FLAC audio input and MP4 render output. Vizcore falls back to pure-Ruby FFT when `fftw3` is unavailable.

## Quick Start

```bash
vizcore doctor
vizcore demo
```

Open `http://127.0.0.1:4567`.

<p align="center">
  <img src="docs/assets/vizcore-demo.gif" width="640" alt="Animated Vizcore demo where detected beats expand concentric rings" />
</p>

Start your own scene file:

```bash
vizcore start scene.rb
```

## Scene Example

Scenes are plain Ruby. Layers describe visuals, and mappings connect audio features to visual parameters.

```ruby
Vizcore.define do
  scene :intro do
    layer :rings do
      shader :spectrum_rings
      map amplitude, to: :intensity, gain: 2.0, range: 0.1..1.0
      map bass, to: :scale, range: 0.8..1.4
      map beat_pulse, to: :flash
    end

    layer :title do
      type :text
      content "VIZCORE"
      font_size 96
      fill "#ffffff"
      map beat?, to: :opacity, range: 0.35..1.0
    end
  end

  scene :drop do
    layer :particles do
      type :particle_field
      count 3600
      blend :screen
      map bass, to: :size, range: 2.0..8.0, curve: :sqrt
      map treble, to: :sparkle
    end
  end

  transition from: :intro, to: :drop do
    on_bar 8
    effect :crossfade, duration: 1.0
  end
end
```

Common audio sources in mappings include `amplitude`, `bass`, `mid`, `treble`, `fft_spectrum`, `beat?`, `beat_pulse`, `beat_confidence`, `onset(:low)`, `kick`, `snare`, and `hihat`.

Mapping options include `gain`, `range`, `min`, `max`, `curve`, `deadzone`, `attack`, and `release`.

## Live Operation

The browser UI includes scene switching, audio meters, FFT preview, shader parameter sliders, performance stats, MIDI Learn, tap tempo, Blackout, Freeze, and projector mode.

Useful routes:

| Route | Use |
| --- | --- |
| `/` | Visual output with operator controls |
| `/projector` | Clean visual output for projection |
| `/control` | Separate operator panel |

For repeatable show startup, use a manifest:

```yaml
scene: scenes/show.rb
audio:
  source: file
  file: audio/set.wav
control_preset: controls/live.json
sync:
  osc:
    port: 9000
```

```bash
vizcore start --manifest vizcore.yml
```

## CLI

Core commands:

```bash
vizcore demo
vizcore start SCENE_FILE
vizcore start --manifest vizcore.yml
vizcore gallery
vizcore doctor
vizcore devices audio
vizcore devices midi
vizcore validate SCENE_FILE
vizcore inspect SCENE_FILE
```

Rendering and capture:

```bash
vizcore snapshot SCENE_FILE --out screenshot.png
vizcore render SCENE_FILE --out frames --frames 120 --fps 30
vizcore render SCENE_FILE --audio-source file --audio-file track.wav --out movie.mp4
vizcore capture SCENE_FILE --out browser.png
```

Reference and scaffolding:

```bash
vizcore new PROJECT_NAME
vizcore layers
vizcore dsl-docs
vizcore shader new NAME
vizcore shader-docs
vizcore plugin new NAME
```

Audio input:

```bash
# microphone input, default
vizcore start scene.rb --audio-source mic

# specific microphone device
vizcore devices audio
vizcore start scene.rb --audio-source mic --audio-device 5

# audio file input
vizcore start scene.rb --audio-source file --audio-file track.wav

# deterministic replay of recorded analysis features
vizcore record-features track.wav --out features.json
vizcore start scene.rb --feature-file features.json
```

## Examples

Run the bundled gallery:

```bash
vizcore gallery
```

Or start one directly:

```bash
vizcore start examples/basic.rb
vizcore start examples/intro_drop.rb
vizcore start examples/audio_inspector.rb
vizcore start examples/vj_techno_warehouse.rb --audio-source file --audio-file examples/assets/complex_demo_loop.wav
```

The full example list is in [examples/README.md](examples/README.md).

## Documentation

- Project site: <https://ydah.github.io/vizcore/>
- Changelog: [CHANGELOG.md](CHANGELOG.md)
- Runtime layer reference: `vizcore layers`
- Ruby DSL reference: `vizcore dsl-docs`
- Shader uniform reference: `vizcore shader-docs`

## Development

```bash
bundle exec rspec
npm --prefix frontend test
bundle exec rake release:verify
```

## Requirements

- Ruby `>= 3.2`
- `portaudio` for microphone input
- `ffmpeg` for MP3/FLAC input and MP4 output
- `fftw3` optional for faster FFT

## License

MIT
