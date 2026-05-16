# Vizcore [![Gem Version](https://badge.fury.io/rb/vizcore.svg)](https://badge.fury.io/rb/vizcore) [![CI](https://github.com/ydah/vizcore/actions/workflows/main.yml/badge.svg)](https://github.com/ydah/vizcore/actions/workflows/main.yml)

Vizcore is a Ruby gem for building audio-reactive visuals with a Ruby DSL. Define scenes in pure Ruby, stream frames to the browser over WebSocket, and react to audio, beat, and MIDI in real time.

## Installation

```bash
gem install vizcore
```

Or add to your Gemfile:

```bash
bundle add vizcore
```

**System dependencies:**

macOS:
```bash
brew install portaudio ffmpeg   # ffmpeg is needed for MP3/FLAC input and MP4 render output
brew install fftw               # optional: faster FFT
```

Ubuntu/Debian:
```bash
sudo apt install -y libportaudio2 libportaudio-dev ffmpeg
sudo apt install -y libfftw3-dev   # optional: faster FFT
```

## Quick Start

```bash
vizcore doctor
vizcore demo
vizcore start examples/basic.rb
```

Then open `http://127.0.0.1:4567`.


## Scene DSL

Scenes are written in plain Ruby. Layers map audio analysis values to visual parameters:

```ruby
Vizcore.define do
  scene :intro do
    layer :wireframe do
      type :wireframe_cube
      map amplitude => :rotation_speed
      map fft_spectrum => :deform
      map frequency_band(:high) => :color_shift
    end
  end

  scene :drop do
    layer :particles do
      type :particle_field
      count 3600
      map amplitude => :speed
      map frequency_band(:low) => :size
    end

    layer :waveform do
      type :waveform
      source :audio
      style :ribbon
      map amplitude, to: :height, range: 0.2..0.7
    end

    layer :spectrogram do
      type :spectrogram
      scroll :vertical
      map amplitude, to: :gain, range: 0.8..3.0
    end

    layer :mesh do
      type :mesh
      geometry :icosahedron
      material :wireframe
      map bass, to: :scale, range: 0.8..1.4
      map high, to: :deform
    end

    layer :rings do
      circle count: 8 do
        radius 100
        stroke 2
        map bass, to: :radius, range: 40..180
      end
    end

    layer :title do
      type :text
      content "DROP\nNOW"
      font "Inter Black"
      font_size 96
      letter_spacing 4
      align :center
      fill "#ffffff"
      stroke width: 2, color: "#111111"
      shadow color: "rgba(0, 0, 0, 0.45)", blur: 18
      map beat? => :flash
    end

    layer :logo do
      type :svg
      file "assets/logo.svg"
      scale 0.9
      map bass, to: :scale, range: 0.8..1.15
    end

    layer :photo do
      type :image
      file "assets/noise.png"
      fit :cover
      blend :screen
      map amplitude, to: :opacity, range: 0.25..0.85
    end

    layer :footage do
      type :video
      file "assets/loop.mp4"
      fit :cover
      map beat?, to: :invert
    end
  end

  transition from: :intro, to: :drop do
    on_bar 16
    effect :crossfade, duration: 1.4
  end
end
```

Mapping options can exaggerate small analysis values, clamp them into useful visual ranges, and smooth changes over time:

```ruby
layer :liquid do
  shader :liquid_wobble
  wobble 0.25
  warp 0.45

  map amplitude, to: :wobble, gain: 3.5, range: 0.12..1.4, curve: :sqrt
  map frequency_band(:low), to: :warp, gain: 2.2, range: 0.25..2.4
  map onset(:high), to: :spark, range: 0.0..1.0
  map kick, to: :pulse, range: 0.0..1.0
  map beat_pulse, to: :effect_intensity, range: 0.08..0.35
end
```

Available transform options are `gain`, `range`, `min`, `max`, `curve`, `deadzone`, `attack`, and `release`. `curve` supports `:linear`, `:sqrt`, `:square`, and `:ease_out`. Existing mappings such as `map amplitude => :speed` continue to work.
Use block syntax when shaping a mapping reads better:

```ruby
map amplitude, to: :scale do
  gain 2.0
  range 0.8..1.6
  curve :ease_out
  smooth attack: 0.02, release: 0.18
  deadzone 0.05
end
```

Block syntax is additive and writes the same transform metadata as keyword
syntax. `deadzone` suppresses tiny values before gain and curve are applied;
`curve` also supports `:ease_out`.

For tracks with very different levels, opt in to adaptive feature
normalization at the top of the scene file:

```ruby
audio_normalize mode: :adaptive, window: 3.0, target: 0.85, floor: 0.05
```

