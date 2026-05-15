# frozen_string_literal: true

require "json"
require "pathname"
require_relative "feature_recorder"

module Vizcore
  module Analysis
    # Replays recorded analysis features as a pipeline-compatible source.
    class FeatureReplay
      attr_reader :metadata

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

      private

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
        case value
        when Hash
          value.each_with_object({}) { |(key, entry), output| output[key] = deep_dup(entry) }
        when Array
          value.map { |entry| deep_dup(entry) }
        else
          value
        end
      end
    end
  end
end
