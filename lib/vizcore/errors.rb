# frozen_string_literal: true

module Vizcore
  # Invalid or missing user-provided configuration.
  class ConfigurationError < ArgumentError; end

  # Scene DSL could not be loaded or resolved.
  class SceneLoadError < ArgumentError; end

  # Audio source initialization/processing failure.
  class AudioSourceError < StandardError; end

  # Frame generation failed in the render pipeline.
  class FrameBuildError < StandardError; end

  # Small helper for concise contextual error messages.
  module ErrorFormatting
    module_function

    # @param error [Exception]
    # @param context [String]
    # @return [String]
    def summarize(error, context:)
      "#{context}: #{error.class}: #{error.message}"
    end
  end
end
