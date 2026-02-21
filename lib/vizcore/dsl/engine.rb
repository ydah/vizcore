# frozen_string_literal: true

require "pathname"
require_relative "file_watcher"
require_relative "scene_builder"

module Vizcore
  module DSL
    class Engine
      THREAD_KEY = :vizcore_current_dsl_engine

      class << self
        def define(&block)
          engine = current || new
          engine.evaluate(&block)
        end

        def load_file(path)
          scene_path = Pathname.new(path.to_s).expand_path
          raise ArgumentError, "Scene file not found: #{scene_path}" unless scene_path.file?

          engine = new
          with_current(engine) { Kernel.load(scene_path.to_s) }
          engine.result
        end

        def watch_file(path, poll_interval: FileWatcher::DEFAULT_POLL_INTERVAL, listener_factory: nil, &on_change)
          FileWatcher.new(path: path, poll_interval: poll_interval, listener_factory: listener_factory) do |changed_path|
            definition = load_file(changed_path.to_s)
            on_change&.call(definition, changed_path)
          end
        end

        def current
          Thread.current[THREAD_KEY]
        end

        private

        def with_current(engine)
          previous = current
          Thread.current[THREAD_KEY] = engine
          yield
        ensure
          Thread.current[THREAD_KEY] = previous
        end
      end

      def initialize
        @audio_inputs = []
        @midi_inputs = []
        @scenes = []
        @transitions = []
        @midi_mappings = []
        @global_params = {}
      end

      def evaluate(&block)
        instance_eval(&block) if block
        result
      end

      def audio(name, **options)
        @audio_inputs << { name: name.to_sym, options: symbolize_keys(options) }
      end

      def midi(name, **options)
        @midi_inputs << { name: name.to_sym, options: symbolize_keys(options) }
      end

      def scene(name, &block)
        builder = SceneBuilder.new(name: name)
        builder.evaluate(&block)
        @scenes << builder.to_h
      end

      def transition(from:, to:, &block)
        definition = {
          from: from.to_sym,
          to: to.to_sym
        }
        builder = TransitionBuilder.new
        builder.instance_eval(&block) if block
        @transitions << definition.merge(builder.to_h)
      end

      def midi_map(note: nil, cc: nil, pc: nil, &block)
        trigger = {}
        trigger[:note] = Integer(note) unless note.nil?
        trigger[:cc] = Integer(cc) unless cc.nil?
        trigger[:pc] = Integer(pc) unless pc.nil?
        raise ArgumentError, "midi_map requires note, cc or pc" if trigger.empty?

        @midi_mappings << {
          trigger: trigger,
          action: block
        }
      end

      def set(key, value)
        @global_params[key.to_sym] = value
      end

      def result
        {
          audio: @audio_inputs.map { |item| deep_dup(item) },
          midi: @midi_inputs.map { |item| deep_dup(item) },
          scenes: @scenes.map { |scene| deep_dup(scene) },
          transitions: @transitions.map { |transition| deep_dup(transition) },
          midi_maps: @midi_mappings.map { |mapping| deep_dup(mapping) },
          globals: deep_dup(@global_params)
        }
      end

      private

      def symbolize_keys(hash)
        hash.each_with_object({}) do |(key, value), output|
          output[key.to_sym] = value
        end
      end

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

      class TransitionBuilder
        def initialize
          @effect = nil
          @trigger = nil
        end

        def effect(name, **options)
          @effect = {
            name: name.to_sym,
            options: options.each_with_object({}) { |(key, value), output| output[key.to_sym] = value }
          }
        end

        def trigger(&block)
          @trigger = block
        end

        def to_h
          output = {}
          output[:effect] = @effect if @effect
          output[:trigger] = @trigger if @trigger
          output
        end
      end
    end
  end
end
