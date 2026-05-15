# Changelog

All notable changes to this project are documented in this file.

The format is based on Keep a Changelog and this project follows Semantic Versioning.

## [Unreleased]

- Add concept, architecture, DSL guide, cookbook, one-line walkthrough, and troubleshooting docs.
- Add initial RBS signatures for the public Ruby DSL.
- Add shader parameter schema metadata through the Ruby `param` layer DSL.
- Add `vizcore shader new NAME` for generating custom GLSL starter shaders.
- Add `vizcore shader-docs` for generated custom GLSL uniform reference output.
- Add browser latency probes for RTT and Ruby/browser clock-offset measurement.
- Drop stale realtime `audio_frame` sends when a browser WebSocket connection is backpressured.
- Add `vizcore.frame.v1` protocol version to WebSocket message envelopes.
- Document the Ruby-to-browser WebSocket frame protocol.
- Add `vizcore gallery` for browsing bundled examples in a local browser view.
- Add hot reload for referenced custom GLSL shader files.
- Add explicit `vizcore start --reload` / `--no-reload` control for scene hot reload.
- Add `vizcore render` for writing a software-rendered PNG image sequence.
- Add `vizcore snapshot` for writing a software-rendered PNG preview of a scene.
- Add `vizcore new --template` scaffold variants for minimal, shader, MIDI, live-set, and rubykaigi starters.
- Add `/control` for a separate HUD/operator panel alongside projector output.
- Add projector output mode via `vizcore start --projector`, `vizcore demo --projector`, and `/projector`.
- Add a browser HUD performance monitor for FPS, frame time, WebSocket latency, dropped-frame estimates, audio processing time, shader compile time, and reconnect count.
- Add browser HUD Blackout/Freeze emergency controls for live output.
- Add explicit layer `blend` DSL support and frontend compositing for alpha/add/multiply/screen/difference modes.
- Add `react_to` layer DSL for grouping source-driven `change` and `trigger` mappings.
- Add `vizcore demo` for launching a bundled scene with bundled audio.
- Show GLSL compile/link failures in a browser shader error overlay while keeping fallback rendering.
- Add `vizcore doctor`, `vizcore validate`, and `vizcore inspect` CLI commands for setup and scene diagnostics.
- Add musical frequency band aliases (`bass`, `mid`, `treble`, `sub`, `low`, `high`) to layer mappings and transition triggers.
- Add a browser HUD Audio Inspector with amplitude, band meters, FFT preview bars, and peak frequency display.

## 0.1.0 (2026-02-23)

- Initial release.
