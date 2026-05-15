# frozen_string_literal: true

require_relative "layer_builder"
require_relative "layer_group_builder"

module Vizcore
  module DSL
    # Collects layer definitions inside a single scene block.
    class SceneBuilder
      # @param name [Symbol, String] scene identifier
      # @param styles [Hash] reusable layer parameter styles
      # @param themes [Hash] reusable scene-wide layer parameter themes
      # @param layers [Array<Hash>] initial layer definitions
      def initialize(name:, styles: {}, themes: {}, layers: [])
        @name = name.to_sym
        @styles = styles
        @themes = themes
        @theme_name = nil
        @theme_params = {}
        @layers = layers.map { |layer| deep_dup(layer) }
      end

      # Evaluate a scene block.
      #
      # @yield Layer definitions
      # @return [Vizcore::DSL::SceneBuilder]
      def evaluate(&block)
        instance_eval(&block) if block
        self
      end

      # Define one layer in this scene.
      #
      # @param name [Symbol, String] layer identifier
      # @yield Layer definition block
      # @return [void]
      def layer(name, &block)
        builder = LayerBuilder.new(name: name, styles: @styles, defaults: @theme_params)
        builder.evaluate(&block)
        @layers << builder.to_h
      end

      # Define a related group of layers with shared params.
      #
      # @param name [Symbol, String] group identifier
      # @yield Layer group definition block
      # @return [void]
      def group(name, &block)
        builder = LayerGroupBuilder.new(name: name, styles: @styles, defaults: @theme_params)
        builder.evaluate(&block)
        @layers.concat(builder.to_a)
      end

      # Apply a named theme as default params for all layers in this scene.
      #
      # @param name [Symbol, String] theme identifier
      # @raise [ArgumentError] when the theme is unknown
      # @return [Hash] applied theme params
      def use_theme(name)
        theme_name = name.to_sym
        theme_params = @themes.fetch(theme_name) { raise ArgumentError, "unknown theme: #{theme_name}" }
        @theme_name = theme_name
        @theme_params = deep_dup(theme_params)
        @layers = @layers.map { |layer| apply_theme_defaults(layer, @theme_params) }
        deep_dup(@theme_params)
      end

      # @return [Hash] serialized scene payload
      def to_h
        scene = {
          name: @name,
          layers: @layers.map { |layer| deep_dup(layer) }
        }
        scene[:theme] = @theme_name if @theme_name
        scene
      end

      private

      def apply_theme_defaults(layer, theme_params)
        themed_layer = deep_dup(layer)
        themed_layer[:params] = deep_dup(theme_params).merge(Hash(themed_layer[:params] || {}))
        themed_layer
      end

      def deep_dup(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, entry), output|
            output[key] = deep_dup(entry)
          end
        when Array
          value.map { |entry| deep_dup(entry) }
        else
          value
        end
      end
    end
  end
end
