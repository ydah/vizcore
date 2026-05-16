# Vizcore Examples

Run the browser gallery for launch commands and scene metadata:

```bash
vizcore gallery
```

Most examples also work directly:

```bash
vizcore start examples/basic.rb
vizcore start examples/vj_techno_warehouse.rb --audio-source mic
vizcore start examples/vj_techno_warehouse.rb --audio-source file --audio-file examples/assets/complex_demo_loop.wav
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

## VJ Set Examples

Ready-to-run scenes grouped by genre / mood. All scenes accept live mic input
or any audio file. `B` toggles Blackout, `F` toggles Freeze, and scenes that
declare tap tempo use Space.

| File | Genre / Mood | BPM | Scenes | Notes |
|---|---|---|---|---|
| `vj_techno_warehouse.rb` | Techno / Warehouse | 128-140 | 4 | wireframe + particles |
| `vj_dnb_jungle.rb` | Drum & Bass / Jungle | 170-180 | 3 | kick/snare/hihat split |
| `vj_ambient_chill_room.rb` | Ambient / Chill | 60-90 | 2 | beatless, drone-friendly |
| `vj_hiphop_cipher.rb` | HipHop / Cipher | 85-100 | 3 | text-forward |
| `vj_jpop_idol_live.rb` | J-POP / Idol | 130-180 | 4 | color fields + tap tempo |
| `vj_synthwave_retro.rb` | Synthwave / Retro | 100-120 | 3 | circle and line primitives |
| `vj_glitch_industrial.rb` | Glitch / Industrial | n/a | 3 | feedback + difference blend |
| `vj_festival_mainstage.rb` | EDM / Mainstage | 124-132 | 5 | uses `extends:` and `group` |

Use `examples/vj_festival_mainstage.yml` as a manifest pattern for file-audio
rehearsal. Replace `audio_file` with your set recording or switch to
`audio_source: mic` for live input.
