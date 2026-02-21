# Getting Started

This guide covers local setup and first-run commands for `vizcore`.

## 1. Prerequisites

### macOS (Homebrew)

```bash
brew install portaudio ffmpeg
# optional (recommended for faster FFT): brew install fftw
```

### Ubuntu/Debian

```bash
sudo apt update
sudo apt install -y libportaudio2 libportaudio-dev ffmpeg
# optional (recommended for faster FFT): sudo apt install -y libfftw3-dev
```

### Ruby

- Ruby `3.2+`
- Bundler

## 2. Install and Boot

### Run from this repository

```bash
bundle install
bundle exec ruby -Ilib exe/vizcore start examples/basic.rb
```

Open `http://127.0.0.1:4567`.

### Project scaffold

```bash
bundle exec ruby -Ilib exe/vizcore new my_show
cd my_show
vizcore start scenes/basic.rb
```

## 3. Audio Source Selection

### Microphone input

```bash
vizcore start examples/basic.rb --audio-source mic
```

### File input (WAV)

```bash
vizcore start examples/basic.rb --audio-source file --audio-file spec/fixtures/audio/pulse16_mono.wav
```

### File input (MP3/FLAC via ffmpeg)

```bash
vizcore start examples/basic.rb --audio-source file --audio-file path/to/set.mp3
```

### Dummy source fallback

```bash
vizcore start examples/basic.rb --audio-source dummy
```

## 4. Device Discovery

```bash
vizcore devices audio
vizcore devices midi
```

## 5. Useful Example Scenes

```bash
vizcore start examples/intro_drop.rb
vizcore start examples/midi_scene_switch.rb
vizcore start examples/custom_shader.rb
```

## 6. Troubleshooting

- `Audio file not found`: check `--audio-file` path.
- `.mp3` / `.flac` fails: confirm `ffmpeg -version` works.
- No mic signal on macOS: allow microphone permission for the Ruby process/terminal app.
- Web page does not update: check terminal logs and browser devtools console.
