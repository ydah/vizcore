# frozen_string_literal: true

require "json"
require "pathname"
require_relative "feature_recorder"

module Vizcore
  module Analysis
    # Replays recorded analysis features as a pipeline-compatible source.
    class FeatureReplay
      attr_reader :metadata, :cursor

      def initialize(path:)
        @path = Pathname.new(path.to_s).expand_path
        payload = load_payload
        @metadata = deep_symbolize(payload.fetch("metadata", {}))
        @features = load_features(payload)
        @cursor = 0
      end

      # @param _samples [Array<Float>, nil] ignored; replay data already contains analyzed features
      # @return [Hash<Symbol, Object>] recorded audio analysis for the next frame
      def call(_samples = nil)
        audio = @features.fetch(@cursor)
        @cursor = (@cursor + 1) % @features.length
        deep_dup(audio)
      end

      def frame_count
        @features.length
      end

      # Move the replay cursor to a frame index.
      #
      # @param index [Integer]
      # @return [Vizcore::Analysis::FeatureReplay]
      def seek(index)
        @cursor = normalize_index(index)
        self
      end

      # Move the replay cursor to the frame nearest to the given timestamp.
      #
      # @param seconds [Numeric]
      # @return [Vizcore::Analysis::FeatureReplay]
      def seek_seconds(seconds)
        fps = metadata_fps
        raise ArgumentError, "feature metadata fps must be positive to seek by seconds" unless fps.positive?

        seek((numeric_seconds(seconds) * fps).floor)
      end

      # Read a specific feature frame without changing the replay cursor.
      #
      # @param index [Integer]
      # @return [Hash<Symbol, Object>]
      def frame(index)
        deep_dup(@features.fetch(normalize_index(index)))
      end

      private

      def metadata_fps
        Float(metadata[:fps] || metadata["fps"] || 0.0)
      rescue ArgumentError, TypeError
        0.0
      end

      def numeric_seconds(value)
        Float(value)
      rescue ArgumentError, TypeError
        raise ArgumentError, "seconds must be numeric"
      end

      def load_payload
        raise ArgumentError, "Feature file not found: #{@path}" unless @path.file?

        payload = JSON.parse(@path.read)
        version = payload["version"]
        return payload if version == FeatureRecorder::VERSION

        raise ArgumentError, "Unsupported feature file version: #{version.inspect}"
      rescue JSON::ParserError => e
        raise ArgumentError, "Invalid feature file JSON: #{e.message}"
      end

      def load_features(payload)
        features = Array(payload["features"]).map.with_index do |entry, index|
          audio = Hash(entry).fetch("audio", nil)
          raise ArgumentError, "Feature frame #{index} is missing audio data" unless audio.is_a?(Hash)

          deep_symbolize(audio)
        end
        raise ArgumentError, "Feature file contains no frames" if features.empty?

        features
      end

      def normalize_index(value)
        Integer(value) % @features.length
      rescue ArgumentError, TypeError
        raise ArgumentError, "feature frame index must be an integer"
      end

      def deep_symbolize(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, entry), output|
            output[key.to_s.to_sym] = deep_symbolize(entry)
          end
        when Array
          value.map { |entry| deep_symbolize(entry) }
        else
          value
        end
      end

      def deep_dup(value)
        Vizcore::DeepCopy.copy(value)
      end
    end
  end
end
