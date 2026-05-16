# frozen_string_literal: true

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

    private

    def normalize_payload(value)
      input = value.is_a?(Hash) ? value : {}
      visual_settings = hash_value(input, "visual_settings", "visualSettings", "settings")
      midi_learn_bindings = hash_value(input, "midi_learn_bindings", "midiLearnBindings", "midi")

      {}.tap do |payload|
        payload["visual_settings"] = visual_settings if visual_settings
        payload["midi_learn_bindings"] = midi_learn_bindings if midi_learn_bindings
      end
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
