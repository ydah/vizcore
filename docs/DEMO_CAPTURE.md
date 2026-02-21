# Demo Asset Refresh Guide

This document covers demo asset refresh for Phase 5 (`5-11`).

## Current Assets

- `docs/assets/demo.gif` (README embedded animation)
- `docs/assets/demo-poster.png` (static poster)

## Scenario Coverage

- `examples/intro_drop.rb` (scene transition flow)
- `examples/midi_scene_switch.rb` (MIDI switch flow)
- `examples/custom_shader.rb` (custom shader flow)

## Local Refresh

Run:

```bash
scripts/generate_demo_assets.sh
```

The script writes:

- `docs/assets/demo.gif`
- `docs/assets/demo-poster.png`

## Validation Checklist

- `README.md` demo image points to `docs/assets/demo.gif`
- `git status` contains updated assets when refreshed
- Demo still renders correctly on GitHub README view
