# frozen_string_literal: true

require_relative "layer_builder"
require_relative "layer_group_builder"
require_relative "style_builder"
require_relative "../deep_copy"

module Vizcore
  module DSL
    # Collects layer definitions inside a single scene block.
    class SceneBuilder
      # @param name [Symbol, String] scene identifier
      # @param styles [Hash] reusable layer parameter styles
      # @param themes [Hash] reusable scene-wide layer parameter themes
      # @param layers [Array<Hash>] initial layer definitions
      # @param strict [Boolean] true when unknown layer params should fail
      def initialize(name:, styles: {}, themes: {}, layers: [], strict: false)
        @name = name.to_sym
        @styles = styles
        @themes = themes
        @strict = !!strict
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
        builder = LayerBuilder.new(name: name, styles: @styles, defaults: @theme_params, strict: @strict)
        builder.evaluate(&block)
        @layers << builder.to_h
      end

      # Set defaults applied to every layer in this scene.
      #
      # @param params [Hash] layer params
      # @yield optional defaults block using style-like setters
      # @return [Hash]
      def scene_defaults(**params, &block)
        defaults = params.each_with_object({}) { |(key, value), output| output[key.to_sym] = value }
        if block
          block_defaults = StyleBuilder.new(name: :scene_defaults, kind: "scene_defaults").evaluate(&block).to_h[:params]
          defaults.merge!(block_defaults)
        end
        raise ArgumentError, "scene_defaults requires at least one parameter" if defaults.empty?

        @theme_params = deep_dup(@theme_params).merge(defaults)
        @layers = @layers.map { |layer| apply_theme_defaults(layer, defaults) }
        deep_dup(@theme_params)
      end

      # Remove an inherited or previously declared layer by name.
      #
      # @param name [Symbol, String]
      # @return [Hash] removed layer definition
      def remove_layer(name)
        index = layer_index!(name)
        @layers.delete_at(index)
      end

      # Replace an inherited or previously declared layer while preserving order.
      #
      # @param name [Symbol, String]
      # @yield Layer definition block
      # @return [Hash] replacement layer definition
      def replace_layer(name, &block)
        index = layer_index!(name)
        builder = LayerBuilder.new(name: name, styles: @styles, defaults: @theme_params, strict: @strict)
        builder.evaluate(&block)
        @layers[index] = builder.to_h
      end

      # Override params on an existing layer without changing its type/shader.
      #
      # @param name [Symbol, String]
      # @param params [Hash]
      # @yield optional style-like param block
      # @return [Hash] updated layer definition
      def override_layer(name, **params, &block)
        index = layer_index!(name)
        overrides = params.each_with_object({}) { |(key, value), output| output[key.to_sym] = value }
        if block
          block_overrides = StyleBuilder.new(name: name, kind: "override_layer").evaluate(&block).to_h[:params]
          overrides.merge!(block_overrides)
        end
        raise ArgumentError, "override_layer #{name} requires at least one parameter" if overrides.empty?

        layer = deep_dup(@layers[index])
        layer[:params] = Hash(layer[:params] || {}).merge(overrides)
        @layers[index] = layer
      end

      # Define a related group of layers with shared params.
      #
      # @param name [Symbol, String] group identifier
      # @yield Layer group definition block
      # @return [void]
      def group(name, &block)
        builder = LayerGroupBuilder.new(name: name, styles: @styles, defaults: @theme_params, strict: @strict)
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

      def layer_index!(name)
        normalized = name.to_sym
        index = @layers.index { |layer| layer[:name]&.to_sym == normalized }
        raise ArgumentError, "unknown layer: #{normalized}" unless index

        index
      end

      def deep_dup(value)
        Vizcore::DeepCopy.copy(value)
      end
    end
  end
end