This keeps `amplitude` and FFT-driven mappings in a repeatable range without
changing the default analysis behavior.

When the detected tempo should not drift during a prepared file or live set,
lock BPM at the top of the scene file:

```ruby
bpm 128
bpm_lock true
```

When you want to set tempo by ear from the browser during a live set, opt in to
tap tempo and choose the keyboard key:

```ruby
tap_tempo key: :space
```

After two valid taps, Vizcore estimates BPM from recent intervals and applies it
as a locked BPM so beat-driven visuals stop drifting.

Browser keyboard shortcuts can also be declared in the scene file for operators
who do not have a MIDI controller:

```ruby
key "d" do
  switch_scene :drop
end

key "x" do
  blackout
end
```

For a more music-oriented style, `react_to` groups the same mappings by source:

```ruby
layer :particles do
  type :particle_field

  react_to bass do
    change :size, gain: 4.0, range: 2.0..8.0, curve: :sqrt
  end

  react_to beat do
    trigger :burst
  end
end
```

`react_to` is additive syntax; it serializes to the same mapping model as `map`.

Transitions can use explicit trigger blocks, or beat/bar helpers when that reads
closer to the structure of a track:

```ruby
transition from: :build, to: :drop do
  on_bar 8
  effect :flash, duration: 0.35
end
```

For simple song structure, `section` defines scenes in order and creates
beat-counted transitions between adjacent sections:

```ruby
section :intro, bars: 8 do
  layer :pulse do
    map amplitude => :scale
  end
end

section :drop, bars: 16 do
  layer :sparks do
    map beat? => :burst
  end
end
```

For file-backed shows or rehearsed sets, `timeline` can mark existing scenes at
ordered beat or second positions and generate the transitions:

```ruby
timeline do
  at beats(0), scene: :intro
  at bars(8), scene: :build
  at bars(16), scene: :drop
end
```

Layers can choose their compositing mode with `blend`. Supported modes are `:alpha` / `:normal`, `:add`, `:multiply`, `:screen`, and `:difference`:

```ruby
layer :sparks do
  type :particle_field
  blend :screen
  map treble, to: :sparkle
end
```

Waveform layers draw the current audio features as browser line geometry. Use
`style :line`, `:mirror`, or `:ribbon`; `source :audio` documents that the layer
uses the active audio stream:

```ruby
layer :scope do
  type :waveform
  source :audio
  style :ribbon
  map amplitude, to: :height, range: 0.2..0.7
end
```

Video layers embed MP4/WebM/OGV assets as muted looping textures. They share
`fit`, `scale`, `rotation`, `blend`, and post-effect params with image layers:

```ruby
layer :footage do
  type :video
  file "assets/loop.mp4"
  fit :cover
  map beat?, to: :invert
end
```

Spectrogram layers render a short scrolling FFT heatmap. Use `scroll :vertical`
for a waterfall view or `scroll :horizontal` when time should move left to right:

```ruby
layer :waterfall do
  type :spectrogram
  scroll :vertical
  bins 96
  history 128
  map amplitude, to: :gain, range: 0.8..3.0
end
```

Mesh layers render preset 3D wireframes without writing GLSL. Available
geometry presets are `:cube`, `:tetrahedron`, `:octahedron`, and
`:icosahedron`; use `material :wireframe`:

```ruby
layer :mesh do
  type :mesh
  geometry :icosahedron
  material :wireframe
  map bass, to: :scale, range: 0.8..1.4
  map high, to: :deform
end
```

Shape layers provide declarative circles and lines for scenes that do not need
custom GLSL. Shape-local mappings target the primitive inside the block:

```ruby
layer :rings do
  circle count: 8 do
    radius 100
    stroke 2
    map bass, to: :radius, range: 40..180
  end

  draw do
    line x1: 0, y1: 360, x2: 1280, y2: 360
  end
end
```

Layers can also apply browser-side post effects. Supported effects are
`:bloom`, `:glitch`, `:chromatic`, `:feedback`, `:motion_blur`, and `:crt`:

```ruby
layer :tunnel do
  shader :bass_tunnel
  effect :motion_blur
  map bass, to: :effect_intensity, range: 0.1..0.7
end
```

Reusable layer styles keep repeated visual params in one place:

```ruby
style :neon do
  palette "#00ffff", "#ff00aa", "#facc15"
  glow_strength 0.45
  blend :add
end

scene :drop do
  layer :title do
    type :text
    use_style :neon
    content "DROP"
  end
end
```

Themes provide scene-wide layer defaults:

```ruby
theme :ruby_night do
  palette "#e11d48", "#f59e0b", "#38bdf8"
  glow_strength 0.5
  blend :screen
end

scene :drop do
  use_theme :ruby_night

  layer :title do
    type :text
    content "DROP"
  end
end
```

