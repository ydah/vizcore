# frozen_string_literal: true

require_relative "layer_builder"

module Vizcore
  module DSL
    class SceneBuilder
      def initialize(name:)
        @name = name.to_sym
        @layers = []
      end

      def evaluate(&block)
        instance_eval(&block) if block
        self
      end

      def layer(name, &block)
        builder = LayerBuilder.new(name: name)
        builder.evaluate(&block)
        @layers << builder.to_h
      end

      def to_h
        {
          name: @name,
          layers: @layers.map { |layer| layer.dup }
        }
      end
    end
  end
end
