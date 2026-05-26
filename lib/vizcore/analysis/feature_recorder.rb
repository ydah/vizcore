# frozen_string_literal: true

require "fileutils"
require "digest"
require "json"
require "pathname"
require_relative "../audio/file_input"
require_relative "../audio/input_manager"
require_relative "pipeline"

module Vizcore
  module Analysis
    # Records deterministic audio analysis features from a file source.
    class FeatureRecorder
      VERSION = "vizcore.features.v1"
      DEFAULT_FRAME_COUNT = 300
      DEFAULT_FRAME_RATE = 30.0

      def initialize(
        audio_file:,
        frames: DEFAULT_FRAME_COUNT,
        fps: DEFAULT_FRAME_RATE,
        noise_gate: Pipeline::DEFAULT_NOISE_GATE,
        audio_normalize: nil,
        bpm: nil,
        bpm_lock: false,
        cache_root: nil
      )
        @audio_file = Pathname.new(audio_file.to_s).expand_path
        @frames = normalize_frame_count(frames)
        @fps = normalize_frame_rate(fps)
        @noise_gate = Float(noise_gate)
        @audio_normalize = audio_normalize
        @bpm = bpm
        @bpm_lock = bpm_lock
        @cache_root = normalize_cache_root(cache_root)
      end

      # Absolute cache file path for current recorder settings.
      #
      # @return [Pathname, nil]
      def cache_path
        return nil unless @cache_root

        @cache_root.join("#{cache_key}.json")
      end

      # @param out [String, Pathname] JSON output path
      # @return [Hash] recorder metadata
      def write(out:)
        output_path = Pathname.new(out.to_s).expand_path
        FileUtils.mkdir_p(output_path.dirname)

        if cache_path
          cached_payload = load_cached_payload(cache_path)
          output_payload = cached_payload if cached_payload
        end

        output_payload ||= record
        output_path.write("#{JSON.pretty_generate(output_payload)}\n")
        write_cached_output(output_payload) if cache_path && cache_path != output_path

        metadata_from_payload(output_payload, path: output_path)
      end

      # Stable hash key for this recorder configuration.
      #
      # @return [String]
      def cache_key
        self.class.cache_key(
          version: VERSION,
          audio_file: @audio_file,
          frames: @frames,
          fps: @fps,
          noise_gate: @noise_gate,
          audio_normalize: @audio_normalize,
          bpm: @bpm,
          bpm_lock: @bpm_lock
        )
      end

      # @return [Hash] recorder metadata
      def self.cache_key(version:, audio_file:, frames:, fps:, noise_gate:, audio_normalize:, bpm:, bpm_lock:)
        audio_path = Pathname.new(audio_file.to_s).expand_path
        Digest::SHA256.hexdigest(
          JSON.generate(
            {
              version: version,
              audio_file: audio_path.to_s,
              audio_file_size: audio_file_size(audio_path),
              audio_file_mtime: audio_file_mtime(audio_path),
              frames: frames,
              fps: fps,
              noise_gate: noise_gate,
              audio_normalize: audio_normalize,
              bpm: bpm,
              bpm_lock: bpm_lock
            }
          )
        )
      end

      def self.audio_file_size(path)
        file_stat_value(path, :size)
      end

      def self.audio_file_mtime(path)
        file_stat_value(path, :mtime).to_i
      rescue StandardError
        0
      end

      def self.file_stat_value(path, name)
        stat = Pathname.new(path).stat
        stat.send(name)
      rescue StandardError
        0
      end

      private

      def load_cached_payload(path)
        payload = JSON.parse(Pathname.new(path).read)
        return unless payload.is_a?(Hash)

        payload if valid_cached_payload?(payload)
      rescue StandardError
        nil
      end

      def valid_cached_payload?(payload)
        payload.fetch("version", nil) == VERSION &&
          payload.fetch("metadata", {}).fetch("frames", nil) == @frames &&
          (Float(payload.fetch("metadata", {}).fetch("fps", nil)) - @fps).abs < Float::EPSILON &&
          payload.fetch("features", nil).is_a?(Array) &&
          !payload.fetch("features", []).empty?
      end

      def write_cached_output(payload)
        cache = cache_path
        return unless cache

        FileUtils.mkdir_p(cache.dirname)
        cache.write("#{JSON.pretty_generate(payload)}\n")
      end

      def metadata_from_payload(payload, path:)
        metadata = payload.fetch("metadata", {})
        {
          path: path,
          frames: metadata.fetch("frames"),
          fps: metadata.fetch("fps"),
          sample_rate: metadata.fetch("sample_rate")
        }
      end

      def normalize_cache_root(value)
        return nil if value.nil?

        Pathname.new(value.to_s).expand_path
      end

      def record
        validate_audio_file!
        input = Vizcore::Audio::FileInput.new(path: @audio_file.to_s)
        raise ArgumentError, input.last_error.message if input.last_error

        input.start
        sample_rate = input.stream_sample_rate
        capture_size = capture_size_for(sample_rate)
        pipeline = build_pipeline(sample_rate)
        features = @frames.times.map do |index|
          {
            "index" => index,
            "time" => (index / @fps).round(6),
            "audio" => serializable(pipeline.call(input.read(capture_size)))
          }
        end
        payload(sample_rate: sample_rate, capture_size: capture_size, features: features)
      ensure
        input&.stop
      end

      def payload(sample_rate:, capture_size:, features:)
        {
          "version" => VERSION,
          "metadata" => {
            "audio_file" => @audio_file.to_s,
            "frames" => @frames,
            "fps" => @fps,
            "sample_rate" => sample_rate,
            "capture_size" => capture_size,
            "noise_gate" => @noise_gate,
            "bpm" => @bpm,
            "bpm_lock" => @bpm_lock,
            "audio_normalize" => serializable(@audio_normalize)
          },
          "features" => features
        }
      end

      def build_pipeline(sample_rate)
        Pipeline.new(
          sample_rate: sample_rate,
          fft_size: supported_fft_size(Vizcore::Audio::InputManager::DEFAULT_FRAME_SIZE),
          noise_gate: @noise_gate,
          audio_normalize: @audio_normalize,
          bpm: @bpm,
          bpm_lock: @bpm_lock
        )
      end

      def validate_audio_file!
        raise ArgumentError, "Audio file not found: #{@audio_file}" unless @audio_file.file?
        return if Vizcore::Audio::FileInput::SUPPORTED_EXTENSIONS.include?(@audio_file.extname.downcase)

        raise ArgumentError, "Unsupported audio format: #{@audio_file.extname.downcase}"
      end

      def capture_size_for(sample_rate)
        [(sample_rate.to_f / @fps).round, 1].max
      end

      def supported_fft_size(size)
        value = Integer(size)
        return value if value.positive? && (value & (value - 1)).zero?

        Vizcore::Audio::InputManager::DEFAULT_FRAME_SIZE
      rescue StandardError
        Vizcore::Audio::InputManager::DEFAULT_FRAME_SIZE
      end

      def serializable(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, entry), output|
            output[key.to_s] = serializable(entry)
          end
        when Array
          value.map { |entry| serializable(entry) }
        when Float
          value.finite? ? value.round(6) : 0.0
        when Symbol
          value.to_s
        else
          value
        end
      end

      def normalize_frame_count(value)
        count = Integer(value)
        raise ArgumentError, "frames must be positive" unless count.positive?

        count
      rescue ArgumentError, TypeError
        raise ArgumentError, "frames must be a positive integer"
      end

      def normalize_frame_rate(value)
        rate = Float(value)
        raise ArgumentError, "fps must be positive" unless rate.positive?

        rate
      rescue ArgumentError, TypeError
        raise ArgumentError, "fps must be a positive number"
      end
    end
  end
end
