# frozen_string_literal: true

require_relative "base_input"

module Vizcore
  module Audio
    class DummySineInput < BaseInput
      DEFAULT_AMPLITUDE = 0.45
      DEFAULT_FREQUENCY = 220.0

      def initialize(sample_rate: 44_100, frequency: DEFAULT_FREQUENCY, amplitude: DEFAULT_AMPLITUDE)
        super(sample_rate: sample_rate)
        @frequency = Float(frequency)
        @amplitude = Float(amplitude).clamp(0.0, 1.0)
        @phase = 0.0
      end

      def read(frame_size)
        count = Integer(frame_size)
        return Array.new(count, 0.0) unless running?

        step = (2.0 * Math::PI * @frequency) / sample_rate

        Array.new(count) do
          value = Math.sin(@phase) * @amplitude
          @phase += step
          value
        end
      end
    end
  end
end
