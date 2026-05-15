# frozen_string_literal: true

require "tmpdir"
require "vizcore/dsl/engine"
require "vizcore/dsl/transition_controller"

RSpec.describe Vizcore::DSL::Engine do
  describe ".define" do
    it "builds scenes and layers from the DSL block" do
      definition = described_class.define do
        audio :mic, device: :default, sample_rate: 44_100
        midi :controller, device: "Launchpad"
        set :global_intensity, 0.75

        scene :intro do
          layer :background do
            shader :gradient_pulse
            map frequency_band(:low) => :intensity
            map beat? => :flash
            map beat_confidence => :sync_strength
            map beat_pulse => :wobble
          end
        end
      end

      expect(definition[:audio]).to eq([{ name: :mic, options: { device: :default, sample_rate: 44_100 } }])
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
        { source: { kind: :beat_pulse }, target: :wobble }
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
        }
      )
    end

    it "applies named styles to layer params" do
      definition = described_class.define do
        style :neon do
          color "#00ffff"
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
              glow_strength: 0.45,
              blend: :add
            }
          }
        ]
      )

      params = definition[:scenes].first[:layers].first[:params]
      expect(params).to include(
        color: "#ffffff",
        glow_strength: 0.45,
        blend: :add
      )
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
