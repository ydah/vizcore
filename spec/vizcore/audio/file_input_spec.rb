# frozen_string_literal: true

require "vizcore/audio/file_input"
require "tmpdir"

RSpec.describe Vizcore::Audio::FileInput do
  let(:fixture_path) { Vizcore.root.join("spec", "fixtures", "audio", "pulse16_mono.wav").to_s }
  let(:expected_sequence) { [0.0, 12_000.0, -12_000.0, 24_000.0, -24_000.0, 0.0, 8_000.0, -8_000.0] }

  it "reads samples from a WAV fixture file" do
    input = described_class.new(path: fixture_path)
    input.start

    expect(input.read(8)).to eq(expected_sequence)
  ensure
    input&.stop
  end

  it "loops over WAV samples when requested frames exceed fixture length" do
    input = described_class.new(path: fixture_path)
    input.start

    expect(input.read(10)).to eq(expected_sequence + [0.0, 12_000.0])
  ensure
    input&.stop
  end

  it "returns silence when not started" do
    input = described_class.new(path: fixture_path)
    expect(input.read(4)).to eq([0.0, 0.0, 0.0, 0.0])
  end

  it "decodes mp3 files via ffmpeg when available" do
    status = instance_double(Process::Status, success?: true)
    runner = double("runner")
    allow(runner).to receive(:capture3).and_return([[0.25, -0.25].pack("e*"), "", status])

    Dir.mktmpdir("vizcore-file-input") do |dir|
      mp3_path = File.join(dir, "pulse.mp3")
      File.binwrite(mp3_path, "fake-mp3")
      input = described_class.new(path: mp3_path, command_runner: runner, ffmpeg_checker: -> { true })
      input.start

      expect(input.read(4)).to eq([0.25, -0.25, 0.25, -0.25])
      expect(runner).to have_received(:capture3).with(
        "ffmpeg",
        "-hide_banner",
        "-loglevel",
        "error",
        "-i",
        mp3_path,
        "-f",
        "f32le",
        "-ac",
        "1",
        "-ar",
        "44100",
        "pipe:1"
      )
    end
  end

  it "returns silence for mp3 when ffmpeg is unavailable" do
    runner = double("runner")
    allow(runner).to receive(:capture3)

    Dir.mktmpdir("vizcore-file-input") do |dir|
      mp3_path = File.join(dir, "pulse.mp3")
      File.binwrite(mp3_path, "fake-mp3")
      input = described_class.new(path: mp3_path, command_runner: runner, ffmpeg_checker: -> { false })
      input.start

      expect(input.read(4)).to eq([0.0, 0.0, 0.0, 0.0])
      expect(runner).not_to have_received(:capture3)
    end
  end
end
