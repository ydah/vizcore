# frozen_string_literal: true

require "tmpdir"
require "vizcore/dsl/engine"

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
        { source: { kind: :beat }, target: :flash }
      )
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