Layer groups apply shared params to a subset of adjacent layers while keeping the
runtime payload as normal ordered layers:

```ruby
scene :drop do
  group :foreground do
    use_style :neon
    blend :add
    opacity 0.9

    layer(:particles) { type :particle_field }
    layer(:title) { type :text }
  end
end
```

Scenes can inherit shared layers from an earlier scene:

```ruby
scene :base do
  layer(:background) { shader :neon_grid }
end

scene :drop, extends: :base do
  layer(:particles) { type :particle_field }
end
```

Frequency bands can be written with musical aliases when that reads better in a scene:

```ruby
map bass, to: :size      # same as frequency_band(:low)
map mid, to: :twist
map treble, to: :sparkle # same as frequency_band(:high)
map beat_confidence, to: :sync_strength
```

### Custom GLSL Shaders

Built-in shader presets include `:gradient_pulse`, `:bass_tunnel`,
`:neon_grid`, `:kaleidoscope`, `:spectrum_rings`, `:liquid_wobble`,
`:audio_bars`, `:ruby_crystal`, `:starfield`, `:waveform_ribbon`,
`:unyo_geometry`, and `:glitch_flash`.

```ruby
layer :wave_shader do
  type :shader
  glsl "shaders/custom_wave.frag"
  param :intensity, default: 0.6, range: 0.0..2.0, step: 0.05
  map amplitude => :param_intensity
  map frequency_band(:low) => :param_bass
  map beat? => :param_flash
end
```

Path-style shader declarations are also accepted, so `shader "shaders/liquid.frag", reload: true` is equivalent to `glsl "shaders/liquid.frag"` for custom fragment shaders. When hot reload is enabled, Vizcore watches referenced GLSL files and pushes updated shader source to connected browsers.

Use `vizcore shader new liquid` to create `shaders/liquid.frag` with a GLSL ES
starter template.

Custom fragment shaders must be GLSL ES 3.00. Run `vizcore shader-docs`
to print the generated uniform reference. Common uniforms include:

- `u_amplitude`
- `u_bass` / `u_mid` / `u_high`
- `u_beat`
- `u_beat_pulse`
- `u_onset` / `u_low_onset` / `u_mid_onset` / `u_high_onset`
- `u_kick` / `u_snare` / `u_hihat`
- `u_bpm`
- `u_fft[32]`
- `u_fft_size`
- `u_param_<name>`
- `u_global_<name>`

For backward compatibility, a DSL target like `:param_intensity` is also exposed as `u_param_intensity`.
Runtime globals set with `set :global_intensity, 0.75` are exposed as `u_global_intensity`.
Use `param :name, default:, range:, step:` to attach numeric metadata for shader
params that can be surfaced by tooling.
The browser HUD turns this metadata into per-layer shader parameter sliders, so
declared params can be adjusted during a live run without editing the scene file.

### MIDI Scene Switching

```ruby
Vizcore.define do
  set :global_intensity, 0.65

  midi :controller, device: :default

  scene :warmup do
    layer :grid do
      shader :waveform_ribbon
      map frequency_band(:mid) => :intensity
    end
  end

  midi_map note: 36 do
    switch_scene :impact
  end

  midi_map cc: 1 do |value|
    set :global_intensity, value / 127.0
  end
end
```

## CLI

```bash
vizcore start SCENE_FILE [--host 127.0.0.1] [--port 4567] [--audio-source mic|file|dummy] [--audio-file PATH] [--audio-device INDEX_OR_NAME] [--feature-file features.json] [--noise-gate RMS] [--bpm BPM --bpm-lock] [--reload|--no-reload] [--projector]
vizcore demo [--host 127.0.0.1] [--port 4567] [--projector]
vizcore doctor
vizcore validate SCENE_FILE
vizcore inspect SCENE_FILE
vizcore snapshot SCENE_FILE [--audio-source dummy|file|mic] [--audio-file PATH] [--out screenshot.png]
vizcore render SCENE_FILE [--audio-source dummy|file|mic] [--audio-file PATH] [--out frames|movie.mp4] [--frames 60] [--fps 30]
vizcore record-features AUDIO_FILE [--out features.json] [--frames 300] [--fps 30]
vizcore gallery [--host 127.0.0.1] [--port 4568]
vizcore layers
vizcore dsl-docs
vizcore shader new NAME [--out shaders/name.frag]
vizcore shader-docs
vizcore new PROJECT_NAME [--template standard|minimal|shader|midi|live-set|rubykaigi]
vizcore devices [audio|midi]
```

### Audio Sources

