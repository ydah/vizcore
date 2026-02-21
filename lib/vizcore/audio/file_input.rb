# frozen_string_literal: true

require "open3"
require_relative "../errors"
require_relative "base_input"

module Vizcore
  module Audio
    class FileInput < BaseInput
      SUPPORTED_EXTENSIONS = %w[.wav .mp3 .flac].freeze
      attr_reader :last_error

      def initialize(path:, sample_rate: 44_100, command_runner: Open3, ffmpeg_checker: nil)
        super(sample_rate: sample_rate)
        @path = path
        @command_runner = command_runner
        @ffmpeg_checker = ffmpeg_checker || method(:ffmpeg_available?)
        @cursor = 0
        @last_error = nil
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
        return record_error(AudioSourceError.new("Audio file not found: #{@path}")) unless File.file?(@path)
        return record_error(AudioSourceError.new("Unsupported audio format: #{extension}")) unless SUPPORTED_EXTENSIONS.include?(extension)

        return load_wav_samples if extension == ".wav"

        load_compressed_samples
      end

      def extension
        File.extname(@path).downcase
      end

      def load_wav_samples
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
        @last_error = nil
        samples
      rescue LoadError => e
        record_error(
          AudioSourceError.new(
            "wavefile gem is required for WAV input: #{e.message}"
          )
        )
      end

      def load_compressed_samples
        return record_error(AudioSourceError.new("ffmpeg is unavailable")) unless @ffmpeg_checker.call

        stdout, _stderr, status = @command_runner.capture3(*ffmpeg_decode_command)
        return record_error(AudioSourceError.new("ffmpeg decode failed with non-zero status")) unless status.success?

        @last_error = nil
        stdout.unpack("e*").map { |sample| Float(sample) }
      rescue StandardError => e
        record_error(AudioSourceError.new("ffmpeg decode failed: #{e.message}"))
      end

      def ffmpeg_decode_command
        [
          "ffmpeg",
          "-hide_banner",
          "-loglevel",
          "error",
          "-i",
          @path.to_s,
          "-f",
          "f32le",
          "-ac",
          "1",
          "-ar",
          sample_rate.to_s,
          "pipe:1"
        ]
      end

      def ffmpeg_available?
        system("ffmpeg", "-version", out: File::NULL, err: File::NULL)
      rescue StandardError
        false
      end

      def record_error(error)
        @last_error = error
        []
      end
    end
  end
end
