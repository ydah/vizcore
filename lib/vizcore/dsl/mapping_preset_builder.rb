# frozen_string_literal: true

require_relative "layer_builder"

module Vizcore
  module DSL
    # Collects reusable mapping definitions for layer-level reuse.
    class MappingPresetBuilder
      # @param name [Symbol, String] preset identifier
      # @param strict [Boolean] strict mode behavior while building mapping preset
      def initialize(name:, strict: false)
        @name = name.to_sym
        @strict = !!strict
        @builder = LayerBuilder.new(name: "#{@name}_mapping_preset", strict: @strict)
      end

      # Evaluate mapping preset block.
      #
      # @yield DSL block
      # @return [Vizcore::DSL::MappingPresetBuilder]
      def evaluate(&block)
        @builder.instance_eval(&block) if block
        self
      end

      # @return [Hash] serialized mapping preset payload
      def to_h
        {
          name: @name,
          mappings: deep_dup(@builder.to_h[:mappings] || [])
        }
      end

      private

      def deep_dup(value)
        Vizcore::DeepCopy.copy(value)
      end
    end
  end
end