| Source | Description |
|--------|-------------|
| `mic` | Live microphone input (default) |
| `file` | File playback — `.wav` directly, `.mp3`/`.flac` via `ffmpeg` |
| `dummy` | Silent source for layout testing |

```bash
# Microphone
vizcore start scene.rb --audio-source mic

# Specific microphone device
vizcore devices audio
vizcore start scene.rb --audio-source mic --audio-device 5

# Raise this if a quiet room still moves the visual
vizcore start scene.rb --audio-source mic --audio-device 5 --noise-gate 0.03

# WAV file
vizcore start scene.rb --audio-source file --audio-file track.wav

# MP3/FLAC (requires ffmpeg)
vizcore start scene.rb --audio-source file --audio-file set.mp3

# Recorded analysis features
vizcore record-features track.wav --out features.json --frames 300 --fps 30
vizcore start scene.rb --feature-file features.json
```

When using file source, the HUD exposes **Play Audio** / **Pause Audio** controls and shows BPM, Beat, and Beat Count.

The browser HUD also includes an Audio Inspector with amplitude, sub/low/mid/high meters, FFT preview bars, a performance monitor for FPS/frame/latency/drop/audio/shader/reconnect health, shader compile error overlay, emergency Blackout/Freeze controls, and Visual Gain, Bass Boost, Smoothing, Beat Hold, and Wobble controls for adapting visual response to different tracks and input levels. Reactivity controls can be saved, loaded, imported, and exported for repeatable HUD presets. MIDI Learn can bind Web MIDI note/CC/program messages to the current scene, Blackout/Freeze, or reactivity controls. Scene launcher entries can be selected with `1`-`9`, and scene-defined `key` mappings can switch scenes or toggle live controls. Use `--projector` or open `/projector` when the browser output should hide operator UI, and open `/control` for a separate operator panel.

`vizcore demo` starts a bundled scene with bundled audio, so it is the quickest way to verify a fresh installation.


`vizcore start scene.rb --reload` watches the scene file and pushes changes to connected browsers without restarting the server. Hot reload is enabled by default; use `--no-reload` when you want a fixed scene for a show.

Use `vizcore snapshot scene.rb --audio-source dummy --out screenshot.png` to create a software-rendered PNG preview for README, social cards, or quick visual checks without starting the browser.

Use `vizcore render scene.rb --audio-source file --audio-file track.wav --out frames --frames 120 --fps 30` to write a software-rendered PNG image sequence, or `--out movie.mp4` to encode the frames to MP4 with `ffmpeg`.

Use `vizcore record-features track.wav --out features.json --frames 300 --fps 30` to capture the same audio analysis values as JSON for debugging mappings or comparing tracks. Replay the file with `vizcore start scene.rb --feature-file features.json` when you want deterministic visual behavior without live audio input.

## Requirements

- Ruby `>= 3.2`
- `portaudio` for microphone input
- `ffmpeg` on `PATH` when using `.mp3` / `.flac` file input or `.mp4` render output
- `fftw3` (optional) — Vizcore falls back to pure-Ruby FFT automatically when unavailable

## Examples

Run `vizcore gallery` to open a browser gallery of bundled examples with scene counts, layer counts, audio-source hints, and launch commands.

| File | Description |
|------|-------------|
| `examples/basic.rb` | Single wireframe cube layer |
| `examples/intro_drop.rb` | Beat-triggered scene transition |
| `examples/file_audio_demo.rb` | File audio source walkthrough |
| `examples/complex_audio_showcase.rb` | Dense multi-layer showcase |
| `examples/rhythm_geometry.rb` | Single large morphing geometric pattern scene with drum-reactive motion |
| `examples/ruby_crystal_show.rb` | Ruby-themed crystal, particles, and title visual |
| `examples/parser_visualizer.rb` | Parser-themed token, AST, and reduce visual sketch |
| `examples/live_coding_minimal.rb` | Tiny scene for live-coding demos |
| `examples/club_intro_drop.rb` | Intro, build, and drop flow for rhythmic file input |
| `examples/shader_playground.rb` | Focused shader scene with declared params |
| `examples/audio_inspector.rb` | Audio bars and blob for analysis visualization |
| `examples/midi_scene_switch.rb` | MIDI-driven scene switching |
| `examples/midi_controller_show.rb` | MIDI pads for scenes and knobs for global shader intensity/color |
| `examples/kansai_rubykaigi_visual.rb` | Event showcase with ruby crystal, water ripple, and Kyoto-inspired pattern |
| `examples/custom_shader.rb` | Custom GLSL shader with audio mapping |
| `examples/unyo_liquid.rb` | Organic liquid wobble scene with FFT blob and particles |

## Development

```bash
bundle exec rspec
npm --prefix frontend test
```


## License

MIT
