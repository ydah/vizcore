# frozen_string_literal: true

require_relative "dummy_sine_input"
require_relative "file_input"
require_relative "mic_input"
require_relative "midi_input"
require_relative "portaudio_ffi"
require_relative "ring_buffer"

module Vizcore
  module Audio
    # High-level coordinator for audio frame capture and ring-buffer storage.
    class InputManager
      DEFAULT_SAMPLE_RATE = 44_100
      DEFAULT_FRAME_SIZE = 1024
      DEFAULT_RING_BUFFER_SIZE = 4096

      attr_reader :frame_size, :sample_rate, :ring_buffer

      # @param source [Symbol, String] input source (`:mic`, `:file`, `:dummy`)
      # @param sample_rate [Integer] sample rate in Hz
      # @param frame_size [Integer] frame size used by capture loop
      # @param ring_buffer_size [Integer] stored sample capacity
      # @param file_path [String, nil] source file path for `:file`
      def initialize(source: :mic, sample_rate: DEFAULT_SAMPLE_RATE, frame_size: DEFAULT_FRAME_SIZE, ring_buffer_size: DEFAULT_RING_BUFFER_SIZE, file_path: nil)
        @source_name = source.to_sym
        @sample_rate = Integer(sample_rate)
        @frame_size = Integer(frame_size)
        @ring_buffer = RingBuffer.new(ring_buffer_size)
        @input = build_input(file_path)
      end

      # @return [Vizcore::Audio::InputManager]
      def start
        @input.start
        self
      end

      # @return [Vizcore::Audio::InputManager]
      def stop
        @input.stop
        self
      end

      # @return [Boolean]
      def running?
        @input.running?
      end

      # Capture one frame from the underlying input and append to ring buffer.
      #
      # @return [Array<Float>]
      def capture_frame
        samples = @input.read(frame_size)
        ring_buffer.write(samples)
        samples
      end

      # @param count [Integer]
      # @return [Array<Float>] recent samples from the ring buffer
      def latest_samples(count = frame_size)
        ring_buffer.latest(count)
      end

      # @return [Array<Hash>] detected audio devices or fallback dummy descriptor
      def self.available_audio_devices
        devices = PortAudioFFI.input_devices
        return devices unless devices.empty?

        [
          { index: 0, name: "default (dummy fallback)", max_input_channels: 1, default_sample_rate: DEFAULT_SAMPLE_RATE.to_f }
        ]
      end

      # @return [Array<Hash>] detected MIDI devices or virtual fallback descriptor
      def self.available_midi_devices
        devices = MidiInput.available_devices
        return devices unless devices.empty?

        [{ id: "virtual-0", name: "virtual-midi (optional dependency: unimidi)" }]
      end

      private

      def build_input(file_path)
        case @source_name
        when :mic
          MicInput.new(sample_rate: sample_rate)
        when :file
          FileInput.new(path: file_path, sample_rate: sample_rate)
        when :dummy
          DummySineInput.new(sample_rate: sample_rate)
        else
          raise ArgumentError, "unsupported audio source: #{@source_name}"
        end
      end
    end
  end
end
