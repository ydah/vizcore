# frozen_string_literal: true

require_relative "scene_inspector"
require_relative "scene_validator"

module Vizcore
  module CLISupport
    # Facade used by Thor commands for scene validation and inspection.
    class SceneDiagnostics
      def initialize(scene_file:)
        @validator = SceneValidator.new(scene_file: scene_file)
      end

      def validate
        @validator.call
      end

      def inspect_lines(definition)
        SceneInspector.new(definition: definition).lines
      end
    end
  end
end
