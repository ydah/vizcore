# Vizcore

Vizcore is a Ruby gem for building audio-reactive visuals with a Ruby DSL.

## What You Get

- `vizcore start` to run Rack + WebSocket server and stream frames to browser WebGL.
- Audio input sources: `mic`, `file`, `dummy`.
- File input supports `.wav` directly and `.mp3`/`.flac` via `ffmpeg`.
- MIDI device listing and `midi_map` runtime actions.
- Scene transitions, hot-reload, built-in shaders, custom GLSL layers.

## Quick Start

```bash
# from repository root
bundle exec ruby -Ilib exe/vizcore start examples/basic.rb
```

Then open `http://127.0.0.1:4567`.

For full setup (system dependencies, scaffold flow, troubleshooting), see `GETTING_STARTED.md`.

## CLI

```bash
vizcore start SCENE_FILE [--host 127.0.0.1] [--port 4567] [--audio-source mic|file|dummy] [--audio-file path]
vizcore new PROJECT_NAME
vizcore devices [audio|midi]
```

### File Audio Source

```bash
# WAV
vizcore start examples/basic.rb --audio-source file --audio-file spec/fixtures/audio/pulse16_mono.wav

# MP3/FLAC (decoded through ffmpeg)
vizcore start examples/basic.rb --audio-source file --audio-file path/to/set.mp3
```

When `--audio-source file` is selected, `--audio-file` is required.

## Requirements

- Ruby `>= 3.2`
- `ffmpeg` on `PATH` when using file source with `.mp3` / `.flac`
- `fftw3` is optional for faster FFT processing; when unavailable, Vizcore uses a Pure Ruby FFT fallback automatically.

## Examples

- `examples/basic.rb`
- `examples/intro_drop.rb`
- `examples/midi_scene_switch.rb`
- `examples/custom_shader.rb`

## Development

```bash
bundle exec rspec
```

## API Documentation

- YARD generation and stats commands are documented in `docs/YARD.md`.

## Demo

![Vizcore demo](docs/assets/demo.gif)

Try the same scenes locally:

```bash
vizcore start examples/intro_drop.rb --audio-source file --audio-file spec/fixtures/audio/pulse16_mono.wav
vizcore start examples/midi_scene_switch.rb --audio-source dummy
vizcore start examples/custom_shader.rb --audio-source file --audio-file spec/fixtures/audio/pulse16_mono.wav
```

Re-generate demo assets with:

```bash
scripts/generate_demo_assets.sh
```

## Error Handling Notes

- Runtime components emit contextual error logs (for example scene reload and MIDI runtime failures).
- Audio inputs keep diagnostic state in `last_error` while preserving fallback behavior (silence/dummy source).

## Cross-Platform Validation

- Cross-platform smoke verification and artifact format are documented in `docs/CROSS_PLATFORM_TESTING.md`.

## Release Process

- Release checklist: `docs/RELEASE.md`
- Demo capture checklist (README embed asset prep): `docs/DEMO_CAPTURE.md`
- Changelog: `CHANGELOG.md`
- Tag-driven release workflow: `.github/workflows/release.yml`

## Gem Packaging Policy

- Runtime files only are packaged in the gem: `lib/`, `exe/`, `frontend/index.html`, `frontend/src/`, `examples/`, `sig/`, `README.md`, `GETTING_STARTED.md`, `LICENSE.txt`.
- Development-only files are excluded from gem payload (for example `spec/`, `.github/`, and `frontend/test/`).
- RubyGems MFA is required for release operations (`rubygems_mfa_required=true`).

## License

MIT
