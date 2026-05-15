# frozen_string_literal: true

require_relative "layer_builder"

module Vizcore
  module DSL
    # Collects layer definitions inside a single scene block.
    class SceneBuilder
      # @param name [Symbol, String] scene identifier
      # @param styles [Hash] reusable layer parameter styles
      # @param layers [Array<Hash>] initial layer definitions
      def initialize(name:, styles: {}, layers: [])
        @name = name.to_sym
        @styles = styles
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
        builder = LayerBuilder.new(name: name, styles: @styles)
        builder.evaluate(&block)
        @layers << builder.to_h
      end

      # @return [Hash] serialized scene payload
      def to_h
        {
          name: @name,
          layers: @layers.map { |layer| deep_dup(layer) }
        }
      end

      private

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
