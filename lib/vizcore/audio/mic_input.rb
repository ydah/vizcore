# frozen_string_literal: true

require_relative "base_input"
require_relative "dummy_sine_input"
require_relative "../errors"
require_relative "portaudio_ffi"

module Vizcore
  module Audio
    # Microphone input using PortAudio, with automatic fallback to dummy source.
    class MicInput < BaseInput
      attr_reader :device, :last_error

      # @param device [Symbol, String]
      # @param sample_rate [Integer]
      # @param fallback_input [Vizcore::Audio::BaseInput, nil]
      # @param portaudio_backend [Module]
      # @param channels [Integer]
      # @param frames_per_buffer [Integer]
      def initialize(device: :default, sample_rate: 44_100, fallback_input: nil, portaudio_backend: PortAudioFFI, channels: 1, frames_per_buffer: 1024)
        super(sample_rate: sample_rate)
        @device = device
        @channels = Integer(channels)
        @frames_per_buffer = Integer(frames_per_buffer)
        @fallback_input = fallback_input || DummySineInput.new(sample_rate: sample_rate)
        @portaudio_backend = portaudio_backend
        @stream = nil
        @using_fallback = false
        @last_error = nil
      end

      # @return [Vizcore::Audio::MicInput]
      def start
        super
        @using_fallback = false

        @stream = open_stream
        @using_fallback = !@stream
        @fallback_input.start if @using_fallback
        self
      end

      # @return [Vizcore::Audio::MicInput]
      def stop
        close_stream
        @fallback_input.stop if @using_fallback
        @using_fallback = false
        super
      end

      # @param frame_size [Integer]
      # @return [Array<Float>] microphone frame or fallback samples
      def read(frame_size)
        count = Integer(frame_size)
        return Array.new(count, 0.0) unless running?

        if @stream
          samples = @stream.read(count)
          @last_error = nil
          normalize_samples(samples, count)
        else
          @fallback_input.read(count)
        end
      rescue StandardError => e
        @last_error = AudioSourceError.new("Microphone read failed: #{e.message}")
        switch_to_fallback
        @fallback_input.read(count)
      end

      # @return [Boolean]
      def using_fallback?
        @using_fallback
      end

      private

      def open_stream
        stream = @portaudio_backend.open_default_input_stream(
          sample_rate: sample_rate,
          channels: @channels,
          frames_per_buffer: @frames_per_buffer
        )
        return nil unless stream
        return stream if stream.start

        @portaudio_backend.close_stream(stream)
        nil
      rescue StandardError => e
        @last_error = AudioSourceError.new("Microphone stream open failed: #{e.message}")
        nil
      end

      def close_stream
        return unless @stream

        @portaudio_backend.close_stream(@stream)
      ensure
        @stream = nil
      end

      def switch_to_fallback
        return if @using_fallback

        close_stream
        @using_fallback = true
        @fallback_input.start
      end

      def normalize_samples(samples, expected_count)
        normalized = Array(samples).map { |sample| Float(sample) }
        if normalized.length < expected_count
          normalized + Array.new(expected_count - normalized.length, 0.0)
        else
          normalized.first(expected_count)
        end
      rescue ArgumentError, TypeError
        Array.new(expected_count, 0.0)
      end
    end
  end
end
