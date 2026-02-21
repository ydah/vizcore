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
vizcore start SCENE_FILE [--host 127.0.0.1] [--port 4567]
vizcore new PROJECT_NAME
vizcore devices [audio|midi]
```

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
