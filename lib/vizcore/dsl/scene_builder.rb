# frozen_string_literal: true

require_relative "layer_builder"

module Vizcore
  module DSL
    # Collects layer definitions inside a single scene block.
    class SceneBuilder
      # @param name [Symbol, String] scene identifier
      def initialize(name:)
        @name = name.to_sym
        @layers = []
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
        builder = LayerBuilder.new(name: name)
        builder.evaluate(&block)
        @layers << builder.to_h
      end

      # @return [Hash] serialized scene payload
      def to_h
        {
          name: @name,
          layers: @layers.map { |layer| layer.dup }
        }
      end
    end
  end
end
