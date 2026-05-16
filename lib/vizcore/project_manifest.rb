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
    def config_defaults(profile: nil)
      data = data_for(profile)
      {
        scene_file: expand_path(value_at(data, "scene") || value_at(data, "scene_file")),
        audio_source: value_at(data, "audio_source") || value_at(data, "audio", "source"),
        audio_file: expand_path(value_at(data, "audio_file") || value_at(data, "audio", "file")),
        audio_device: value_at(data, "audio_device") || value_at(data, "audio", "device"),
        feature_file: expand_path(value_at(data, "feature_file") || value_at(data, "features")),
        control_preset: expand_path(value_at(data, "control_preset") || value_at(data, "controlPreset")),
        osc_port: value_at(data, "osc_port") || value_at(data, "sync", "osc_port") || value_at(data, "sync", "osc", "port"),
        plugin_assets: plugin_assets(profile: profile)
      }.compact
    end

    # @return [Array<String>] require paths loaded before scene evaluation
    def plugins(profile: nil)
      plugin_entries(profile: profile).filter_map { |entry| plugin_require_path(entry) }.uniq
    end

    # @return [Array<Pathname>] frontend plugin assets served and loaded by RackApp
    def plugin_assets(profile: nil)
      entries = plugin_entries(profile: profile)
      assets = base_values("plugin_assets", "frontend_plugins") + profile_values(profile, "plugin_assets", "frontend_plugins")
      (entries.filter_map { |entry| plugin_asset_path(entry) } + assets.filter_map { |entry| expand_path(entry) }).uniq
    end

    # @return [Array<String>] configured profile names
    def profile_names
      Hash(@data["profiles"] || {}).keys
    end

    private

    def value_at(data, *keys)
      current = data
      keys.each do |key|
        return nil unless current.is_a?(Hash)

        current = current[key.to_s]
      end
      current
    end

    def data_for(profile)
      profile_name = profile.to_s.strip
      return @data if profile_name.empty?

      deep_merge(@data.reject { |key, _value| key == "profiles" }, profile_overlay(profile_name))
    end

    def plugin_entries(profile:)
      base_entries = base_values("plugins", ["package", "plugins"])
      profile_entries = profile_values(profile, "plugins", ["package", "plugins"])
      base_entries + profile_entries
    end

    def base_values(*paths)
      paths.each do |path|
        value = path.is_a?(Array) ? value_at(@data, *path) : value_at(@data, path)
        return Array(value) if value
      end
      []
    end

    def profile_values(profile, *paths)
      overlay = profile_overlay(profile)
      return [] if overlay.empty?

      paths.each do |path|
        value = path.is_a?(Array) ? value_at(overlay, *path) : value_at(overlay, path)
        return Array(value) if value
      end
      []
    end

    def profile_overlay(profile)
      profile_name = profile.to_s.strip
      return {} if profile_name.empty?

      profiles = Hash(@data["profiles"] || {})
      normalize_hash(profiles.fetch(profile_name) do
        raise ArgumentError, "Unknown project profile: #{profile_name}. Use one of: #{profile_names.join(', ')}"
      end)
    end

    def plugin_require_path(entry)
      value = if entry.is_a?(Hash)
                entry["require"] || entry[:require] || entry["name"] || entry[:name]
              else
                entry
              end
      plugin = value.to_s.strip
      plugin unless plugin.empty?
    end

    def plugin_asset_path(entry)
      return nil unless entry.is_a?(Hash)

      expand_path(entry["asset"] || entry[:asset] || entry["frontend"] || entry[:frontend])
    end

    def expand_path(value)
      raw_value = value.to_s.strip
      return nil if raw_value.empty?

      path_value = Pathname.new(raw_value)
      path_value.absolute? ? path_value : @root.join(path_value).expand_path
    end

    def deep_merge(base, overlay)
      base.merge(overlay) do |_key, left, right|
        left.is_a?(Hash) && right.is_a?(Hash) ? deep_merge(left, right) : right
      end
    end

    def normalize_hash(value)
      return {} unless value.is_a?(Hash)

      value.each_with_object({}) do |(key, entry), output|
        output[key.to_s] = entry.is_a?(Hash) ? normalize_hash(entry) : entry
      end
    end
  end
end
