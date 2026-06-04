# Vizcore Examples

Run the browser gallery for launch commands and scene metadata:

```bash
vizcore gallery
```

Most examples also work directly:

```bash
vizcore start examples/basic.rb
vizcore start examples/audio_inspector.rb --audio-source mic
vizcore start examples/audio_inspector.rb --audio-source mic --noise-gate 0.001
vizcore start examples/neon_grid_mesh.rb --audio-source file --audio-file examples/assets/complex_demo_loop.wav
```

## Core Examples

| File | Description |
|---|---|
| `basic.rb` | Single wireframe cube layer |
| `intro_drop.rb` | Beat-triggered scene transition |
| `file_audio_demo.rb` | File audio source walkthrough |
| `complex_audio_showcase.rb` | Dense multi-layer showcase |
| `rhythm_geometry.rb` | Drum-reactive geometric pattern |
| `ruby_crystal_show.rb` | Ruby-themed crystal visual |
| `parser_visualizer.rb` | Parser-themed token and AST sketch |
| `live_coding_minimal.rb` | Tiny live-coding scene |
| `club_intro_drop.rb` | Intro, build, drop flow |
| `shader_playground.rb` | Focused shader params example |
| `audio_inspector.rb` | Audio feature visualization |
| `readme_demo.rb` | Minimal beat pulse to ring radius demo |
| `midi_scene_switch.rb` | MIDI scene switching |
| `midi_controller_show.rb` | MIDI pads and CC controls |
| `kansai_rubykaigi_visual.rb` | Event showcase visual |
| `custom_shader.rb` | Custom GLSL shader |
| `unyo_liquid.rb` | Liquid wobble and FFT blob |

## Visual Set Examples

Ready-to-run scenes grouped by visual motif. All scenes accept live mic input
or any audio file. `B` toggles Blackout, `F` toggles Freeze, and scenes that
declare tap tempo use Space.

| File | Visual Motif | BPM | Scenes | Notes |
|---|---|---|---|---|
| `neon_grid_mesh.rb` | Neon grid, wireframe mesh, particles | 128-140 | 4 | long-loopable |
| `star_tunnel_cubes.rb` | Star tunnel, particle flow, reactive cubes | 170-180 | 3 | kick/snare/hihat split |
| `nebula_ribbon_bloom.rb` | Soft ribbon, breathing halo, nebula particles | 60-90 | 2 | beatless, drone-friendly |
| `stage_text_pulse.rb` | Large stage text, radial pulses, dot accents | 85-100 | 3 | text-forward |
| `confetti_color_burst.rb` | Gradient fields, penlight grid, confetti burst | 130-180 | 4 | color fields + tap tempo |
| `neon_sun_lasers.rb` | Neon sun, highway grid, laser fan | 100-120 | 3 | circle and line primitives |
| `glitch_scan_feedback.rb` | Scan waterfall, feedback tear, white flash | n/a | 3 | feedback + difference blend |
| `riser_crystal_show.rb` | Countdown rings, riser tunnel, crystal drop | 124-132 | 5 | uses `extends:` and `group` |

Use `examples/riser_crystal_show.yml` as a manifest pattern for file-audio
rehearsal. Replace `audio_file` with your set recording or switch to
`audio_source: mic` for live input.
