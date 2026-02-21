# frozen_string_literal: true

module Vizcore
  module Audio
    class BaseInput
      attr_reader :sample_rate

      def initialize(sample_rate: 44_100)
        @sample_rate = Integer(sample_rate)
        @running = false
      end

      def start
        @running = true
        self
      end

      def stop
        @running = false
        self
      end

      def running?
        @running
      end

      def read(frame_size)
        Array.new(Integer(frame_size), 0.0)
      end
    end
  end
end
