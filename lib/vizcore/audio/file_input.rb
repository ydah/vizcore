# frozen_string_literal: true

require_relative "base_input"

module Vizcore
  module Audio
    class FileInput < BaseInput
      def initialize(path:, sample_rate: 44_100)
        super(sample_rate: sample_rate)
        @path = path
        @cursor = 0
        @samples = load_samples
      end

      def read(frame_size)
        count = Integer(frame_size)
        return Array.new(count, 0.0) unless running?
        return Array.new(count, 0.0) if @samples.empty?

        output = Array.new(count) do
          sample = @samples[@cursor]
          @cursor = (@cursor + 1) % @samples.length
          sample
        end

        output
      end

      private

      def load_samples
        return [] unless @path
        return [] unless File.file?(@path)
        return [] unless File.extname(@path).downcase == ".wav"

        require "wavefile"

        samples = []
        WaveFile::Reader.new(@path).each_buffer(1024) do |buffer|
          mono = if buffer.channels == 1
                   buffer.samples
                 else
                   buffer.samples.map { |frame| frame.is_a?(Array) ? frame.sum / frame.length.to_f : frame }
                 end
          samples.concat(mono.map { |sample| Float(sample) })
        end
        samples
      rescue LoadError
        []
      end
    end
  end
end
