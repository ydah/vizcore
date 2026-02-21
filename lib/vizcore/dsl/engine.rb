# frozen_string_literal: true

require "pathname"
require_relative "file_watcher"
require_relative "scene_builder"

module Vizcore
  module DSL
    # Evaluates and stores scene definitions built with the Vizcore Ruby DSL.
    class Engine
      # Thread-local key used when evaluating scene files.
      THREAD_KEY = :vizcore_current_dsl_engine

      class << self
        # Evaluate a DSL block using the current thread-local engine, or a new engine.
        #
        # @yield Scene/audio/midi DSL configuration block
        # @return [Hash] serialized DSL definition
        def define(&block)
          engine = current || new
          engine.evaluate(&block)
        end

        # Load and evaluate a scene file.
        #
        # @param path [String, Pathname] scene file path
        # @raise [ArgumentError] when the scene file does not exist
        # @return [Hash] serialized DSL definition
        def load_file(path)
          scene_path = Pathname.new(path.to_s).expand_path
          raise ArgumentError, "Scene file not found: #{scene_path}" unless scene_path.file?

          engine = new
          with_current(engine) { Kernel.load(scene_path.to_s) }
          engine.result
        end

        # Build a file watcher that reloads and yields definitions on change.
        #
        # @param path [String, Pathname] scene file path to watch
        # @param poll_interval [Float] watcher poll interval in seconds
        # @param listener_factory [#call, nil] optional listener factory for tests
        # @yieldparam definition [Hash] reloaded DSL definition
        # @yieldparam changed_path [Pathname] path reported by the watcher
        # @return [Vizcore::DSL::FileWatcher]
        def watch_file(path, poll_interval: FileWatcher::DEFAULT_POLL_INTERVAL, listener_factory: nil, &on_change)
          FileWatcher.new(path: path, poll_interval: poll_interval, listener_factory: listener_factory) do |changed_path|
            definition = load_file(changed_path.to_s)
            on_change&.call(definition, changed_path)
          end
        end

        # @return [Vizcore::DSL::Engine, nil] current thread-local DSL engine.
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

      # Evaluate DSL methods on this engine instance.
      #
      # @yield DSL configuration block
      # @return [Hash] serialized DSL definition
      def evaluate(&block)
        instance_eval(&block) if block
        result
      end

      # Register an audio input definition.
      #
      # @param name [Symbol, String] input name
      # @param options [Hash] input options
      # @return [void]
      def audio(name, **options)
        @audio_inputs << { name: name.to_sym, options: symbolize_keys(options) }
      end

      # Register a MIDI input definition.
      #
      # @param name [Symbol, String] input name
      # @param options [Hash] input options
      # @return [void]
      def midi(name, **options)
        @midi_inputs << { name: name.to_sym, options: symbolize_keys(options) }
      end

      # Define a scene and its layers.
      #
      # @param name [Symbol, String] scene identifier
      # @yield Scene definition block
      # @return [void]
      def scene(name, &block)
        builder = SceneBuilder.new(name: name)
        builder.evaluate(&block)
        @scenes << builder.to_h
      end

      # Define a transition between scenes.
      #
      # @param from [Symbol, String] source scene name
      # @param to [Symbol, String] target scene name
      # @yield Optional transition block (`effect`, `trigger`)
      # @return [void]
      def transition(from:, to:, &block)
        definition = {
          from: from.to_sym,
          to: to.to_sym
        }
        builder = TransitionBuilder.new
        builder.instance_eval(&block) if block
        @transitions << definition.merge(builder.to_h)
      end

      # Register a MIDI trigger/action mapping.
      #
      # @param note [Integer, nil] note number trigger
      # @param cc [Integer, nil] control-change trigger
      # @param pc [Integer, nil] program-change trigger
      # @yield Action block executed by midi runtime
      # @raise [ArgumentError] when no trigger is supplied
      # @return [void]
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

      # Set a mutable global value shared with scene/runtime logic.
      #
      # @param key [Symbol, String] global key
      # @param value [Object] global value
      # @return [Object] assigned value
      def set(key, value)
        @global_params[key.to_sym] = value
      end

      # @return [Hash] deep-copied definition payload for renderer/runtime.
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

      # Builder object for `transition` block internals.
      # @api private
      class TransitionBuilder
        def initialize
          @effect = nil
          @trigger = nil
        end

        # @param name [Symbol, String] transition effect name
        # @param options [Hash] effect options
        # @return [void]
        def effect(name, **options)
          @effect = {
            name: name.to_sym,
            options: options.each_with_object({}) { |(key, value), output| output[key.to_sym] = value }
          }
        end

        # @yield Trigger predicate executed in transition context
        # @return [void]
        def trigger(&block)
          @trigger = block
        end

        # @return [Hash] serialized transition extras
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
