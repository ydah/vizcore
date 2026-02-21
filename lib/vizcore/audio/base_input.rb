# frozen_string_literal: true

module Vizcore
  module Audio
    # Base class for audio inputs used by {Vizcore::Audio::InputManager}.
    class BaseInput
      attr_reader :sample_rate

      # @param sample_rate [Integer]
      def initialize(sample_rate: 44_100)
        @sample_rate = Integer(sample_rate)
        @running = false
      end

      # @return [Vizcore::Audio::BaseInput]
      def start
        @running = true
        self
      end

      # @return [Vizcore::Audio::BaseInput]
      def stop
        @running = false
        self
      end

      # @return [Boolean]
      def running?
        @running
      end

      # @param frame_size [Integer]
      # @return [Array<Float>] silence by default
      def read(frame_size)
        Array.new(Integer(frame_size), 0.0)
      end
    end
  end
end
