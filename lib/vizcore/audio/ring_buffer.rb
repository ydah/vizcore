# frozen_string_literal: true

require "thread"

module Vizcore
  module Audio
    # Thread-safe circular buffer for recent audio samples.
    class RingBuffer
      attr_reader :capacity

      # @param capacity [Integer]
      def initialize(capacity)
        raise ArgumentError, "capacity must be positive" unless capacity.to_i.positive?

        @capacity = Integer(capacity)
        @buffer = Array.new(@capacity, 0.0)
        @write_index = 0
        @size = 0
        @write_count = 0
        @overrun_count = 0
        @underrun_count = 0
        @mutex = Mutex.new
      end

      # @param samples [Array<Numeric>]
      # @return [void]
      def write(samples)
        normalized = normalize_samples(samples)
        return if normalized.empty?

        @mutex.synchronize do
          normalized.each do |sample|
            @overrun_count += 1 if @size == @capacity
            @buffer[@write_index] = sample
            @write_index = (@write_index + 1) % @capacity
            @write_count += 1
            @size += 1 if @size < @capacity
          end
        end
      end

      # @param sample [Numeric]
      # @return [void]
      def push(sample)
        write([sample])
      end

      # @param count [Integer, nil]
      # @return [Array<Float>] newest values first-in-order
      def latest(count = nil)
        @mutex.synchronize do
          return [] if @size.zero?

          requested = count ? Integer(count) : @size
          return [] if requested <= 0

          @underrun_count += requested - @size if requested > @size
          length = [requested, @size].min
          start = (@write_index - length) % @capacity

          extract_range(start, length)
        end
      end

      # @return [Integer]
      def size
        @mutex.synchronize { @size }
      end

      # @return [Hash] buffer health counters for runtime diagnostics.
      def metrics
        @mutex.synchronize do
          {
            capacity: @capacity,
            size: @size,
            write_count: @write_count,
            overrun_count: @overrun_count,
            underrun_count: @underrun_count
          }
        end
      end

      # @return [void]
      def clear
        @mutex.synchronize do
          @buffer.fill(0.0)
          @write_index = 0
          @size = 0
          @write_count = 0
          @overrun_count = 0
          @underrun_count = 0
        end
      end

      private

      def extract_range(start, length)
        if start + length <= @capacity
          @buffer[start, length].dup
        else
          tail = @buffer[start, @capacity - start]
          head = @buffer[0, length - tail.length]
          tail + head
        end
      end

      def normalize_samples(samples)
        Array(samples).map { |sample| Float(sample) }
      rescue ArgumentError, TypeError
        raise ArgumentError, "samples must be numeric"
      end
    end
  end
end
