# frozen_string_literal: true

require "pathname"
require_relative "file_watcher"
require_relative "scene_builder"
require_relative "style_builder"

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
        @analysis_settings = {}
        @section_tail = nil
        @styles = {}
        @themes = {}
        @scene_registry = {}
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

      # Register a reusable layer parameter style.
      #
      # @param name [Symbol, String] style identifier
      # @yield Style parameter block
      # @return [void]
      def style(name, &block)
        builder = StyleBuilder.new(name: name)
        style_definition = builder.evaluate(&block).to_h
        @styles[style_definition[:name]] = deep_dup(style_definition[:params])
      end

      # Register a reusable scene-wide layer parameter theme.
      #
      # @param name [Symbol, String] theme identifier
      # @yield Theme parameter block
      # @return [void]
      def theme(name, &block)
        builder = StyleBuilder.new(name: name, kind: "theme")
        theme_definition = builder.evaluate(&block).to_h
        @themes[theme_definition[:name]] = deep_dup(theme_definition[:params])
      end

      # Register a MIDI input definition.
      #
      # @param name [Symbol, String] input name
      # @param options [Hash] input options
      # @return [void]
      def midi(name, **options)
        @midi_inputs << { name: name.to_sym, options: symbolize_keys(options) }
      end

      # Configure analysis-level audio feature normalization.
      #
      # @param mode [Symbol, String] `:off` or `:adaptive`
      # @param options [Hash] optional `window`, `target`, and `floor` values
      # @return [Hash] normalized audio normalization settings
      def audio_normalize(mode: :adaptive, **options)
        settings = normalize_audio_normalize(mode: mode, **options)
        @analysis_settings[:audio_normalize] = settings
      end

      # Set a fixed BPM value for analysis output.
      #
      # @param value [Numeric]
      # @return [Float]
      def bpm(value)
        @analysis_settings[:bpm] = positive_float(value, "bpm")
      end

      # Enable or disable fixed BPM output.
      #
      # @param value [Boolean]
      # @return [Boolean]
      def bpm_lock(value = true)
        @analysis_settings[:bpm_lock] = !!value
      end

      # Enable browser keyboard tap tempo.
      #
      # @param key [Symbol, String] key that should send tap tempo events
      # @return [Hash]
      def tap_tempo(key: :t)
        normalized_key = key.to_s.strip.downcase
        raise ArgumentError, "tap_tempo key must not be empty" if normalized_key.empty?

        @analysis_settings[:tap_tempo] = { key: normalized_key }
      end

      # Define a scene and its layers.
      #
      # @param name [Symbol, String] scene identifier
      # @param extends [Symbol, String, nil] optional base scene to copy layers from
      # @yield Scene definition block
      # @return [void]
      def scene(name, extends: nil, &block)
        builder = SceneBuilder.new(name: name, styles: @styles, themes: @themes, layers: inherited_layers(extends))
        builder.evaluate(&block)
        scene_definition = builder.to_h
        @scenes << scene_definition
        @scene_registry[scene_definition[:name]] = deep_dup(scene_definition)
      end

      # Define a beat-counted song section as a scene and auto-transition to the
      # following section.
      #
      # @param name [Symbol, String] scene/section identifier
      # @param bars [Integer] section duration in bars
      # @param beats_per_bar [Integer] meter used to convert bars into beats
      # @yield Scene definition block
      # @return [void]
      def section(name, bars:, beats_per_bar: 4, &block)
        section_name = name.to_sym
        section_beats = positive_integer(bars, "section bars") * positive_integer(beats_per_bar, "beats_per_bar")

        scene(section_name, &block)
        add_section_transition(to: section_name) if @section_tail
        @section_tail = { name: section_name, beats: section_beats }
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
          globals: deep_dup(@global_params),
          analysis: deep_dup(@analysis_settings),
          styles: @styles.map { |name, params| { name: name, params: deep_dup(params) } },
          themes: @themes.map { |name, params| { name: name, params: deep_dup(params) } }
        }
      end

      private

      def symbolize_keys(hash)
        hash.each_with_object({}) do |(key, value), output|
          output[key.to_sym] = value
        end
      end

      def normalize_audio_normalize(mode:, **options)
        normalized_mode = mode.to_s.strip.to_sym
        raise ArgumentError, "unsupported audio_normalize mode: #{mode}" unless %i[off adaptive].include?(normalized_mode)

        settings = { mode: normalized_mode }
        settings[:window] = positive_float(options[:window], "audio_normalize window") if options.key?(:window)
        settings[:target] = unit_float(options[:target], "audio_normalize target") if options.key?(:target)
        settings[:floor] = unit_float(options[:floor], "audio_normalize floor") if options.key?(:floor)
        settings
      end

      def positive_integer(value, name)
        numeric = Integer(value)
        raise ArgumentError, "#{name} must be positive" unless numeric.positive?

        numeric
      end

      def positive_float(value, name)
        numeric = Float(value)
        raise ArgumentError, "#{name} must be positive" unless numeric.positive?

        numeric
      end

      def unit_float(value, name)
        numeric = Float(value)
        raise ArgumentError, "#{name} must be between 0.0 and 1.0" unless numeric.between?(0.0, 1.0)

        numeric
      end

      def add_section_transition(to:)
        from = @section_tail.fetch(:name)
        beats = @section_tail.fetch(:beats)
        @transitions << {
          from: from,
          to: to,
          trigger: proc { beat_count >= beats }
        }
      end

      def inherited_layers(scene_name)
        return [] if scene_name.nil?

        normalized = scene_name.to_sym
        base_scene = @scene_registry[normalized]
        raise ArgumentError, "unknown base scene: #{normalized}" unless base_scene

        deep_dup(base_scene.fetch(:layers))
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

        # Trigger after a scene-local beat count reaches the given value.
        #
        # @param count [Integer]
        # @return [void]
        def on_beat(count)
          beat_target = Integer(count)
          raise ArgumentError, "on_beat count must be positive" unless beat_target.positive?

          @trigger = proc { beat_count >= beat_target }
        end

        # Trigger after a scene-local bar count reaches the given value.
        #
        # @param count [Integer]
        # @param beats_per_bar [Integer]
        # @return [void]
        def on_bar(count, beats_per_bar: 4)
          bar_target = Integer(count)
          beats = Integer(beats_per_bar)
          raise ArgumentError, "on_bar count must be positive" unless bar_target.positive?
          raise ArgumentError, "beats_per_bar must be positive" unless beats.positive?

          on_beat(bar_target * beats)
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
