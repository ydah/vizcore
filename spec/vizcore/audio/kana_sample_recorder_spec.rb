# frozen_string_literal: true

require "json"
require "fileutils"
require "tmpdir"
require "vizcore/audio/kana_sample_recorder"
require "vizcore/audio/file_input"

RSpec.describe Vizcore::Audio::KanaSampleRecorder do
  let(:clock) { -> { Time.utc(2026, 1, 2, 3, 4, 5) } }
  let(:sleeper) { ->(_seconds) {} }

  it "records labeled WAV samples and writes a manifest" do
    Dir.mktmpdir("vizcore-kana-samples") do |dir|
      result = described_class.new(
        labels: %w[あ ん],
        takes: 1,
        duration: 0.01,
        output_dir: dir,
        source: :dummy,
        lead_in: 0,
        sleeper: sleeper,
        clock: clock
      ).call

      expect(result.samples.length).to eq(2)
      expect(result.total_samples).to eq(2)
      expect(result.manifest_path).to eq(Pathname.new(dir).join("manifest.json"))

      payload = JSON.parse(result.manifest_path.read)
      expect(payload.fetch("version")).to eq(described_class::VERSION)
      expect(payload.dig("metadata", "labels")).to eq(%w[あ ん])
      expect(payload.dig("metadata", "source")).to eq("dummy")
      expect(payload.fetch("samples").map { |sample| sample.fetch("label") }).to eq(%w[あ ん])

      first_sample = payload.fetch("samples").first
      sample_path = Pathname.new(dir).join(first_sample.fetch("path"))
      expect(sample_path).to exist
      expect(first_sample).to include(
        "id" => "sample_0001",
        "take" => 1,
        "sample_rate" => 44_100,
        "sample_count" => 441
      )
      expect(first_sample.fetch("rms")).to be > 0

      input = Vizcore::Audio::FileInput.new(path: sample_path.to_s)
      input.start
      expect(input.read(4).length).to eq(4)
    ensure
      input&.stop
    end
  end

  it "appends new samples to an existing manifest" do
    Dir.mktmpdir("vizcore-kana-samples-append") do |dir|
      2.times do
        described_class.new(
          labels: ["あ"],
          takes: 1,
          duration: 0.001,
          output_dir: dir,
          source: :dummy,
          lead_in: 0,
          sleeper: sleeper,
          clock: clock
        ).call
      end

      payload = JSON.parse(Pathname.new(dir).join("manifest.json").read)
      expect(payload.fetch("samples").map { |sample| sample.fetch("id") }).to eq(%w[sample_0001 sample_0002])
      expect(Pathname.new(dir).join("audio/sample_0001.wav")).to exist
      expect(Pathname.new(dir).join("audio/sample_0002.wav")).to exist
    end
  end

  it "rejects manifests with duplicate sample ids or paths before recording" do
    Dir.mktmpdir("vizcore-kana-samples-duplicate") do |dir|
      manifest_path = Pathname.new(dir).join("manifest.json")
      manifest_path.write(
        "#{JSON.pretty_generate(
          "version" => described_class::VERSION,
          "metadata" => {},
          "samples" => [
            { "id" => "sample_0001", "path" => "audio/sample_0001.wav" },
            { "id" => "sample_0001", "path" => "audio/sample_0001.wav" }
          ]
        )}\n"
      )

      expect do
        described_class.new(
          labels: ["あ"],
          takes: 1,
          duration: 0.001,
          output_dir: dir,
          source: :dummy,
          lead_in: 0,
          sleeper: sleeper,
          clock: clock
        ).call
      end.to raise_error(
        ArgumentError,
        /duplicate sample ids: sample_0001.*duplicate sample paths: audio\/sample_0001\.wav/m
      )
    end
  end

  it "does not overwrite existing audio files when choosing the next sample id" do
    Dir.mktmpdir("vizcore-kana-samples-existing-audio") do |dir|
      existing_path = Pathname.new(dir).join("audio/sample_0001.wav")
      FileUtils.mkdir_p(existing_path.dirname)
      existing_path.write("existing")

      result = described_class.new(
        labels: ["あ"],
        takes: 1,
        duration: 0.001,
        output_dir: dir,
        source: :dummy,
        lead_in: 0,
        sleeper: sleeper,
        clock: clock
      ).call

      expect(result.samples.first.fetch("id")).to eq("sample_0002")
      expect(existing_path.read).to eq("existing")
      expect(Pathname.new(dir).join("audio/sample_0002.wav")).to exist
    end
  end

  it "marks samples below the configured RMS floor as near silence" do
    Dir.mktmpdir("vizcore-kana-samples-silence") do |dir|
      result = described_class.new(
        labels: ["あ"],
        takes: 1,
        duration: 0.001,
        output_dir: dir,
        source: :dummy,
        lead_in: 0,
        min_rms: 1.0,
        allow_silent: true,
        sleeper: sleeper,
        clock: clock
      ).call

      sample = result.samples.first
      expect(sample.fetch("warnings")).to include("near_silence")

      payload = JSON.parse(Pathname.new(dir).join("manifest.json").read)
      expect(payload.dig("metadata", "min_rms")).to eq(1.0)
      expect(payload.dig("metadata", "allow_silent")).to eq(true)
      expect(payload.dig("samples", 0, "warnings")).to include("near_silence")
    end
  end

  it "aborts when a collected sample is near silence by default" do
    Dir.mktmpdir("vizcore-kana-samples-abort") do |dir|
      expect do
        described_class.new(
          labels: ["あ"],
          takes: 1,
          duration: 0.001,
          output_dir: dir,
          source: :dummy,
          lead_in: 0,
          min_rms: 1.0,
          sleeper: sleeper,
          clock: clock
        ).call
      end.to raise_error(ArgumentError, /near silence/)

      expect(Pathname.new(dir).join("manifest.json")).not_to exist
      expect(Dir[File.join(dir, "audio", "*.wav")]).to be_empty
    end
  end

  it "rejects empty label lists" do
    expect do
      described_class.new(labels: ",", takes: 1, duration: 0.1)
    end.to raise_error(ArgumentError, /labels/)
  end
end
