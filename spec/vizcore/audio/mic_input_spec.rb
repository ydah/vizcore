# frozen_string_literal: true

require "vizcore/audio/mic_input"

RSpec.describe Vizcore::Audio::MicInput do
  class FakeFallbackInput
    attr_reader :started, :stopped

    def initialize(samples)
      @samples = samples
      @started = false
      @stopped = false
    end

    def start
      @started = true
      self
    end

    def stop
      @stopped = true
      self
    end

    def read(frame_size)
      @samples.first(frame_size)
    end
  end

  class FakeBackend
    attr_reader :closed_streams

    def initialize(stream)
      @stream = stream
      @closed_streams = []
    end

    def open_default_input_stream(**_kwargs)
      @stream
    end

    def close_stream(stream)
      @closed_streams << stream
      stream.close if stream.respond_to?(:close)
    end
  end

  class FakeStream
    attr_reader :started, :closed

    def initialize(samples:, start_success: true, read_error: nil)
      @samples = samples
      @start_success = start_success
      @read_error = read_error
      @started = false
      @closed = false
    end

    def start
      @started = @start_success
    end

    def read(frame_size)
      raise @read_error if @read_error

      @samples.first(frame_size)
    end

    def close
      @closed = true
    end
  end

  it "reads from portaudio stream when available" do
    stream = FakeStream.new(samples: [0.1, 0.2, 0.3, 0.4])
    backend = FakeBackend.new(stream)
    fallback = FakeFallbackInput.new([0.9, 0.9, 0.9, 0.9])

    mic = described_class.new(
      sample_rate: 44_100,
      portaudio_backend: backend,
      fallback_input: fallback
    )
    mic.start

    expect(mic.using_fallback?).to eq(false)
    expect(mic.read(4)).to eq([0.1, 0.2, 0.3, 0.4])
    expect(fallback.started).to eq(false)
  ensure
    mic&.stop
  end

  it "falls back when no stream is opened" do
    backend = FakeBackend.new(nil)
    fallback = FakeFallbackInput.new([0.7, 0.6, 0.5, 0.4])
    mic = described_class.new(portaudio_backend: backend, fallback_input: fallback)

    mic.start

    expect(mic.using_fallback?).to eq(true)
    expect(fallback.started).to eq(true)
    expect(mic.read(4)).to eq([0.7, 0.6, 0.5, 0.4])
  ensure
    mic&.stop
  end

  it "switches to fallback when stream read raises" do
    stream = FakeStream.new(samples: [0.2, 0.2], read_error: RuntimeError.new("read failed"))
    backend = FakeBackend.new(stream)
    fallback = FakeFallbackInput.new([0.3, 0.3])
    mic = described_class.new(portaudio_backend: backend, fallback_input: fallback)

    mic.start

    expect(mic.read(2)).to eq([0.3, 0.3])
    expect(mic.using_fallback?).to eq(true)
    expect(backend.closed_streams).to include(stream)
  ensure
    mic&.stop
  end
end
