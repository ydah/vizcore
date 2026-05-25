# frozen_string_literal: true

require "tmpdir"
require "vizcore/dsl/engine"
require "vizcore/dsl/transition_controller"

RSpec.describe Vizcore::DSL::Engine do
  describe ".define" do
    it "builds scenes and layers from the DSL block" do
      definition = described_class.define do
        audio :mic, device: :default, sample_rate: 44_100
        audio_normalize mode: :adaptive, window: 3.0, target: 0.8, floor: 0.05
        bpm 128
        bpm_lock true
        tap_tempo key: :t
        midi :controller, device: "Launchpad"
        set :global_intensity, 0.75

        scene :intro do
          layer :background do
            shader :gradient_pulse
            map frequency_band(:low) => :intensity
            map beat? => :flash
            map beat_confidence => :sync_strength
            map beat_pulse => :wobble
            map onset => :burst
            map onset(:high) => :spark
            map kick => :kick_flash
            map snare => :snare_flash
            map hihat => :hat_spark
          end
        end
      end

      expect(definition[:audio]).to eq([{ name: :mic, options: { device: :default, sample_rate: 44_100 } }])
      expect(definition[:analysis]).to eq(
        audio_normalize: { mode: :adaptive, window: 3.0, target: 0.8, floor: 0.05 },
        bpm: 128.0,
        bpm_lock: true,
        tap_tempo: { key: "t" }
      )
      expect(definition[:midi]).to eq([{ name: :controller, options: { device: "Launchpad" } }])
      expect(definition[:globals]).to eq(global_intensity: 0.75)
      expect(definition[:scenes].length).to eq(1)

      scene = definition[:scenes].first
      expect(scene[:name]).to eq(:intro)
      expect(scene[:layers].length).to eq(1)

      layer = scene[:layers].first
      expect(layer[:name]).to eq(:background)
      expect(layer[:type]).to eq(:shader)
      expect(layer[:shader]).to eq(:gradient_pulse)
      expect(layer[:mappings]).to include(
        { source: { kind: :frequency_band, band: :low }, target: :intensity },
        { source: { kind: :beat }, target: :flash },
        { source: { kind: :beat_confidence }, target: :sync_strength },
        { source: { kind: :beat_pulse }, target: :wobble },
        { source: { kind: :onset }, target: :burst },
        { source: { kind: :onset, band: :high }, target: :spark },
        { source: { kind: :kick }, target: :kick_flash },
        { source: { kind: :snare }, target: :snare_flash },
        { source: { kind: :hihat }, target: :hat_spark }
      )
    end

    it "builds browser keyboard mappings" do
      definition = described_class.define do
        key "d" do
          switch_scene :drop
        end

        key "B" do
          blackout
        end

        key " " do
          freeze
        end
      end

      expect(definition[:key_mappings]).to eq(
        [
          { key: "d", action: { type: :switch_scene, scene: "drop" } },
          { key: "b", action: { type: :live_control, control: :blackout } },
          { key: "space", action: { type: :live_control, control: :freeze } }
        ]
      )
    end

    it "builds mapping transforms from keyword and target hash syntax" do
      definition = described_class.define do
        scene :reactive do
          layer :liquid do
            shader :gradient_pulse
            map amplitude, to: :wobble, gain: 3.0, range: 0.1..1.2, curve: :sqrt
            map frequency_band(:low) => { to: :warp, gain: 2.0, min: 0.2, max: 2.5 }
            map beat_pulse => { to: :flash, range: [0.0, 1.0], attack: 1.0, release: 0.2 }
            map spectral_flux, to: :spark, threshold: 0.4, hysteresis: 0.1, hold: 0.2, decay: 0.8, curve: :smoothstep
          end
        end
      end

      layer = definition[:scenes].first[:layers].first

      expect(layer[:mappings]).to include(
        {
          source: { kind: :amplitude },
          target: :wobble,
          transform: { gain: 3.0, min: 0.1, max: 1.2, curve: :sqrt }
        },
        {
          source: { kind: :frequency_band, band: :low },
          target: :warp,
          transform: { gain: 2.0, min: 0.2, max: 2.5 }
        },
        {
          source: { kind: :beat_pulse },
          target: :flash,
          transform: { min: 0.0, max: 1.0, attack: 1.0, release: 0.2 }
        },
        {
          source: { kind: :spectral_flux },
          target: :spark,
          transform: { threshold: 0.4, hysteresis: 0.1, curve: :smoothstep, hold: 0.2, decay: 0.8 }
        }
      )
    end

    it "builds extended audio feature mapping sources" do
      definition = described_class.define do
        scene :features do
          layer :meters do
            type :geometry
            map peak => :peak_level
            map bpm_confidence => :tempo_lock
            map spectral_centroid => :brightness
            map spectral_rolloff => :rolloff
            map spectral_flatness => :noise
            map zero_crossing_rate => :crossings
          end
        end
      end

      mappings = definition[:scenes].first[:layers].first[:mappings]

      expect(mappings).to include(
        { source: { kind: :peak }, target: :peak_level },
        { source: { kind: :bpm_confidence }, target: :tempo_lock },
        { source: { kind: :spectral_centroid }, target: :brightness },
        { source: { kind: :spectral_rolloff }, target: :rolloff },
        { source: { kind: :spectral_flatness }, target: :noise },
        { source: { kind: :zero_crossing_rate }, target: :crossings }
      )
    end

    it "rejects unknown layer params in strict mode" do
      expect do
        described_class.define do
          strict!

          scene :strict_scene do
            layer :typo do
              type :geometry
              opactiy 0.5
            end
          end
        end
      end.to raise_error(ArgumentError, /unknown params in strict mode: opactiy/)
    end

    it "applies named styles to layer params" do
      definition = described_class.define do
        style :neon do
          color "#00ffff"
          palette "#00ffff", "#ff00aa"
          glow_strength 0.45
          blend :add
        end

        scene :styled do
          layer :title do
            type :text
            use_style :neon
            color "#ffffff"
          end
        end
      end

      expect(definition[:styles]).to eq(
        [
          {
            name: :neon,
            params: {
              color: "#00ffff",
              palette: %w[#00ffff #ff00aa],
              glow_strength: 0.45,
              blend: :add
            }
          }
        ]
      )

      params = definition[:scenes].first[:layers].first[:params]
      expect(params).to include(
        color: "#ffffff",
        palette: %w[#00ffff #ff00aa],
        glow_strength: 0.45,
        blend: :add
      )
    end

    it "applies scene themes as layer defaults" do
      definition = described_class.define do
        theme :ruby_night do
          palette "#e11d48", "#f59e0b", "#38bdf8"
          color "#e11d48"
          glow_strength 0.5
          blend :screen
        end

        scene :drop do
          use_theme :ruby_night

          layer :title do
            type :text
            color "#ffffff"
          end

          layer :sparks do
            type :particle_field
          end
        end
      end

      expect(definition[:themes]).to eq(
        [
          {
            name: :ruby_night,
            params: {
              palette: %w[#e11d48 #f59e0b #38bdf8],
              color: "#e11d48",
              glow_strength: 0.5,
              blend: :screen
            }
          }
        ]
      )

      scene = definition[:scenes].first
      expect(scene[:theme]).to eq(:ruby_night)

      title_params = scene[:layers][0][:params]
      sparks_params = scene[:layers][1][:params]
      expect(title_params).to include(color: "#ffffff", palette: %w[#e11d48 #f59e0b #38bdf8], glow_strength: 0.5, blend: :screen)
      expect(sparks_params).to include(color: "#e11d48", palette: %w[#e11d48 #f59e0b #38bdf8], glow_strength: 0.5, blend: :screen)
    end

    it "builds layer groups with shared params" do
      definition = described_class.define do
        style :glow do
          glow_strength 0.7
        end

        theme :night do
          palette "#111111", "#eeeeee"
          opacity 0.8
          blend :screen
        end

        scene :drop do
          use_theme :night

          group :foreground do
            use_style :glow
            blend :add
            opacity 0.9

            layer :particles do
              type :particle_field
              count 900
            end

            layer :title do
              type :text
              blend :screen
            end
          end
        end
      end

      particles, title = definition[:scenes].first[:layers]

      expect(particles[:params]).to include(
        group: :foreground,
        palette: %w[#111111 #eeeeee],
        glow_strength: 0.7,
        opacity: 0.9,
        blend: :add,
        count: 900
      )
      expect(title[:params]).to include(
        group: :foreground,
        palette: %w[#111111 #eeeeee],
        glow_strength: 0.7,
        opacity: 0.9,
        blend: :screen
      )
    end

    it "stores layer-specific palettes" do
      definition = described_class.define do
        scene :palette_show do
          layer :sparks do
            type :particle_field
            palette %w[#ff0055 #00ffff #facc15]
          end
        end
      end

      params = definition[:scenes].first[:layers].first[:params]
      expect(params[:palette]).to eq(%w[#ff0055 #00ffff #facc15])
    end

    it "rejects empty palettes" do
      expect do
        described_class.define do
          style :empty do
            palette " "
          end
        end
      end.to raise_error(ArgumentError, /palette requires at least one color/)
    end

    it "stores text presentation params" do
      definition = described_class.define do
        scene :titles do
          layer :headline do
            type :text
            content "DROP"
            font "Inter Black"
            align :center
            letter_spacing 4
            fill "#ffffff"
            stroke width: 2, color: "#111111"
            shadow color: "rgba(0, 0, 0, 0.45)", blur: 18
          end
        end
      end

      params = definition[:scenes].first[:layers].first[:params]
      expect(params).to include(
        content: "DROP",
        font: "Inter Black",
        align: :center,
        letter_spacing: 4.0,
        color: "#ffffff",
        stroke_width: 2.0,
        stroke_color: "#111111",
        shadow_color: "rgba(0, 0, 0, 0.45)",
        shadow_blur: 18.0
      )
    end

    it "stores asset file params for svg layers" do
      definition = described_class.define do
        scene :logo_scene do
          layer :logo do
            type :svg
            file "assets/logo.svg"
            scale 1.2
            map bass, to: :scale
          end
        end
      end

      layer = definition[:scenes].first[:layers].first
      expect(layer[:type]).to eq(:svg)
      expect(layer[:params]).to include(file: "assets/logo.svg", scale: 1.2)
      expect(layer[:mappings]).to include(
        source: { kind: :frequency_band, band: :low },
        target: :scale
      )
    end

    it "stores asset file params for image layers" do
      definition = described_class.define do
        scene :photo_scene do
          layer :photo do
            type :image
            file "assets/noise.png"
            fit :cover
            scale 1.1
            map amplitude, to: :opacity
          end
        end
      end

      layer = definition[:scenes].first[:layers].first
      expect(layer[:type]).to eq(:image)
      expect(layer[:params]).to include(file: "assets/noise.png", fit: :cover, scale: 1.1)
      expect(layer[:mappings]).to include(
        source: { kind: :amplitude },
        target: :opacity
      )
    end

    it "stores asset file params for video layers" do
      definition = described_class.define do
        scene :footage_scene do
          layer :footage do
            type :video
            file "assets/loop.mp4"
            fit :cover
            playback_rate 1.25
            map beat?, to: :invert
          end
        end
      end

      layer = definition[:scenes].first[:layers].first
      expect(layer[:type]).to eq(:video)
      expect(layer[:params]).to include(file: "assets/loop.mp4", fit: :cover, playback_rate: 1.25)
      expect(layer[:mappings]).to include(
        source: { kind: :beat },
        target: :invert
      )
    end

    it "stores waveform layer params and source" do
      definition = described_class.define do
        scene :audio_scope do
          layer :waveform do
            type :waveform
            source :audio
            style :ribbon
            height 0.6
            map amplitude, to: :height, range: 0.2..0.8
          end
        end
      end

      layer = definition[:scenes].first[:layers].first
      expect(layer[:type]).to eq(:waveform)
      expect(layer[:params]).to include(source: :audio, style: :ribbon, height: 0.6)
      expect(layer[:mappings]).to include(
        source: { kind: :amplitude },
        target: :height,
        transform: { min: 0.2, max: 0.8 }
      )
    end

    it "stores spectrogram layer params" do
      definition = described_class.define do
        scene :analysis do
          layer :spectrogram do
            type :spectrogram
            scroll :vertical
            bins 96
            history 128
            map amplitude, to: :gain, range: 0.8..3.0
          end
        end
      end

      layer = definition[:scenes].first[:layers].first
      expect(layer[:type]).to eq(:spectrogram)
      expect(layer[:params]).to include(scroll: :vertical, bins: 96, history: 128)
      expect(layer[:mappings]).to include(
        source: { kind: :amplitude },
        target: :gain,
        transform: { min: 0.8, max: 3.0 }
      )
    end

    it "stores preset mesh layer params" do
      definition = described_class.define do
        scene :mesh_scene do
          layer :mesh do
            type :mesh
            geometry :icosahedron
            material :wireframe
            scale 1.1
            map bass, to: :scale, range: 0.8..1.4
            map high, to: :deform
          end
        end
      end

      layer = definition[:scenes].first[:layers].first
      expect(layer[:type]).to eq(:mesh)
      expect(layer[:params]).to include(geometry: :icosahedron, material: :wireframe, scale: 1.1)
      expect(layer[:mappings]).to include(
        {
          source: { kind: :frequency_band, band: :low },
          target: :scale,
          transform: { min: 0.8, max: 1.4 }
        },
        {
          source: { kind: :frequency_band, band: :high },
          target: :deform
        }
      )
    end

    it "stores 2d shape primitives and scoped shape mappings" do
      definition = described_class.define do
        scene :shapes do
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
        end
      end

      layer = definition[:scenes].first[:layers].first
      expect(layer[:type]).to eq(:shape)
      expect(layer[:params][:shapes]).to eq(
        [
          { kind: :circle, count: 8, radius: 100, stroke: 2 },
          { kind: :line, x1: 0, y1: 360, x2: 1280, y2: 360 }
        ]
      )
      expect(layer[:mappings]).to include(
        source: { kind: :frequency_band, band: :low },
        target: :"shapes.0.radius",
        transform: { min: 40, max: 180 }
      )
    end

    it "stores extended shape primitives, transforms, and shape id mappings" do
      definition = described_class.define do
        scene :badge_scene do
          layer :badge do
            rect :panel, width: 320, height: 160, radius: 24 do
              fill "#111827"
              stroke width: 2, color: "#38bdf8"
              translate x: 100, y: 40
              rotate 15
              scale x: 1.2, y: 0.8
              opacity 0.75
              map beat_pulse, to: :scale, range: 1.0..1.4
            end

            polygon :triangle, points: [[0, 120], [-104, -60], [104, -60]]
            polyline points: [[-120, 0], [0, 80], [120, 0]]

            path :blob, detail: 8 do
              move_to 0, 100
              quad_to 80, 140, 120, 40
              close
            end

            bezier :curve, from: [-120, 0], control: [0, 100], to: [120, 0]

            star :spark, points: 5, radius: 80, inner_radius: 32 do
              map high, to: :opacity, range: 0.2..1.0
            end

            map bass, to: shape(:panel).rotate, range: -15..15
          end
        end
      end

      layer = definition[:scenes].first[:layers].first
      expect(layer[:type]).to eq(:shape)
      expect(layer[:params][:shape_schema_version]).to eq(2)
      expect(layer[:params][:shapes]).to include(
        hash_including(
          kind: :rect,
          id: :panel,
          fill: "#111827",
          stroke_width: 2.0,
          stroke_color: "#38bdf8",
          opacity: 0.75,
          transform: {
            translate: { x: 100.0, y: 40.0 },
            rotate: 15.0,
            scale: { x: 1.2, y: 0.8 }
          }
        ),
        hash_including(kind: :polygon, id: :triangle),
        hash_including(kind: :polyline, closed: false),
        hash_including(kind: :path, id: :blob, commands: [["M", 0, 100], ["Q", 80, 140, 120, 40], ["Z"]]),
        hash_including(kind: :path, id: :curve, commands: [["M", -120, 0], ["Q", 0, 100, 120, 0]]),
        hash_including(kind: :star, id: :spark)
      )
      expect(layer[:mappings]).to include(
        {
          source: { kind: :beat_pulse },
          target: :"shapes.0.transform.scale",
          transform: { min: 1.0, max: 1.4 }
        },
        {
          source: { kind: :frequency_band, band: :high },
          target: :"shapes.5.opacity",
          transform: { min: 0.2, max: 1.0 }
        },
        {
          source: { kind: :frequency_band, band: :low },
          target: :"shapes.0.transform.rotate",
          transform: { min: -15, max: 15 }
        }
      )
    end

    it "expands registered custom shapes into primitive shapes" do
      shape_class = Class.new do
        include Vizcore::Shape

        param :radius, default: 64

        def draw(ctx)
          ctx.draw do
            circle radius: ctx.param(:radius)

            group do
              translate x: 90, y: 0
              rect width: 40, height: 20
            end
          end
        end
      end
      Vizcore.register_shape :engine_spec_badge_shape, shape_class
      Vizcore.register_shape :engine_spec_diamond_shape do |ctx|
        radius = ctx.param(:radius, 50)
        ctx.polygon points: [[0, radius], [radius, 0], [0, -radius], [-radius, 0]]
      end

      definition = described_class.define do
        scene :custom_shape_scene do
          layer :generated do
            custom_shape :engine_spec_badge_shape, radius: 96 do
              fill "#22d3ee"
              map beat_pulse, to: :scale, range: 0.8..1.2
            end

            custom_shape :engine_spec_diamond_shape, radius: 48
          end
        end
      end

      layer = definition[:scenes].first[:layers].first
      expect(layer[:params][:shape_schema_version]).to eq(2)
      expect(layer[:params][:shapes]).to eq(
        [
          { kind: :circle, radius: 96, fill: "#22d3ee" },
          { kind: :rect, width: 40, height: 20, transform: { translate: { x: 90.0, y: 0.0 } }, fill: "#22d3ee" },
          { kind: :polygon, points: [[0, 48], [48, 0], [0, -48], [-48, 0]] }
        ]
      )
      expect(layer[:mappings]).to include(
        {
          source: { kind: :beat_pulse },
          target: :"shapes.0.transform.scale",
          transform: { min: 0.8, max: 1.2 }
        },
        {
          source: { kind: :beat_pulse },
          target: :"shapes.1.transform.scale",
          transform: { min: 0.8, max: 1.2 }
        }
      )
    end

    it "caches static custom shape expansions without sharing mutable primitives" do
      draw_count = 0
      shape_class = Class.new do
        define_singleton_method(:draw) do |ctx|
          draw_count += 1
          { kind: :circle, radius: ctx.param(:radius), dash: [4, 2] }
        end
      end
      Vizcore.register_shape :engine_spec_cached_shape, shape_class

      definition = described_class.define do
        scene :custom_shape_scene do
          layer :generated do
            custom_shape :engine_spec_cached_shape, radius: 64, static: true
            custom_shape :engine_spec_cached_shape, radius: 64, static: true
          end
        end
      end

      shapes = definition[:scenes].first[:layers].first[:params][:shapes]
      expect(draw_count).to eq(1)
      expect(shapes).to eq(
        [
          { kind: :circle, radius: 64, dash: [4, 2] },
          { kind: :circle, radius: 64, dash: [4, 2] }
        ]
      )
      expect(shapes[0]).not_to equal(shapes[1])
      expect(shapes[0][:dash]).not_to equal(shapes[1][:dash])
    end

    it "stores dynamic custom shapes for runtime expansion after mappings" do
      shape_class = Class.new do
        include Vizcore::Shape

        param :radius, default: 64, min: 10, max: 120, step: 1

        def draw(ctx)
          ctx.circle radius: ctx.param(:radius)
        end
      end
      Vizcore.register_shape :engine_spec_dynamic_shape, shape_class

      definition = described_class.define do
        scene :dynamic_custom_shape_scene do
          layer :generated do
            custom_shape :engine_spec_dynamic_shape, radius: 48, dynamic: true do
              fill "#22d3ee"
              rotate 15
              map bass, to: :radius, range: 24..96
              map beat_pulse, to: :scale, range: 0.8..1.2
            end
          end
        end
      end

      layer = definition[:scenes].first[:layers].first
      expect(layer[:params][:shapes]).to be_nil
      expect(layer[:params][:custom_shapes]).to contain_exactly(
        hash_including(
          name: :engine_spec_dynamic_shape,
          renderer: shape_class,
          params: { radius: 48 },
          style: { fill: "#22d3ee" },
          transform: { rotate: 15.0 },
          param_schema: [{ name: :radius, default: 64, min: 10, max: 120, step: 1 }],
          dynamic: true
        )
      )
      expect(layer[:mappings]).to include(
        {
          source: { kind: :frequency_band, band: :low },
          target: :"custom_shapes.0.params.radius",
          transform: { min: 24, max: 96 }
        },
        {
          source: { kind: :beat_pulse },
          target: :"custom_shapes.0.transform.scale",
          transform: { min: 0.8, max: 1.2 }
        }
      )
    end

    it "validates custom shape params from declared metadata" do
      shape_class = Class.new do
        include Vizcore::Shape

        param :radius, default: 64, min: 10, max: 120

        def draw(ctx)
          ctx.circle radius: ctx.param(:radius)
        end
      end
      Vizcore.register_shape :engine_spec_validated_shape, shape_class

      expect do
        described_class.define do
          scene :custom_shape_scene do
            layer :generated do
              custom_shape :engine_spec_validated_shape, radius: 140
            end
          end
        end
      end.to raise_error(ArgumentError, /shape param radius must be <= 120.0/)
    end

    it "raises when a custom shape is unknown" do
      expect do
        described_class.define do
          scene :custom_shape_scene do
            layer :generated do
              custom_shape :missing_shape
            end
          end
        end
      end.to raise_error(ArgumentError, /Unknown custom shape: :missing_shape/)
    end

    it "flattens shape groups into child primitive style and transform" do
      definition = described_class.define do
        scene :grouped_shape_scene do
          layer :logo do
            group :badge do
              translate x: 40, y: 20
              rotate 15
              scale 1.5
              opacity 0.5
              stroke width: 2, color: "#38bdf8"

              circle :ring, radius: 80 do
                opacity 0.8
                translate x: 10, y: 0
              end

              group do
                translate x: -20, y: 0
                rect width: 120, height: 48
              end
            end
          end
        end
      end

      shapes = definition[:scenes].first[:layers].first[:params][:shapes]
      expect(shapes).to eq(
        [
          {
            kind: :circle,
            id: :ring,
            radius: 80,
            opacity: 0.4,
            stroke_width: 2.0,
            stroke_color: "#38bdf8",
            transform: {
              translate: { x: 50.0, y: 20.0 },
              rotate: 15.0,
              scale: { x: 1.5, y: 1.5 }
            }
          },
          {
            kind: :rect,
            width: 120,
            height: 48,
            opacity: 0.5,
            stroke_width: 2.0,
            stroke_color: "#38bdf8",
            transform: {
              translate: { x: 20.0, y: 20.0 },
              rotate: 15.0,
              scale: { x: 1.5, y: 1.5 }
            }
          }
        ]
      )
    end

    it "validates invalid shape primitives early" do
      expect do
        described_class.define do
          scene :invalid_shape_scene do
            layer :bad do
              polygon :piece, points: [[0, 0], [1, 1]]
            end
          end
        end
      end.to raise_error(ArgumentError, /Invalid polygon `piece`: points must contain at least 3 points/)

      expect do
        described_class.define do
          scene :invalid_shape_scene do
            layer :bad do
              rect width: -10, height: 20
            end
          end
        end
      end.to raise_error(ArgumentError, /width must be non-negative/)

      expect do
        described_class.define do
          scene :invalid_shape_scene do
            layer :bad do
              path :empty
            end
          end
        end
      end.to raise_error(ArgumentError, /Invalid path `empty`: commands must not be empty/)

      expect do
        described_class.define do
          scene :invalid_shape_scene do
            layer :bad do
              path :busy, detail: 8, max_segments: 4 do
                move_to 0, 0
                cubic_to 20, 80, 80, -80, 100, 0
              end
            end
          end
        end
      end.to raise_error(ArgumentError, /Invalid path `busy`: max_segments exceeded \(8 > 4\)/)

      expect do
        described_class.define do
          scene :invalid_shape_scene do
            layer :bad do
              path :invalid_budget, max_segments: 0 do
                move_to 0, 0
                line_to 10, 0
              end
            end
          end
        end
      end.to raise_error(ArgumentError, /Invalid path `invalid_budget`: max_segments must be a positive integer/)
    end

    it "builds scenes from inherited layers" do
      definition = described_class.define do
        scene :base do
          layer :background do
            shader :neon_grid
          end
        end

        scene :drop, extends: :base do
          layer :particles do
            type :particle_field
          end
        end
      end

      drop_layers = definition[:scenes].last[:layers]
      expect(drop_layers.map { |layer| layer[:name] }).to eq(%i[background particles])
      expect(drop_layers.first).to include(type: :shader, shader: :neon_grid)
      expect(drop_layers.last).to include(type: :particle_field)
    end

    it "builds mapping transforms from block syntax" do
      definition = described_class.define do
        scene :reactive do
          layer :liquid do
            shader :gradient_pulse

            map amplitude, to: :scale do
              gain 2.0
              range 0.8..1.6
              curve :ease_out
              smooth attack: 0.2, release: 0.6
              deadzone 0.05
            end
          end
        end
      end

      layer = definition[:scenes].first[:layers].first

      expect(layer[:mappings]).to include(
        {
          source: { kind: :amplitude },
          target: :scale,
          transform: {
            deadzone: 0.05,
            gain: 2.0,
            min: 0.8,
            max: 1.6,
            curve: :ease_out,
            attack: 0.2,
            release: 0.6
          }
        }
      )
    end

    it "treats shader path strings as custom GLSL shaders" do
      definition = described_class.define do
        scene :custom do
          layer :liquid do
            shader "shaders/liquid.frag", reload: true
          end
        end
      end

      layer = definition[:scenes].first[:layers].first

      expect(layer[:type]).to eq(:shader)
      expect(layer[:glsl]).to eq("shaders/liquid.frag")
      expect(layer[:shader]).to be_nil
      expect(layer[:params]).to include(shader_reload: true)
    end

    it "supports musical frequency band aliases in layer mappings" do
      definition = described_class.define do
        scene :aliases do
          layer :reactive do
            type :particle_field
            map bass => :size
            map treble, to: :sparkle
            map sub => :rumble
          end
        end
      end

      mappings = definition[:scenes].first[:layers].first[:mappings]

      expect(mappings).to include(
        { source: { kind: :frequency_band, band: :low }, target: :size },
        { source: { kind: :frequency_band, band: :high }, target: :sparkle },
        { source: { kind: :frequency_band, band: :sub }, target: :rumble }
      )
    end

    it "builds react_to blocks as normal mappings" do
      definition = described_class.define do
        scene :reactive do
          layer :particles do
            type :particle_field

            react_to amplitude do
              change :speed, gain: 2.5, range: 0.1..4.0
            end

            react_to beat do
              trigger :burst
            end
          end
        end
      end

      mappings = definition[:scenes].first[:layers].first[:mappings]

      expect(mappings).to include(
        {
          source: { kind: :amplitude },
          target: :speed,
          transform: { gain: 2.5, min: 0.1, max: 4.0 }
        },
        { source: { kind: :beat }, target: :burst }
      )
    end

    it "stores explicit layer blend modes" do
      definition = described_class.define do
        scene :blend_modes do
          layer :sparks do
            type :particle_field
            blend :screen
          end
        end
      end

      params = definition[:scenes].first[:layers].first[:params]
      expect(params[:blend]).to eq(:screen)
    end

    it "declares numeric shader parameter metadata" do
      definition = described_class.define do
        scene :custom do
          layer :liquid do
            shader "shaders/liquid.frag"
            param :wobble, default: 0.3, range: 0.0..2.0, step: 0.05
          end
        end
      end

      layer = definition[:scenes].first[:layers].first
      expect(layer[:params]).to include(wobble: 0.3)
      expect(layer[:param_schema]).to eq(
        [
          {
            name: :wobble,
            default: 0.3,
            min: 0.0,
            max: 2.0,
            step: 0.05
          }
        ]
      )
    end

    it "builds beat and bar transition triggers" do
      definition = described_class.define do
        scene(:intro) { layer(:a) { type :geometry } }
        scene(:build) { layer(:b) { type :geometry } }
        scene(:drop) { layer(:c) { type :geometry } }

        transition from: :intro, to: :build do
          on_beat 8
        end

        transition from: :build, to: :drop do
          on_bar 4
        end
      end

      controller = Vizcore::DSL::TransitionController.new(
        scenes: definition[:scenes],
        transitions: definition[:transitions]
      )

      expect(controller.next_transition(scene_name: :intro, audio: { beat_count: 7 })).to be_nil
      expect(controller.next_transition(scene_name: :intro, audio: { beat_count: 8 })).to include(to: :build)
      expect(controller.next_transition(scene_name: :build, audio: { beat_count: 15 })).to be_nil
      expect(controller.next_transition(scene_name: :build, audio: { beat_count: 16 })).to include(to: :drop)
    end

    it "builds section scenes with beat-counted transitions" do
      definition = described_class.define do
        section :intro, bars: 2 do
          layer(:a) { type :geometry }
        end

        section :drop, bars: 1, beats_per_bar: 3 do
          layer(:b) { type :geometry }
        end

        section :outro, bars: 1 do
          layer(:c) { type :geometry }
        end
      end

      expect(definition[:scenes].map { |scene| scene[:name] }).to eq(%i[intro drop outro])

      controller = Vizcore::DSL::TransitionController.new(
        scenes: definition[:scenes],
        transitions: definition[:transitions]
      )

      expect(controller.next_transition(scene_name: :intro, audio: { beat_count: 7 })).to be_nil
      expect(controller.next_transition(scene_name: :intro, audio: { beat_count: 8 })).to include(to: :drop)
      expect(controller.next_transition(scene_name: :drop, audio: { beat_count: 2 })).to be_nil
      expect(controller.next_transition(scene_name: :drop, audio: { beat_count: 3 })).to include(to: :outro)
    end

    it "builds timeline transitions from beat markers" do
      definition = described_class.define do
        scene(:intro) { layer(:a) { type :geometry } }
        scene(:build) { layer(:b) { type :geometry } }
        scene(:drop) { layer(:c) { type :geometry } }

        timeline do
          at beats(0), scene: :intro
          at bars(2), scene: :build
          at bars(3), scene: :drop
        end
      end

      expect(definition[:timelines]).to eq(
        [
          [
            { at: 0.0, unit: :beats, scene: :intro },
            { at: 8.0, unit: :beats, scene: :build },
            { at: 12.0, unit: :beats, scene: :drop }
          ]
        ]
      )

      controller = Vizcore::DSL::TransitionController.new(
        scenes: definition[:scenes],
        transitions: definition[:transitions]
      )

      expect(controller.next_transition(scene_name: :intro, audio: { beat_count: 7 })).to be_nil
      expect(controller.next_transition(scene_name: :intro, audio: { beat_count: 8 })).to include(to: :build)
      expect(controller.next_transition(scene_name: :build, audio: { beat_count: 3 })).to be_nil
      expect(controller.next_transition(scene_name: :build, audio: { beat_count: 4 })).to include(to: :drop)
    end

    it "builds timeline transitions from second markers" do
      definition = described_class.define do
        scene(:intro) { layer(:a) { type :geometry } }
        scene(:drop) { layer(:b) { type :geometry } }

        timeline do
          at 0, scene: :intro
          at seconds(1.5), scene: :drop
        end
      end

      controller = Vizcore::DSL::TransitionController.new(
        scenes: definition[:scenes],
        transitions: definition[:transitions]
      )

      expect(controller.next_transition(scene_name: :intro, audio: {}, frame_count: 89)).to be_nil
      expect(controller.next_transition(scene_name: :intro, audio: {}, frame_count: 90)).to include(to: :drop)
    end

    it "rejects mixed timeline units" do
      expect do
        described_class.define do
          timeline do
            at seconds(0), scene: :intro
            at beats(4), scene: :drop
          end
        end
      end.to raise_error(ArgumentError, /same unit/)
    end

    it "rejects non-increasing timeline positions" do
      expect do
        described_class.define do
          timeline do
            at beats(4), scene: :intro
            at beats(4), scene: :drop
          end
        end
      end.to raise_error(ArgumentError, /positions must increase/)
    end

    it "rejects react_to without a reaction body" do
      expect do
        described_class.define do
          scene :invalid do
            layer :particles do
              react_to amplitude
            end
          end
        end
      end.to raise_error(ArgumentError, /react_to requires a block/)
    end

    it "rejects unknown layer styles" do
      expect do
        described_class.define do
          scene :invalid do
            layer :title do
              use_style :missing
            end
          end
        end
      end.to raise_error(ArgumentError, /unknown style: missing/)
    end

    it "rejects unknown scene themes" do
      expect do
        described_class.define do
          scene :invalid do
            use_theme :missing
          end
        end
      end.to raise_error(ArgumentError, /unknown theme: missing/)
    end

    it "rejects unknown base scenes" do
      expect do
        described_class.define do
          scene :drop, extends: :missing
        end
      end.to raise_error(ArgumentError, /unknown base scene: missing/)
    end
  end

  describe ".load_file" do
    it "evaluates a scene file and returns definition hash" do
      Dir.mktmpdir("vizcore-dsl-scene") do |dir|
        scene_path = File.join(dir, "scene.rb")
        File.write(
          scene_path,
          <<~RUBY
            Vizcore.define do
              scene :loaded do
                layer :particles do
                  type :particle_field
                  count 1200
                  map amplitude => :speed
                end
              end
            end
          RUBY
        )

        definition = described_class.load_file(scene_path)
        expect(definition[:scenes].length).to eq(1)
        expect(definition[:scenes][0][:name]).to eq(:loaded)
        expect(definition[:scenes][0][:layers][0][:type]).to eq(:particle_field)
        expect(definition[:scenes][0][:layers][0][:params]).to eq(count: 1200)
      end
    end

    it "raises for missing file path" do
      expect do
        described_class.load_file("/tmp/does-not-exist-#{Process.pid}.rb")
      end.to raise_error(ArgumentError, /Scene file not found/)
    end
  end

  describe ".watch_file" do
    it "loads updated definition and yields it to callback" do
      fake_listener = nil

      Dir.mktmpdir("vizcore-dsl-watch") do |dir|
        scene_path = File.join(dir, "scene.rb")
        File.write(scene_path, <<~RUBY)
          Vizcore.define do
            scene :initial do
              layer :l do
                type :geometry
              end
            end
          end
        RUBY

        yielded = nil
        watcher = described_class.watch_file(
          scene_path,
          listener_factory: lambda do |_directory, _pattern, &block|
            fake_listener = Struct.new(:callback) do
              def start; end
              def stop; end
            end.new(block)
          end
        ) do |definition, changed_path|
          yielded = [definition, changed_path]
        end

        watcher.start
        File.write(scene_path, <<~RUBY)
          Vizcore.define do
            scene :updated do
              layer :l do
                type :shader
              end
            end
          end
        RUBY
        fake_listener.callback.call([scene_path], [], [])
        watcher.stop

        definition, changed_path = yielded
        expect(changed_path.to_s).to eq(scene_path)
        expect(definition[:scenes][0][:name]).to eq(:updated)
      end
    end
  end
end
