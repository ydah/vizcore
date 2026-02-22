# frozen_string_literal: true

require "open3"
require "thread"
require_relative "../errors"
require_relative "base_input"

module Vizcore
  module Audio
    # File-backed audio input for WAV and ffmpeg-decoded formats.
    class FileInput < BaseInput
      # Supported file extensions.
      SUPPORTED_EXTENSIONS = %w[.wav .mp3 .flac].freeze
      attr_reader :last_error
      attr_reader :stream_sample_rate

      # @param path [String, Pathname]
      # @param sample_rate [Integer]
      # @param command_runner [#capture3]
      # @param ffmpeg_checker [#call, nil]
      def initialize(path:, sample_rate: 44_100, command_runner: Open3, ffmpeg_checker: nil)
        super(sample_rate: sample_rate)
        @path = path
        @command_runner = command_runner
        @ffmpeg_checker = ffmpeg_checker || method(:ffmpeg_available?)
        @cursor = 0
        @last_error = nil
        @stream_sample_rate = sample_rate
        @state_mutex = Mutex.new
        @transport_paused = false
        @samples = load_samples
      end

      # @param frame_size [Integer]
      # @return [Array<Float>] file samples (looped), or silence when unavailable
      def read(frame_size)
        count = Integer(frame_size)
        return Array.new(count, 0.0) unless running?
        return Array.new(count, 0.0) if @samples.empty?

        @state_mutex.synchronize do
          return Array.new(count, 0.0) if @transport_paused

          Array.new(count) do
            sample = @samples[@cursor]
            @cursor = (@cursor + 1) % @samples.length
            sample
          end
        end
      end

      # Synchronize file cursor with an external playback transport (browser audio element).
      #
      # @param playing [Boolean]
      # @param position_seconds [Numeric]
      # @return [Vizcore::Audio::FileInput]
      def sync_transport(playing:, position_seconds:)
        return self if @samples.empty?

        seconds = Float(position_seconds)
        @state_mutex.synchronize do
          @transport_paused = !playing
          @cursor = seconds_to_cursor(seconds)
        end
        self
      rescue StandardError
        self
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
        WaveFile::Reader.new(@path) do |reader|
          @stream_sample_rate = reader.native_format.sample_rate

          reader.each_buffer(1024) do |buffer|
            mono = if buffer.channels == 1
                     buffer.samples
                   else
                     buffer.samples.map { |frame| frame.is_a?(Array) ? frame.sum / frame.length.to_f : frame }
                   end
            samples.concat(mono.map { |sample| Float(sample) })
          end
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

      def seconds_to_cursor(seconds)
        return 0 if @samples.empty?

        rate = @stream_sample_rate.to_f.positive? ? @stream_sample_rate.to_f : sample_rate.to_f
        index = (seconds * rate).floor
        index %= @samples.length
        index.negative? ? index + @samples.length : index
      end
    end
  end
end
