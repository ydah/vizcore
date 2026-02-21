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

## Examples

- `examples/basic.rb`
- `examples/intro_drop.rb`
- `examples/midi_scene_switch.rb`
- `examples/custom_shader.rb`

## Development

```bash
bundle exec rspec
```

## License

MIT
