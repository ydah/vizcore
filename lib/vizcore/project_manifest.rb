# frozen_string_literal: true

require "pathname"
require "yaml"

module Vizcore
  # Reads a project-level manifest such as vizcore.yml.
  class ProjectManifest
    # @param path [String, Pathname]
    # @return [Vizcore::ProjectManifest]
    def self.load(path)
      new(path)
    end

    attr_reader :path, :root

    # @param path [String, Pathname]
    def initialize(path)
      @path = Pathname.new(path).expand_path
      raise ArgumentError, "Project manifest not found: #{@path}" unless @path.file?

      @root = @path.dirname
      @data = normalize_hash(YAML.safe_load_file(@path, aliases: false) || {})
    rescue Psych::Exception => e
      raise ArgumentError, "Invalid project manifest #{@path}: #{e.message}"
    end

    # @return [Hash] config defaults accepted by Vizcore::Config
    def config_defaults
      {
        scene_file: expand_path(value_at("scene") || value_at("scene_file")),
        audio_source: value_at("audio_source") || value_at("audio", "source"),
        audio_file: expand_path(value_at("audio_file") || value_at("audio", "file")),
        audio_device: value_at("audio_device") || value_at("audio", "device"),
        feature_file: expand_path(value_at("feature_file") || value_at("features")),
        control_preset: expand_path(value_at("control_preset") || value_at("controlPreset"))
      }.compact
    end

    # @return [Array<String>] require paths loaded before scene evaluation
    def plugins
      values = value_at("plugins") || value_at("package", "plugins")
      Array(values).filter_map do |value|
        plugin = value.to_s.strip
        plugin unless plugin.empty?
      end
    end

    private

    def value_at(*keys)
      keys.reduce(@data) do |current, key|
        break nil unless current.is_a?(Hash)

        current[key.to_s]
      end
    end

    def expand_path(value)
      raw_value = value.to_s.strip
      return nil if raw_value.empty?

      path_value = Pathname.new(raw_value)
      path_value.absolute? ? path_value : @root.join(path_value).expand_path
    end

    def normalize_hash(value)
      return {} unless value.is_a?(Hash)

      value.each_with_object({}) do |(key, entry), output|
        output[key.to_s] = entry.is_a?(Hash) ? normalize_hash(entry) : entry
      end
    end
  end
end
