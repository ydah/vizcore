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

  it "reads and normalizes scene-specific overrides from JSON" do
    Dir.mktmpdir("vizcore-control-preset-scene-overrides") do |dir|
      path = File.join(dir, "controls.json")
      File.write(
        path,
        JSON.generate(
          visual_settings: { visualGain: 3.1 },
          scene_overrides: {
            build: {
              visual_settings: { bassBoost: 2.0 },
              midi_learn_bindings: { "cc:1:5" => { type: "live_control", control: "freeze" } }
            },
            drop: {
              midi: { "note:1:36" => { type: "switch_scene", scene: "build" } }
            }
          }
        )
      )

      expect(described_class.load(path)).to eq(
        "visual_settings" => { "visualGain" => 3.1 },
        "scene_overrides" => {
          "build" => {
            "visual_settings" => { "bassBoost" => 2.0 },
            "midi_learn_bindings" => { "cc:1:5" => { "type" => "live_control", "control" => "freeze" } }
          },
          "drop" => {
            "midi_learn_bindings" => { "note:1:36" => { "type" => "switch_scene", "scene" => "build" } }
          }
        }
      )
    end
  end

  it "writes scene-specific overrides in normalized form" do
    Dir.mktmpdir("vizcore-control-preset-write-scene-overrides") do |dir|
      path = File.join(dir, "controls", "live.json")

      result = described_class.write(
        path,
        {
          sceneOverrides: {
            build: {
              visualSettings: { visualGain: 4.0 },
              midiLearnBindings: { "note:1:36" => { type: "switch_scene", scene: "drop" } }
            },
            drop: {
              midiLearnBindings: nil
            },
            "   " => {
              visual_settings: { visualGain: 1 },
            },
          }
        }
      )

      expect(result).to include("scene_overrides")
      expect(result.fetch("scene_overrides").keys).to include("build")
      scene_override = result["scene_overrides"]["build"]
      visual_settings = scene_override["visual_settings"] || scene_override[:visual_settings]
      midi_overrides = scene_override["midi_learn_bindings"] || scene_override[:midi_learn_bindings]
      expect(visual_settings[:visualGain] || visual_settings["visualGain"]).to eq(4.0)
      expect(midi_overrides).to have_key("note:1:36")

      action = scene_override.fetch("midi_learn_bindings", {}).fetch("note:1:36", {})
      expect(action[:type] || action["type"]).to eq("switch_scene")
      expect(action[:scene] || action["scene"]).to eq("drop")
      expect(JSON.parse(File.read(path))).to include("scene_overrides")
      expect(JSON.parse(File.read(path))["scene_overrides"]).to include("build")
      expect(JSON.parse(File.read(path))["scene_overrides"]).not_to have_key("   ")
    end
  end
end
