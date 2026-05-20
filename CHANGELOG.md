# Changelog

All notable changes to this project are documented in this file.

The format is based on Keep a Changelog and this project follows Semantic Versioning.

## [Unreleased]

## [1.1.0] - 2026-05-20

### Added

- Added extended shape DSL primitives, custom shape registration, dynamic expansion, canvas rendering, arcs, and grouped shape validation.
- Added browser controls for editing custom shape parameters and mapping them to runtime sources.
- Added the Ruby WASM playground for trying Vizcore scenes in the browser.

### Improved

- Improved custom shape reliability with parameter metadata validation, risky payload warnings, path segment limits, static expansion caching, and adaptive path flattening tolerance.
- Simplified the README into a smaller quick-start and reference entry point.

## [1.0.0] - 2026-05-20

### Added

- Expanded the Ruby DSL for musical timing, scene sequencing, reusable styles/themes, scene inheritance, layer styling, blending, and source-driven reactivity.
- Added richer audio-reactive sources, including onset, percussive confidence, beat confidence, BPM locking, tap tempo, audio normalization, and musical frequency band aliases.
- Added shader and visual effect workflows with new built-in presets, shader parameter schemas, custom shader scaffolding, generated shader docs, hot reload, and browser shader error reporting.
- Added browser control surfaces for live operation, including the HUD controls, Audio Inspector, performance monitor, operator panel, projector mode, scene shortcuts, and emergency Blackout/Freeze controls.
- Added CLI workflows for demos, project templates, galleries, diagnostics, validation, inspection, snapshots, and software-rendered image sequences.
- Expanded bundled examples, documentation, packaged assets, and public Ruby DSL type signatures.

### Improved

- Improved live reliability and diagnostics with WebSocket protocol versioning, latency probes, dropped-frame visibility, stale audio-frame backpressure handling, and repeatable audio fixtures.
- Improved installed gem contents so examples, browser assets, docs, and RBS files are available after installation.

## 0.1.0 (2026-02-23)

- Initial release.
