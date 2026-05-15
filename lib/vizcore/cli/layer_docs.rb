# frozen_string_literal: true

require_relative "../layer_catalog"

module Vizcore
  module CLISupport
    # Formats built-in layer capability metadata for CLI output.
    class LayerDocs
      def lines
        [
          "# Vizcore Layer Capabilities",
          "",
          *layer_lines,
          "",
          "Built-in shaders: #{Vizcore::LayerCatalog::BUILTIN_SHADERS.join(', ')}",
          "Blend modes: #{Vizcore::LayerCatalog::BLEND_MODES.join(', ')}",
          "Post effects: #{Vizcore::LayerCatalog::POST_EFFECTS.join(', ')}",
          "VJ effects: #{Vizcore::LayerCatalog::VJ_EFFECTS.join(', ')}"
        ]
      end

      private

      def layer_lines
        Vizcore::LayerCatalog.capabilities.flat_map do |capability|
          aliases = capability.aliases.empty? ? "" : " (aliases: #{capability.aliases.join(', ')})"
          [
            "## #{capability.type}#{aliases}",
            capability.description,
            "Params: #{format_params(capability.params)}",
            "Mappable params: #{format_list(capability.mappable_params)}",
            ""
          ]
        end.tap(&:pop)
      end

      def format_params(params)
        params.map { |name, type| "#{name}: #{type}" }.join(", ")
      end

      def format_list(values)
        values.empty? ? "(none)" : values.join(", ")
      end
    end
  end
end
