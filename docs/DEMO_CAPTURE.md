# Demo Capture Checklist

This document covers Phase 5 demo-video preparation (`5-11`).

## Target Output

- 30-60s short demo clip (README/GitHub release embedding)
- Optional GIF excerpt (10-15s)

## Scenario Script

1. `vizcore new demo_show` and open generated scene.
2. Run `vizcore start examples/intro_drop.rb`.
3. Show transition behavior (`intro -> drop`).
4. Run `vizcore start examples/midi_scene_switch.rb`.
5. Trigger scene switch via MIDI event (or simulated event in development setup).
6. Run `vizcore start examples/custom_shader.rb`.
7. Show custom GLSL layer reacting to audio.

## Recording Setup

- Capture browser window and terminal logs side-by-side.
- Use fixed viewport size (for consistent README embed).
- Use audio source:
  - Preferred: `--audio-source file --audio-file <known fixture/audio track>`
  - Fallback: `--audio-source dummy` for deterministic visuals.

## Validation Before Publish

- Confirm no runtime errors in terminal.
- Confirm WebSocket connection status is stable.
- Confirm visuals react to beat/amplitude and transitions.
- Export mp4 and verify playback quality.

## README Embed

- Upload video/gif to repository release assets or hosted location.
- Add demo section to README with:
  - short caption
  - link to full video
- Replace `docs/assets/demo-placeholder.svg` with captured GIF thumbnail or static poster frame.
