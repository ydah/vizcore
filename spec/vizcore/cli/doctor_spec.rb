# frozen_string_literal: true

require "vizcore/cli/doctor"

RSpec.describe Vizcore::CLISupport::Doctor do
  it "passes when required runtime pieces are available" do
    report = described_class.new(
      ruby_version: "3.2.0",
      portaudio_available: -> { true },
      audio_devices: -> { [{ index: 0, name: "Mic" }] },
      midi_devices: -> { [{ id: "0", name: "Controller" }] },
      fftw_available: -> { true },
      command_available: ->(command) { command == "ffmpeg" },
      port_available: ->(_host, _port) { true }
    ).call

    expect(report).not_to be_failure
    expect(report.checks.map(&:status)).to all(eq(:ok))
  end

  it "warns for optional audio features without failing the report" do
    report = described_class.new(
      ruby_version: "3.2.0",
      portaudio_available: -> { false },
      audio_devices: -> { [] },
      midi_devices: -> { [] },
      fftw_available: -> { false },
      command_available: ->(_command) { false },
      port_available: ->(_host, _port) { false }
    ).call

    expect(report).not_to be_failure
    expect(report.checks.map(&:status)).to include(:warn)
  end

  it "fails when Ruby is too old" do
    report = described_class.new(
      ruby_version: "3.1.9",
      portaudio_available: -> { true },
      audio_devices: -> { [] },
      midi_devices: -> { [] },
      fftw_available: -> { true },
      command_available: ->(_command) { true },
      port_available: ->(_host, _port) { true }
    ).call

    expect(report).to be_failure
    expect(report.checks.find { |check| check.name == "Ruby" }.status).to eq(:fail)
  end
end
