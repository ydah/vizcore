# Vizcore

Vizcore is a Ruby gem for building audio-reactive visuals with a Ruby-first workflow.

Current implementation status: **Phase 0 skeleton** (CLI + Rack/WebSocket server + WebGL frontend boilerplate).

## Quick Start

```bash
# Run from this repository
ruby -Ilib exe/vizcore start examples/basic.rb
```

Open `http://127.0.0.1:4567` in a browser.  
The page initializes WebGL and renders a wireframe cube driven by dummy frame data.

## CLI Commands

```bash
vizcore start SCENE_FILE [--host 127.0.0.1] [--port 4567] [--audio-source mic|file|dummy] [--audio-file path]
vizcore new PROJECT_NAME
vizcore devices [audio|midi]
```

### File Audio Source

```bash
# WAV
vizcore start examples/basic.rb --audio-source file --audio-file spec/fixtures/audio/pulse16_mono.wav

# MP3/FLAC (decoded via ffmpeg)
vizcore start examples/basic.rb --audio-source file --audio-file path/to/set.mp3
```

When using `--audio-source file`, `--audio-file` is required and must point to an existing file.

## Requirements

- Ruby 3.2+
- For `--audio-source file` with `.mp3` / `.flac`: `ffmpeg` must be installed and available on `PATH`

## Project Scaffold

```bash
vizcore new my_show
cd my_show
vizcore start scenes/basic.rb
```

Generated files:

- `README.md`
- `scenes/basic.rb`
- `shaders/`

## Development

```bash
rspec
```

Note: in this environment, `bundle install` may fail without external network access.

## License

MIT
