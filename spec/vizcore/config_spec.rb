# frozen_string_literal: true

require "vizcore/config"

RSpec.describe Vizcore::Config do
  let(:scene_file) { Vizcore.root.join("examples", "basic.rb").to_s }

  it "parses audio source and optional audio file" do
    config = described_class.new(
      scene_file: scene_file,
      audio_source: "file",
      audio_file: "spec/fixtures/audio/pulse16_mono.wav"
    )

    expect(config.audio_source).to eq(:file)
    expect(config.audio_file).to be_a(Pathname)
    expect(config.audio_file.to_s).to end_with("spec/fixtures/audio/pulse16_mono.wav")
  end

  it "parses optional audio device" do
    config = described_class.new(scene_file: scene_file, audio_device: "5")

    expect(config.audio_device).to eq("5")
  end

  it "parses optional feature replay file" do
    config = described_class.new(scene_file: scene_file, feature_file: "features.json")

    expect(config.feature_file).to be_a(Pathname)
    expect(config.feature_file.to_s).to end_with("features.json")
  end

  it "parses optional control preset file" do
    config = described_class.new(scene_file: scene_file, control_preset: "controls.json")

    expect(config.control_preset).to be_a(Pathname)
    expect(config.control_preset.to_s).to end_with("controls.json")
  end

  it "parses optional plugin asset files" do
    config = described_class.new(scene_file: scene_file, plugin_assets: ["frontend/plugin.js"])

    expect(config.plugin_assets.map(&:to_s).first).to end_with("frontend/plugin.js")
  end

  it "parses optional noise gate" do
    config = described_class.new(scene_file: scene_file, noise_gate: "0.03")

    expect(config.noise_gate).to eq(0.03)
  end

  it "parses optional BPM lock settings" do
    config = described_class.new(scene_file: scene_file, bpm: "128", bpm_lock: true)

    expect(config.bpm).to eq(128.0)
    expect(config.bpm_lock?).to eq(true)
  end

  it "parses optional OSC sync port" do
    config = described_class.new(scene_file: scene_file, osc_port: "9000")

    expect(config.osc_port).to eq(9000)
  end

  it "parses projector mode" do
    config = described_class.new(scene_file: scene_file, projector_mode: true)

    expect(config.projector_mode).to eq(true)
    expect(config.projector?).to eq(true)
  end

  it "parses voice kana analysis opt-in" do
    config = described_class.new(scene_file: scene_file, voice_kana: true)

    expect(config.voice_kana?).to eq(true)
  end

  it "parses public control opt-in" do
    config = described_class.new(scene_file: scene_file, allow_public_control: true)

    expect(config.allow_public_control?).to eq(true)
  end

  it "parses optional scene switch effect and duration" do
    config = described_class.new(
      scene_file: scene_file,
      scene_switch_effect: "crossfade",
      scene_switch_effect_duration: "0.45"
    )

    expect(config.scene_switch_effect).to eq({ name: :crossfade, options: { duration: 0.45 } })
  end

  it "accepts scene switch effect without duration" do
    config = described_class.new(scene_file: scene_file, scene_switch_effect: "crossfade")

    expect(config.scene_switch_effect).to eq({ name: :crossfade })
  end

  it "raises for non-numeric scene switch duration" do
    expect do
      described_class.new(scene_file: scene_file, scene_switch_effect: "crossfade", scene_switch_effect_duration: "bad")
    end.to raise_error(ArgumentError, /scene_switch_duration/)
  end

  it "enables scene hot reload by default and can disable it" do
    default_config = described_class.new(scene_file: scene_file)
    disabled_config = described_class.new(scene_file: scene_file, reload: false)

    expect(default_config.reload?).to eq(true)
    expect(disabled_config.reload?).to eq(false)
  end

  it "raises for unsupported audio source" do
    expect do
      described_class.new(scene_file: scene_file, audio_source: "invalid")
    end.to raise_error(ArgumentError, /Unsupported audio source/)
  end
end
