# frozen_string_literal: true

require "json"
require "tmpdir"
require "vizcore/control_preset"

RSpec.describe Vizcore::ControlPreset do
  it "loads visual settings and MIDI learn bindings from JSON" do
    Dir.mktmpdir("vizcore-control-preset") do |dir|
      path = File.join(dir, "controls.json")
      File.write(
        path,
        JSON.generate(
          visual_settings: { visualGain: 3.5 },
          midi_learn_bindings: { "cc:1:7" => { type: "live_control", control: "freeze" } }
        )
      )

      expect(described_class.load(path)).to eq(
        "visual_settings" => { "visualGain" => 3.5 },
        "midi_learn_bindings" => { "cc:1:7" => { "type" => "live_control", "control" => "freeze" } }
      )
    end
  end

  it "raises for invalid JSON" do
    Dir.mktmpdir("vizcore-control-preset-invalid") do |dir|
      path = File.join(dir, "controls.json")
      File.write(path, "{")

      expect { described_class.load(path) }.to raise_error(ArgumentError, /Invalid control preset JSON/)
    end
  end

  it "writes normalized control presets to JSON" do
    Dir.mktmpdir("vizcore-control-preset-write") do |dir|
      path = File.join(dir, "controls", "live.json")

      result = described_class.write(
        path,
        {
          visualSettings: { visualGain: 4.0 },
          midiLearnBindings: { "note:1:36" => { type: "switch_scene", scene: "drop" } }
        }
      )

      expect(result).to include(
        "visual_settings" => { visualGain: 4.0 },
        "midi_learn_bindings" => { "note:1:36" => { type: "switch_scene", scene: "drop" } }
      )
      expect(JSON.parse(File.read(path))).to include("visual_settings", "midi_learn_bindings")
    end
  end
end
