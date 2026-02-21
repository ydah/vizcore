# frozen_string_literal: true

require_relative "base_input"
require_relative "dummy_sine_input"

module Vizcore
  module Audio
    class MicInput < BaseInput
      attr_reader :device

      def initialize(device: :default, sample_rate: 44_100, fallback_input: nil)
        super(sample_rate: sample_rate)
        @device = device
        @fallback_input = fallback_input || DummySineInput.new(sample_rate: sample_rate)
      end

      def start
        super
        @fallback_input.start
        self
      end

      def stop
        @fallback_input.stop
        super
      end

      def read(frame_size)
        return Array.new(Integer(frame_size), 0.0) unless running?

        @fallback_input.read(frame_size)
      end
    end
  end
end
