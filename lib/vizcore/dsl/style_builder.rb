# frozen_string_literal: true

module Vizcore
  module DSL
    # Collects reusable layer parameter presets for the `style` DSL.
    class StyleBuilder
      # @param name [Symbol, String] style identifier
      # @param kind [String] user-facing DSL kind for error messages
      def initialize(name:, kind: "style")
        @name = name.to_sym
        @kind = kind
        @params = {}
      end

      # Evaluate a style block.
      #
      # @yield Style parameter declarations
      # @return [Vizcore::DSL::StyleBuilder]
      def evaluate(&block)
        instance_eval(&block) if block
        raise ArgumentError, "#{@kind} #{@name} requires at least one parameter" if @params.empty?

        self
      end

      # @return [Hash] serialized style payload
      def to_h
        {
          name: @name,
          params: @params.dup
        }
      end

      # Stores one-argument style setters into `params`.
      # @api private
      def method_missing(method_name, *args, &block)
        if block.nil? && args.length == 1
          @params[method_name.to_sym] = args.first
          return args.first
        end

        super
      end

      def respond_to_missing?(_method_name, _include_private = false)
        true
      end
    end
  end
end
