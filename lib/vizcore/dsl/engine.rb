# frozen_string_literal: true

require "pathname"
require_relative "../deep_copy"
require_relative "file_watcher"
require_relative "scene_builder"
require_relative "style_builder"
require_relative "timeline_builder"

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
        @key_mappings = []
        @global_params = {}
        @mapping_presets = {}
        @analysis_settings = {}
        @section_tail = nil
        @timelines = []
        @styles = {}
        @themes = {}
        @scene_registry = {}
        @strict = false
        @seed = nil
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

      # Register reusable mapping behavior for layer-level targets.
      #
      # @param name [Symbol, String] mapping preset identifier
      # @yield Mapping preset block
      # @return [void]
      def mapping(name, &block)
        builder = MappingPresetBuilder.new(name: name, strict: @strict)
        preset_definition = builder.evaluate(&block).to_h
        @mapping_presets[preset_definition[:name]] = deep_dup(preset_definition[:mappings])
      end

      # Register a MIDI input definition.
      #
      # @param name [Symbol, String] input name
      # @param options [Hash] input options
      # @return [void]
      def midi(name, **options)
        @midi_inputs << { name: name.to_sym, options: symbolize_keys(options) }
      end

      # Enable strict DSL validation while the file is evaluated.
      #
      # @return [Boolean]
      def strict!
        @strict = true
      end

      # Set a deterministic Ruby random seed for offline rendering.
      #
      # @param value [Integer]
      # @return [Integer]
      def seed(value)
        @seed = Integer(value)
      rescue ArgumentError, TypeError
        raise ArgumentError, "seed must be an integer"
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

      # Configure analysis feature extraction behavior.
      #
      # @param options [Hash] optional onset/FFT/silence/peak-hold settings
      # @return [Hash] normalized analysis settings
      def audio_analysis(**options)
        settings = normalize_audio_analysis(options)
        @analysis_settings.merge!(settings)
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
        builder = SceneBuilder.new(name: name, styles: @styles, themes: @themes, mapping_presets: @mapping_presets, layers: inherited_layers(extends), strict: @strict)
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
      # @param loop [Boolean] whether the section should loop to itself
      # @param hold [Numeric] optional additional beats to wait before transitioning
      # @param outro [Boolean] whether to skip auto-transitioning to the next section
      # @yield Scene definition block
      # @return [void]
      def section(name, bars:, beats_per_bar: 4, loop: false, hold: 0, outro: false, &block)
        section_name = name.to_sym
        section_beats = positive_integer(bars, "section bars") * positive_integer(beats_per_bar, "beats_per_bar")
        normalized_hold = non_negative_float(hold, "section hold")
        is_loop = !!loop
        is_outro = !!outro
        if is_loop && is_outro
          raise ArgumentError, "section cannot be both loop and outro"
        end

        scene(section_name, &block)
        add_section_transition(to: section_name) if @section_tail
        @section_tail = {
          name: section_name,
          beats: section_beats,
          hold: normalized_hold,
          loop: is_loop,
          outro: is_outro
        }
      end

      # Define ordered scene markers and derive transitions between them.
      #
      # @param beats_per_bar [Integer] meter used by timeline `bars(...)` markers
      # @yield Timeline marker block
      # @return [void]
      def timeline(beats_per_bar: TimelineBuilder::DEFAULT_BEATS_PER_BAR, &block)
        raise ArgumentError, "timeline requires a block" unless block

        builder = TimelineBuilder.new(beats_per_bar: beats_per_bar, bpm: @analysis_settings[:bpm]).evaluate(&block)
        entries = builder.to_h
        @timelines << entries unless entries.empty?
        @transitions.concat(builder.transitions)
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
      # @param channel [Integer, nil] optional MIDI channel condition (1..16; 0 aliases channel 1)
      # @param relative [Boolean] true when CC values should be treated as relative encoder deltas
      # @param deadband [Numeric, nil] minimum CC value change required to emit an action
      # @param smooth [Numeric, Boolean, nil] optional CC smoothing alpha
      # @param pickup [Boolean, nil] when true, waits for CC to reach local pickup point before emitting updates
      # @yield Action block executed by midi runtime
      # @raise [ArgumentError] when no trigger is supplied
      # @return [void]
      def midi_map(note: nil, cc: nil, pc: nil, channel: nil, relative: false, deadband: nil, smooth: nil, pickup: nil, allow_multiple: false, &block)
        trigger = {}
        trigger[:note] = Integer(note) unless note.nil?
        trigger[:cc] = Integer(cc) unless cc.nil?
        trigger[:pc] = Integer(pc) unless pc.nil?
        raise ArgumentError, "midi_map requires note, cc or pc" if trigger.empty?
        trigger[:channel] = normalize_midi_channel(channel) unless channel.nil?
        trigger[:relative] = true if relative && trigger.key?(:cc)
        trigger[:deadband] = non_negative_float(deadband, "midi deadband") unless deadband.nil?
        trigger[:smooth] = normalize_midi_smooth(smooth) unless smooth.nil? || smooth == false
        trigger[:pickup] = pickup if trigger.key?(:cc) && trigger[:cc].between?(0, 127) && !!pickup
        trigger[:allow_multiple] = !!allow_multiple

        @midi_mappings << {
          trigger: trigger,
          action: block
        }
      end

      # Register a browser keyboard shortcut for runtime controls.
      #
      # @param value [Symbol, String] browser KeyboardEvent key value
      # @yield Action block (`switch_scene`, `blackout`, or `freeze`)
      # @raise [ArgumentError] when the key or action is missing
      # @return [void]
      def key(value, &block)
        binding_key = normalize_keyboard_key(value)
        builder = KeyBindingBuilder.new
        builder.instance_eval(&block) if block
        action = builder.to_h
        raise ArgumentError, "key #{binding_key.inspect} requires an action" if action.empty?

        @key_mappings << {
          key: binding_key,
          action: action
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
        append_pending_section_transition
        definition = {
          audio: @audio_inputs.map { |item| deep_dup(item) },
          midi: @midi_inputs.map { |item| deep_dup(item) },
          scenes: @scenes.map { |scene| deep_dup(scene) },
          transitions: @transitions.map { |transition| deep_dup(transition) },
          midi_maps: @midi_mappings.map { |mapping| deep_dup(mapping) },
          key_mappings: @key_mappings.map { |mapping| deep_dup(mapping) },
          mapping_presets: @mapping_presets.map { |name, mappings| { name: name, mappings: deep_dup(mappings) } },
          globals: deep_dup(@global_params),
          analysis: deep_dup(@analysis_settings),
          styles: @styles.map { |name, params| { name: name, params: deep_dup(params) } },
          themes: @themes.map { |name, params| { name: name, params: deep_dup(params) } }
        }
        definition[:strict] = true if @strict
        definition[:seed] = @seed unless @seed.nil?
        definition[:timelines] = @timelines.map { |timeline| deep_dup(timeline) } unless @timelines.empty?
        definition
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
        settings[:per_band] = !!options[:per_band] if options.key?(:per_band)
        settings
      end

      def normalize_audio_analysis(options)
        settings = {}
        settings[:onset_sensitivity] = positive_float(options[:onset_sensitivity], "onset_sensitivity") if options.key?(:onset_sensitivity)
        settings[:fft_bins] = ranged_integer(options[:fft_bins], "fft_bins", 8, 128) if options.key?(:fft_bins)
        peak_hold = options.key?(:peak_hold) ? options[:peak_hold] : options[:peak_hold_frames]
        settings[:peak_hold_frames] = ranged_integer(peak_hold, "peak_hold", 0, 10_000) unless peak_hold.nil?
        settings[:silence_reset_frames] = ranged_integer(options[:silence_reset_frames], "silence_reset_frames", 1, 10_000) if options.key?(:silence_reset_frames)
        settings
      end

      def positive_integer(value, name)
        numeric = Integer(value)
        raise ArgumentError, "#{name} must be positive" unless numeric.positive?

        numeric
      end

      def ranged_integer(value, name, min, max)
        numeric = Integer(value)
        raise ArgumentError, "#{name} must be between #{min} and #{max}" unless numeric.between?(min, max)

        numeric
      end

      def normalize_midi_channel(value)
        channel = Integer(value)
        return 0 if channel.zero?
        return channel - 1 if channel.between?(1, 16)

        raise ArgumentError, "midi channel must be between 1 and 16"
      end

      def non_negative_float(value, name)
        numeric = Float(value)
        raise ArgumentError, "#{name} must be non-negative" if numeric.negative?

        numeric
      end

      def normalize_midi_smooth(value)
        return 0.25 if value == true

        numeric = Float(value)
        raise ArgumentError, "midi smooth must be between 0.0 and 1.0" unless numeric.between?(0.0, 1.0)

        numeric
      rescue ArgumentError, TypeError
        raise ArgumentError, "midi smooth must be true or between 0.0 and 1.0"
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

      def normalize_keyboard_key(value)
        raw = value.to_s
        return "space" if raw == " "

        normalized = raw.strip.downcase
        normalized = "space" if normalized == "spacebar"
        raise ArgumentError, "key value must not be empty" if normalized.empty?

        normalized
      end

      def add_section_transition(to:)
        from = @section_tail.fetch(:name)
        beats = @section_tail.fetch(:beats)
        hold = @section_tail.fetch(:hold, 0.0)
        return if @section_tail.fetch(:loop, false)
        return if @section_tail.fetch(:outro, false)

        @transitions << {
          from: from,
          to: to,
          trigger: proc { beat_count >= (beats + hold) }
        }
      end

      def append_pending_section_transition
        return unless @section_tail && @section_tail.fetch(:loop, false)

        from = @section_tail.fetch(:name)
        beats = @section_tail.fetch(:beats, 0)
        hold = @section_tail.fetch(:hold, 0.0)
        @transitions << {
          from: from,
          to: from,
          trigger: proc { beat_count >= (beats + hold) }
        }
        @section_tail = @section_tail.merge(loop: false)
      end

      def inherited_layers(scene_name)
        return [] if scene_name.nil?

        normalized = scene_name.to_sym
        base_scene = @scene_registry[normalized]
        raise ArgumentError, "unknown base scene: #{normalized}" unless base_scene

        deep_dup(base_scene.fetch(:layers))
      end

      def deep_dup(value)
        Vizcore::DeepCopy.copy(value)
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

      # Builder object for `key` block internals.
      # @api private
      class KeyBindingBuilder
        def initialize
          @action = nil
        end

        # Switch to a named scene when the key is pressed.
        #
        # @param name [Symbol, String]
        # @return [void]
        def switch_scene(name, effect: nil)
          scene_name = name.to_s.strip
          raise ArgumentError, "switch_scene scene must not be empty" if scene_name.empty?

          action = { type: :switch_scene, scene: scene_name }
          action[:effect] = effect unless effect.nil?
          assign_action(action)
        end

        # Toggle browser blackout output.
        #
        # @return [void]
        def blackout(value = nil, fade: nil, release: nil, color: nil)
          live_control(:blackout, value, fade: fade, release: release, color: color)
        end

        # Toggle browser freeze output.
        #
        # @return [void]
        def freeze(value = nil, fade: nil, release: nil)
          live_control(:freeze, value, fade: fade, release: release)
        end

        # Toggle a browser live control.
        #
        # @param control [Symbol, String]
        # @param value [Object, nil] target value; nil means UI-side toggle for keyboard/live mapping
        # @return [void]
        def live_control(control, value = nil, fade: nil, release: nil, color: nil)
          normalized = control.to_s.strip.downcase.to_sym
          raise ArgumentError, "unsupported live control: #{control}" unless %i[blackout freeze].include?(normalized)

          assign_action(type: :live_control, control: normalized)

          # Preserve explicit value and transition timings when provided by DSL authors.
          # `nil` is kept for UI-side toggles to avoid changing existing keyboard ergonomics.
          action = @action
          action[:value] = value unless value.nil?
          action[:fade] = normalize_control_transition(fade)
          action[:release] = normalize_control_transition(release)
          action[:color] = normalize_control_color(color) unless color.nil?
          action.delete(:fade) if action[:fade].nil?
          action.delete(:release) if action[:release].nil?
          action.delete(:color) if action[:color].nil?
        end

        # @return [Hash] serialized key action
        def to_h
          @action || {}
        end

        private

        def assign_action(action)
          raise ArgumentError, "key mapping already has an action" if @action

          @action = action
        end

        def normalize_control_transition(value)
          return nil if value.nil?

          numeric = Float(value)
          return nil if numeric.negative? || !numeric.finite?

          numeric
        rescue ArgumentError, TypeError
          nil
        end

        def normalize_control_color(value)
          return nil if value.nil?

          if value.is_a?(Array)
            return nil unless (3..4).cover?(value.length)

            channels = Array(value).map { |entry| Float(entry, exception: false) }
            return nil if channels.include?(nil)

            rgb = channels.take(3)
            alpha = channels[3]
            normalized_rgb = if rgb.all? { |channel| channel.between?(0.0, 1.0) }
              rgb
            else
              rgb.map { |channel| channel / 255.0 }
            end
            normalized = normalized_rgb.map { |channel| [0.0, [1.0, channel].min].max }
            return alpha.nil? ? normalized : normalized + [normalize_control_alpha(alpha)]
          end

          raw = value.to_s.strip
          match = raw.match(/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/)
          return nil unless match

          raw_hex = match[1]
          hex = raw_hex.length == 3 || raw_hex.length == 4 ? raw_hex.chars.map { |char| "#{char}#{char}" }.join("") : raw_hex

          [
            Integer("0x#{hex[0, 2]}", 16),
            Integer("0x#{hex[2, 2]}", 16),
            Integer("0x#{hex[4, 2]}", 16),
            Integer("0x#{hex[6, 2]}", 16)
          ].take(raw_hex.length > 4 ? 4 : 3).map { |channel| [0.0, [1.0, channel / 255.0].min].max }
        rescue ArgumentError, TypeError
          nil
        end

        def normalize_control_alpha(value)
          return nil if value.nil?

          alpha = Float(value, exception: false)
          return nil if alpha.nil?
          return [0.0, [1.0, alpha].min].max if alpha.between?(0.0, 1.0)

          [0.0, [1.0, alpha / 255.0].min].max
        end
      end
    end
  end
end
