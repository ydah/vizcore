# frozen_string_literal: true

require "pathname"
require_relative "../plugin_asset_policy"

module Vizcore
  module CLISupport
    # Performs local smoke checks for a Vizcore plugin scaffold.
    class PluginChecker
      Check = Struct.new(:name, :status, :message, keyword_init: true) do
        def failure?
          status == :fail
        end
      end

      Report = Struct.new(:checks, keyword_init: true) do
        def failure?
          checks.any?(&:failure?)
        end
      end

      # @param root [String, Pathname]
      def initialize(root)
        @root = Pathname.new(root).expand_path
      end

      # @return [Report]
      def call
        return Report.new(checks: [fail_check("Plugin root", "directory not found: #{@root}")]) unless @root.directory?

        Report.new(
          checks: [
            ruby_layer_check,
            frontend_asset_check,
            example_scene_check
          ]
        )
      end

      private

      def ruby_layer_check
        files = @root.join("lib").glob("*.rb")
        return fail_check("Ruby layer", "missing lib/*.rb") if files.empty?

        syntax_check("Ruby layer", files.first)
      end

      def frontend_asset_check
        files = @root.join("frontend").glob("*.{js,mjs}")
        return fail_check("Frontend renderer", "missing frontend/*.js or frontend/*.mjs") if files.empty?

        Vizcore::PluginAssetPolicy.validate!(files.first, root: @root)
        body = files.first.read
        return warn_check("Frontend renderer", "#{files.first} does not register globalThis.VizcorePlugins") unless body.include?("VizcorePlugins")

        ok("Frontend renderer", "#{files.first.relative_path_from(@root)} is loadable")
      rescue ArgumentError => e
        fail_check("Frontend renderer", e.message)
      end

      def example_scene_check
        files = @root.join("examples").glob("*.rb")
        return fail_check("Example scene", "missing examples/*.rb") if files.empty?

        syntax_check("Example scene", files.first)
      end

      def syntax_check(name, path)
        if defined?(RubyVM::InstructionSequence)
          RubyVM::InstructionSequence.compile_file(path.to_s)
        else
          return warn_check(name, "syntax check skipped on this Ruby engine")
        end
        ok(name, "#{path.relative_path_from(@root)} has valid Ruby syntax")
      rescue SyntaxError => e
        fail_check(name, "#{path.relative_path_from(@root)} has invalid Ruby syntax: #{e.message.lines.first&.strip}")
      end

      def ok(name, message)
        Check.new(name: name, status: :ok, message: message)
      end

      def warn_check(name, message)
        Check.new(name: name, status: :warn, message: message)
      end

      def fail_check(name, message)
        Check.new(name: name, status: :fail, message: message)
      end
    end
  end
end
