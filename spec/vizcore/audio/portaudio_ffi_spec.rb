# frozen_string_literal: true

require "ffi"
require "vizcore/audio/portaudio_ffi"

RSpec.describe Vizcore::Audio::PortAudioFFI::Stream do
  class FakePortAudioStreamModule
    def initialize(read_result:, samples:)
      @read_result = read_result
      @samples = samples
    end

    define_method(:Pa_StartStream) do |_pointer|
      0
    end

    define_method(:Pa_ReadStream) do |_pointer, buffer, frames|
      frame_count = Integer(frames)
      buffer.write_array_of_float(@samples.first(frame_count))
      @read_result
    end

    define_method(:Pa_StopStream) do |_pointer|
      0
    end

    define_method(:Pa_CloseStream) do |_pointer|
      0
    end
  end

  def build_stream(read_result:, samples:)
    described_class.new(
      mod: FakePortAudioStreamModule.new(read_result: read_result, samples: samples),
      pointer: FFI::MemoryPointer.new(:char, 1),
      channels: 1
    )
  end

  it "returns samples when PortAudio reports input overflow" do
    stream = build_stream(
      read_result: described_class.pa_input_overflowed,
      samples: [0.1, -0.2, 0.3, -0.4]
    )

    stream.start

    expect(stream.read(4)).to match([
      be_within(0.000001).of(0.1),
      be_within(0.000001).of(-0.2),
      be_within(0.000001).of(0.3),
      be_within(0.000001).of(-0.4)
    ])
  ensure
    stream&.close
  end

  it "returns silence for unrecoverable read errors" do
    stream = build_stream(
      read_result: -9999,
      samples: [0.1, -0.2, 0.3, -0.4]
    )

    stream.start

    expect(stream.read(4)).to eq([0.0, 0.0, 0.0, 0.0])
  ensure
    stream&.close
  end
end
