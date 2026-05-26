# frozen_string_literal: true

module Vizcore
  module DSL
    # Collects high-level `react_to` DSL entries and converts them to mappings.
    class ReactionBuilder
      # @param mapping_factory [#call] builds one normalized mapping hash
      def initialize(mapping_factory:)
        @mapping_factory = mapping_factory
        @mappings = []
      end

      # Evaluate a `react_to` block.
      #
      # @yield Reaction DSL methods
      # @raise [ArgumentError] when the block does not define any reaction
      # @return [Array<Hash>] normalized mapping payloads
      def evaluate(&block)
        instance_eval(&block) if block
        raise ArgumentError, "react_to requires at least one change or trigger" if @mappings.empty?

        @mappings.map(&:dup)
      end

      # Continuously map the reaction source to a target parameter.
      #
      # @param target [Symbol, String] layer parameter name
      # @param options [Hash] mapping transform options
      # @return [void]
      def change(target, **options)
        @mappings << @mapping_factory.call(target, options)
      end

      # Map the reaction source to an event-like target parameter.
      #
      # @param target [Symbol, String] layer parameter name
      # @param options [Hash] mapping transform options
      # @return [void]
      def trigger(target, **options)
        options = options.merge(as: :trigger) unless options.key?(:as)
        change(target, **options)
      end
    end
  end
end
