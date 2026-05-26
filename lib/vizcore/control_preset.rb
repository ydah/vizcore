# frozen_string_literal: true

require "fileutils"
require "json"
require "pathname"

module Vizcore
  # Loads browser control presets shared through the runtime endpoint.
  class ControlPreset
    # @param path [String, Pathname]
    # @return [Hash]
    def self.load(path)
      new(path).load
    end

    # @param path [String, Pathname]
    # @param payload [Hash]
    # @return [Hash]
    def self.write(path, payload)
      new(path).write(payload)
    end

    # @param path [String, Pathname]
    def initialize(path)
      @path = Pathname.new(path).expand_path
    end

    # @return [Hash]
    def load
      raise ArgumentError, "Control preset file not found: #{@path}" unless @path.file?

      parsed = JSON.parse(@path.read)
      normalize_payload(parsed)
    rescue JSON::ParserError => e
      raise ArgumentError, "Invalid control preset JSON #{@path}: #{e.message}"
    end

    # @param payload [Hash]
    # @return [Hash]
    def write(payload)
      normalized = normalize_payload(payload)
      FileUtils.mkdir_p(@path.dirname)
      @path.write(JSON.pretty_generate(normalized) << "\n")
      normalized
    end

    private

    def normalize_payload(value)
      input = value.is_a?(Hash) ? value : {}
      visual_settings = hash_value(input, "visual_settings", "visualSettings", "settings")
      midi_learn_bindings = hash_value(input, "midi_learn_bindings", "midiLearnBindings", "midi")
      scene_overrides = hash_value(input, "scene_overrides", "sceneOverrides")

      {}.tap do |payload|
        payload["visual_settings"] = visual_settings if visual_settings
        payload["midi_learn_bindings"] = midi_learn_bindings if midi_learn_bindings
        normalized_scene_overrides = normalize_scene_overrides(scene_overrides)
        payload["scene_overrides"] = normalized_scene_overrides if normalized_scene_overrides
      end
    end

    def normalize_scene_overrides(value)
      return nil unless value
      raw_overrides = value.is_a?(Hash) ? value : {}
      normalized = {}

      raw_overrides.each do |raw_scene, raw_override|
        scene_name = raw_scene.to_s.strip
        next if scene_name.empty?

        scene_override = normalize_scene_override(raw_override)
        next if scene_override.empty?

        normalized[scene_name] = scene_override
      end

      normalized.empty? ? nil : normalized
    end

    def normalize_scene_override(value)
      input = value.is_a?(Hash) ? value : {}
      {
        "visual_settings" => hash_value(input, "visual_settings", "visualSettings"),
        "midi_learn_bindings" => hash_value(input, "midi_learn_bindings", "midiLearnBindings", "midi")
      }.select { |_, entry| entry }
    end

    def hash_value(input, *keys)
      keys.each do |key|
        value = input[key] || input[key.to_sym]
        return value if value.is_a?(Hash)
      end
      nil
    end
  end
end
