# frozen_string_literal: true

require "thread"

module Vizcore
  module Audio
    class RingBuffer
      attr_reader :capacity

      def initialize(capacity)
        raise ArgumentError, "capacity must be positive" unless capacity.to_i.positive?

        @capacity = Integer(capacity)
        @buffer = Array.new(@capacity, 0.0)
        @write_index = 0
        @size = 0
        @mutex = Mutex.new
      end

      def write(samples)
        normalized = normalize_samples(samples)
        return if normalized.empty?

        @mutex.synchronize do
          normalized.each do |sample|
            @buffer[@write_index] = sample
            @write_index = (@write_index + 1) % @capacity
            @size += 1 if @size < @capacity
          end
        end
      end

      def push(sample)
        write([sample])
      end

      def latest(count = nil)
        @mutex.synchronize do
          return [] if @size.zero?

          requested = count ? Integer(count) : @size
          return [] if requested <= 0

          length = [requested, @size].min
          start = (@write_index - length) % @capacity

          extract_range(start, length)
        end
      end

      def size
        @mutex.synchronize { @size }
      end

      def clear
        @mutex.synchronize do
          @buffer.fill(0.0)
          @write_index = 0
          @size = 0
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
