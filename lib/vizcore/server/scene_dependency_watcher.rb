# frozen_string_literal: true

require "pathname"
require_relative "../dsl"

module Vizcore
  module Server
    # Watches a scene file and the custom GLSL files referenced by that scene.
    class SceneDependencyWatcher
      # @param scene_file [String, Pathname]
      # @param definition [Hash] current scene definition
      # @param watcher_factory [Class] file watcher class or compatible factory
      # @yieldparam definition [Hash] reloaded scene definition
      # @yieldparam changed_path [Pathname] changed scene or shader file
      def initialize(scene_file:, definition:, watcher_factory: Vizcore::DSL::FileWatcher, &on_change)
        @scene_file = Pathname.new(scene_file.to_s).expand_path
        @definition = definition
        @watcher_factory = watcher_factory
        @on_change = on_change
        @scene_watcher = nil
        @shader_watchers = []
      end

      # @return [Vizcore::Server::SceneDependencyWatcher]
      def start
        @scene_watcher = build_watcher(@scene_file)
        @scene_watcher.start
        refresh_shader_watchers(@definition)
        self
      end

      # @param timeout [Float]
      # @return [void]
      def stop(timeout: 1.0)
        @scene_watcher&.stop(timeout: timeout)
        stop_shader_watchers(timeout: timeout)
      end

      private

      def build_watcher(path)
        @watcher_factory.new(path: path) do |changed_path|
          definition = Vizcore::DSL::Engine.load_file(@scene_file.to_s)
          @on_change&.call(definition, changed_path)
          @definition = definition
          refresh_shader_watchers(definition)
        end
      end

      def refresh_shader_watchers(definition)
        paths = shader_paths(definition)
        stop_shader_watchers
        @shader_watchers = paths.map do |path|
          build_watcher(path).tap(&:start)
        end
      end

      def stop_shader_watchers(timeout: 1.0)
        @shader_watchers.each { |watcher| watcher.stop(timeout: timeout) }
        @shader_watchers = []
      end

      def shader_paths(definition)
        Array(definition[:scenes]).flat_map do |scene|
          Array(scene[:layers]).filter_map { |layer| shader_path(layer) }
        end.uniq
      end

      def shader_path(layer)
        glsl = layer[:glsl] || layer["glsl"]
        return nil unless glsl

        path = Pathname.new(glsl.to_s)
        path = @scene_file.dirname.join(path) unless path.absolute?
        path.expand_path
      end
    end
  end
end
