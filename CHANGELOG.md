# Changelog

All notable changes to this project are documented in this file.

The format is based on Keep a Changelog and this project follows Semantic Versioning.

## [Unreleased]

### Added

- Release verification automation (`rake release:verify`, gem content verification script).
- Cross-platform smoke report artifacts and summary generation in GitHub Actions.
- Runtime diagnostics with typed errors and contextual error formatting.
- FFT backend selection (`auto` / `ruby` / `fftw`) with automatic Ruby fallback.

## [0.1.0] - 2026-02-21

### Added

- Core CLI commands: `start`, `new`, `devices`.
- Rack + Puma server and faye-websocket transport.
- Audio sources: mic, file (wav/mp3/flac), dummy; MIDI input support.
- Analysis pipeline: FFT, band split, beat detection, BPM estimator, smoothing.
- DSL scene/layer/transition/midi_map support with hot reload.
- WebGL frontend layers, shaders, post effects, particle/geometry/text/VJ rendering.
- Example scenes and project scaffold templates.
