# frozen_string_literal: true
require_relative "color_helpers"

module Vizcore
  module DSL
    # Collects reusable layer parameter presets for the `style` DSL.
    class StyleBuilder
      include ColorHelpers

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

      # Store an ordered color palette for styles and themes.
      #
      # @param colors [Array<String, Array<String>>] color values such as "#00ffff"
      # @raise [ArgumentError] when no non-blank colors are supplied
      # @return [Array<String>]
      def palette(*colors)
        @params[:palette] = normalize_palette(colors)
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

      private

      def normalize_palette(colors)
        values = colors.flatten.map { |color| color.to_s.strip }.reject(&:empty?)
        raise ArgumentError, "#{@kind} #{@name} palette requires at least one color" if values.empty?

        values
      end
    end
  end
end
