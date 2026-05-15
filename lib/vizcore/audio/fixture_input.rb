# frozen_string_literal: true

require_relative "base_input"

module Vizcore
  module Audio
    # Deterministic sample-frame input for tests and repeatable development checks.
    class FixtureInput < BaseInput
      # @param frames [Array<Array<Numeric>>] sample frames returned in order
      # @param sample_rate [Integer]
      # @param loop [Boolean] whether to repeat frames after the last one
      def initialize(frames:, sample_rate: 44_100, loop: true)
        super(sample_rate: sample_rate)
        @frames = normalize_frames(frames)
        @loop = !!loop
        @index = 0
      end

      # @param frame_size [Integer]
      # @return [Array<Float>]
      def read(frame_size)
        count = Integer(frame_size)
        return Array.new(count, 0.0) unless running?

        frame = next_frame
        return Array.new(count, 0.0) unless frame

        normalize_frame_size(frame, count)
      end

      # @return [void]
      def reset
        @index = 0
      end

      private

      def next_frame
        return nil if @frames.empty?
        return nil if @index >= @frames.length && !@loop

        frame = @frames[@index % @frames.length]
        @index += 1
        frame
      end

      def normalize_frames(frames)
        Array(frames).map do |frame|
          values = Array(frame).map { |sample| Float(sample) }
          raise ArgumentError, "fixture frames must not be empty" if values.empty?

          values
        end
      rescue ArgumentError, TypeError
        raise ArgumentError, "fixture frames must contain numeric samples"
      end

      def normalize_frame_size(frame, count)
        return frame.first(count) if frame.length >= count

        frame + Array.new(count - frame.length, 0.0)
      end
    end
  end
end
