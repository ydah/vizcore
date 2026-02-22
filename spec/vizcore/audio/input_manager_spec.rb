# frozen_string_literal: true

require "vizcore/audio/input_manager"

RSpec.describe Vizcore::Audio::InputManager do
  let(:fixture_path) { Vizcore.root.join("spec", "fixtures", "audio", "pulse16_mono.wav").to_s }

  describe "#capture_frame" do
    it "captures frame-size samples and stores them in the ring buffer" do
      manager = described_class.new(source: :dummy, frame_size: 16, ring_buffer_size: 32)
      manager.start

      samples = manager.capture_frame

      expect(samples.length).to eq(16)
      expect(manager.latest_samples.length).to eq(16)
      expect(manager.latest_samples.all? { |sample| sample.is_a?(Float) }).to eq(true)
    ensure
      manager.stop
    end

    it "returns silence for file source when no file is available" do
      manager = described_class.new(source: :file, file_path: "missing.wav", frame_size: 8)
      manager.start

      expect(manager.capture_frame).to eq(Array.new(8, 0.0))
    ensure
      manager.stop
    end

    it "reads samples from a WAV file source" do
      manager = described_class.new(source: :file, file_path: fixture_path, frame_size: 4)
      manager.start

      expect(manager.capture_frame).to eq([0.0, 12_000.0, -12_000.0, 24_000.0])
    ensure
      manager&.stop
    end
  end

  describe "#realtime_capture_size" do
    it "returns a real-time ingestion count based on current sample rate and frame rate" do
      manager = described_class.new(source: :dummy, sample_rate: 44_100, frame_size: 1024)

      expect(manager.realtime_capture_size(60.0)).to eq(735)
      expect(manager.realtime_capture_size(30.0)).to eq(1470)
    end

    it "uses WAV native sample rate for file source pacing" do
      manager = described_class.new(source: :file, file_path: fixture_path, frame_size: 1024, sample_rate: 44_100)

      expect(manager.sample_rate).to eq(8000)
      expect(manager.realtime_capture_size(60.0)).to eq(133)
    ensure
      manager&.stop
    end
  end

  describe ".available_audio_devices" do
    it "returns at least one device entry" do
      devices = described_class.available_audio_devices

      expect(devices).not_to be_empty
      expect(devices.first).to include(:name)
    end
  end

  it "raises for unsupported source" do
    expect { described_class.new(source: :unknown) }.to raise_error(ArgumentError)
  end
end
