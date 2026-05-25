# frozen_string_literal: true

require "json"
require "pathname"
require "rack"
require_relative "../control_preset"
require_relative "../plugin_asset_policy"
require_relative "websocket_handler"

module Vizcore
  module Server
    # Rack app serving frontend assets, health endpoint, and WebSocket upgrade.
    class RackApp
      AUDIO_FILE_PATH = "/audio-file"
      CONTROL_PATH = "/control"
      CONTROL_PRESET_PATH = "/control-preset"
      PLUGIN_ASSET_PREFIX = "/plugins/"
      PROJECTOR_PATH = "/projector"
      RUNTIME_PATH = "/runtime"

      # @param frontend_root [Pathname]
      # @param websocket_path [String]
      # @param audio_source [Symbol, String, nil]
      # @param audio_file [String, Pathname, nil]
      # @param scene_names [Array<String, Symbol>, nil]
      # @param tap_tempo_key [String, Symbol, nil]
      # @param key_mappings [Array<Hash>, nil]
      # @param globals [Hash, nil]
      # @param control_preset [Hash, nil]
      # @param control_preset_path [String, Pathname, nil]
      # @param plugin_assets [Array<String, Pathname>, nil]
      # @param projector_mode [Boolean]
      # @param runtime_status_provider [#call, nil]
      def initialize(
        frontend_root:,
        websocket_path: "/ws",
        audio_source: nil,
        audio_file: nil,
        scene_names: nil,
        tap_tempo_key: nil,
        key_mappings: nil,
        globals: nil,
        control_preset: nil,
        control_preset_path: nil,
        plugin_assets: nil,
        projector_mode: false,
        runtime_status_provider: nil
      )
        @frontend_root = frontend_root.expand_path
        @websocket_path = websocket_path
        @audio_source = audio_source&.to_sym
        @audio_file = audio_file ? Pathname.new(audio_file).expand_path : nil
        @scene_names = normalize_scene_names(scene_names)
        @tap_tempo_key = normalize_tap_tempo_key(tap_tempo_key)
        @key_mappings = normalize_key_mappings(key_mappings)
        @globals = normalize_globals(globals)
        @control_preset = normalize_control_preset(control_preset)
        @control_preset_path = control_preset_path ? Pathname.new(control_preset_path).expand_path : nil
        @plugin_assets = normalize_plugin_assets(plugin_assets)
        @projector_mode = !!projector_mode
        @runtime_status_provider = runtime_status_provider
      end

      # @param env [Hash]
      # @return [Array(Integer, Hash, Array<String>)]
      def call(env)
        request = Rack::Request.new(env)

        return WebSocketHandler.call(env) if request.path_info == @websocket_path
        return health_response if request.path_info == "/health"
        return runtime_response if request.path_info == RUNTIME_PATH
        return control_preset_response(request) if request.path_info == CONTROL_PRESET_PATH
        return audio_file_response(request) if request.path_info == AUDIO_FILE_PATH
        return plugin_asset_response(request.path_info) if request.path_info.start_with?(PLUGIN_ASSET_PREFIX)
        return serve_index(display_mode: root_display_mode) if request.path_info == "/"
        return serve_index(display_mode: "control") if request.path_info == CONTROL_PATH
        return serve_index(display_mode: "projector") if request.path_info == PROJECTOR_PATH

        serve_static(request.path_info)
      end

      private

      def health_response
        body = JSON.generate(status: "ok", websocket_clients: WebSocketHandler.connection_count)
        [200, json_headers.merge("content-length" => body.bytesize.to_s), [body]]
      end

      def runtime_response
        payload = {
          status: "ok",
          audio_source: (@audio_source || :unknown).to_s,
          audio_file_name: nil,
          audio_file_url: nil,
          scene_names: @scene_names,
          tap_tempo_key: @tap_tempo_key,
          key_mappings: @key_mappings,
          globals: @globals,
          control_preset: @control_preset,
          control_preset_writable: !!@control_preset_path,
          control_preset_url: @control_preset_path ? CONTROL_PRESET_PATH : nil,
          plugin_assets: @plugin_assets.map { |asset| asset.fetch(:url) },
          projector_mode: @projector_mode,
          websocket_clients: WebSocketHandler.connection_count,
          dropped_frames: WebSocketHandler.dropped_frame_count,
          runtime: runtime_status
        }

        if audio_file_available?
          payload[:audio_file_name] = @audio_file.basename.to_s
          payload[:audio_file_url] = AUDIO_FILE_PATH
        end

        body = JSON.generate(payload)
        [200, json_headers.merge("content-length" => body.bytesize.to_s), [body]]
      end

      def audio_file_response(request)
        return not_found_response unless audio_file_available?

        file_size = @audio_file.size
        range = parse_byte_range(request.get_header("HTTP_RANGE"), file_size)
        return range_not_satisfiable_response(file_size) if range == :invalid

        if range
          byte_start, byte_end = range
          length = byte_end - byte_start + 1
          body = File.binread(@audio_file, length, byte_start)
          return [
            206,
            audio_headers(content_length: body.bytesize).merge("content-range" => "bytes #{byte_start}-#{byte_end}/#{file_size}"),
            [body]
          ]
        end

        body = File.binread(@audio_file)
        [200, audio_headers(content_length: body.bytesize), [body]]
      end

      def control_preset_response(request)
        return not_found_response unless @control_preset_path
        return method_not_allowed_response unless request.put? || request.post?

        payload = JSON.parse(request.body.read)
        @control_preset = Vizcore::ControlPreset.write(@control_preset_path, payload)
        body = JSON.generate(status: "ok", control_preset: @control_preset)
        [200, json_headers.merge("content-length" => body.bytesize.to_s), [body]]
      rescue JSON::ParserError => e
        body = JSON.generate(status: "error", error: "Invalid control preset JSON: #{e.message}")
        [400, json_headers.merge("content-length" => body.bytesize.to_s), [body]]
      rescue ArgumentError => e
        body = JSON.generate(status: "error", error: e.message)
        [400, json_headers.merge("content-length" => body.bytesize.to_s), [body]]
      end

      def serve_static(path_info)
        path = path_info.delete_prefix("/")
        full_path = File.expand_path(path, @frontend_root.to_s)

        return not_found_response unless full_path.start_with?(@frontend_root.to_s)
        return not_found_response unless File.file?(full_path)

        body = File.binread(full_path)
        static_response(body, content_type: Rack::Mime.mime_type(File.extname(full_path), "text/plain"))
      end

      def serve_index(display_mode:)
        full_path = @frontend_root.join("index.html")
        return not_found_response unless full_path.file?

        body = File.binread(full_path)
        body = body.gsub(
          'data-projector-mode="false"',
          "data-projector-mode=\"#{display_mode == 'projector' ? 'true' : 'false'}\""
        )
        body = body.gsub(
          'data-display-mode="auto"',
          "data-display-mode=\"#{display_mode}\""
        )
        body = inject_plugin_asset_scripts(body)
        static_response(body, content_type: "text/html")
      end

      def plugin_asset_response(path_info)
        asset = @plugin_assets.find { |entry| entry.fetch(:url) == path_info }
        return not_found_response unless asset
        return not_found_response unless asset.fetch(:path).file?

        body = File.binread(asset.fetch(:path))
        static_response(body, content_type: Rack::Mime.mime_type(asset.fetch(:path).extname, "text/javascript"))
      end

      def root_display_mode
        @projector_mode ? "projector" : "auto"
      end

      def runtime_status
        return {} unless @runtime_status_provider.respond_to?(:call)

        normalize_runtime_status(@runtime_status_provider.call)
      rescue StandardError => e
        { "last_error" => e.message }
      end

      def normalize_runtime_status(values)
        Hash(values || {}).each_with_object({}) do |(key, value), output|
          output[key.to_s] = normalize_runtime_status_value(value)
        end
      rescue StandardError
        {}
      end

      def normalize_runtime_status_value(value)
        case value
        when Hash
          normalize_runtime_status(value)
        when Array
          value.map { |entry| normalize_runtime_status_value(entry) }
        when Symbol
          value.to_s
        else
          value
        end
      end

      def static_response(body, content_type:)
        headers = {
          "content-type" => content_type,
          "content-length" => body.bytesize.to_s,
          "cache-control" => "no-store, max-age=0, must-revalidate"
        }
        [200, headers, [body]]
      end

      def not_found_response
        [404, text_headers.merge("content-length" => "9"), ["Not Found"]]
      end

      def method_not_allowed_response
        [405, text_headers.merge("allow" => "PUT, POST", "content-length" => "18"), ["Method Not Allowed"]]
      end

      def text_headers
        { "content-type" => "text/plain; charset=utf-8" }
      end

      def json_headers
        { "content-type" => "application/json; charset=utf-8" }
      end

      def audio_file_available?
        @audio_source == :file && @audio_file && @audio_file.file?
      end

      def audio_headers(content_length:)
        {
          "content-type" => Rack::Mime.mime_type(@audio_file.extname, "application/octet-stream"),
          "content-length" => content_length.to_s,
          "cache-control" => "no-store, max-age=0, must-revalidate",
          "accept-ranges" => "bytes"
        }
      end

      def normalize_scene_names(values)
        Array(values).filter_map do |entry|
          name = entry.to_s.strip
          next if name.empty?

          name
        end.uniq
      rescue StandardError
        []
      end

      def normalize_tap_tempo_key(value)
        key = value.to_s.strip.downcase
        return nil if key.empty?

        key
      rescue StandardError
        nil
      end

      def normalize_key_mappings(values)
        Array(values).filter_map do |entry|
          key = normalize_shortcut_key(entry[:key] || entry["key"])
          action = entry[:action] || entry["action"]
          next if key.empty? || !action.is_a?(Hash)

          normalized_action = normalize_key_action(action)
          next unless normalized_action

          { key: key, action: normalized_action }
        end
      rescue StandardError
        []
      end

      def normalize_shortcut_key(value)
        raw = value.to_s
        return "space" if raw == " "

        key = raw.strip.downcase
        key == "spacebar" ? "space" : key
      end

      def normalize_key_action(action)
        type = (action[:type] || action["type"]).to_s.strip
        case type
        when "switch_scene"
          scene = (action[:scene] || action["scene"]).to_s.strip
          return nil if scene.empty?

          { type: "switch_scene", scene: scene }
        when "live_control"
          control = (action[:control] || action["control"]).to_s.strip
          return nil unless %w[blackout freeze].include?(control)

          { type: "live_control", control: control }
        end
      end

      def normalize_globals(values)
        Hash(values || {}).each_with_object({}) do |(key, value), output|
          name = key.to_s.strip
          next if name.empty?

          output[name] = value
        end
      rescue StandardError
        {}
      end

      def normalize_control_preset(values)
        preset = values.is_a?(Hash) ? values : {}
        visual_settings = preset[:visual_settings] || preset["visual_settings"] || preset[:visualSettings] || preset["visualSettings"]
        midi_learn_bindings = preset[:midi_learn_bindings] || preset["midi_learn_bindings"] || preset[:midiLearnBindings] || preset["midiLearnBindings"]

        {}.tap do |payload|
          payload["visual_settings"] = visual_settings if visual_settings.is_a?(Hash)
          payload["midi_learn_bindings"] = midi_learn_bindings if midi_learn_bindings.is_a?(Hash)
        end
      rescue StandardError
        {}
      end

      def normalize_plugin_assets(values)
        Array(values).each_with_index.filter_map do |value, index|
          raw_value = value.to_s.strip
          next if raw_value.empty?

          raw_path = value.is_a?(Pathname) ? value.expand_path : Pathname.new(raw_value).expand_path
          path = Vizcore::PluginAssetPolicy.validate!(raw_path)
          {
            path: path,
            url: "#{PLUGIN_ASSET_PREFIX}#{index}/#{rack_escape_path(path.basename.to_s)}"
          }
        end
      rescue StandardError
        []
      end

      def inject_plugin_asset_scripts(body)
        return body if @plugin_assets.empty?

        scripts = @plugin_assets.map do |asset|
          %(<script type="module" src="#{asset.fetch(:url)}"></script>)
        end.join("\n  ")
        body.sub(%(<script type="module" src="/src/main.js?v=20260516d"></script>), "#{scripts}\n  \\0")
      end

      def rack_escape_path(value)
        Rack::Utils.escape_path(value)
      end

      def parse_byte_range(raw_range, file_size)
        range_value = raw_range.to_s.strip
        return nil if range_value.empty?
        return :invalid unless range_value.start_with?("bytes=")
        return :invalid if file_size <= 0

        match = /\Abytes=(\d*)-(\d*)\z/.match(range_value)
        return :invalid unless match

        start_part = match[1]
        end_part = match[2]

        if start_part.empty?
          return :invalid if end_part.empty?

          suffix_length = Integer(end_part)
          return :invalid unless suffix_length.positive?

          return [0, file_size - 1] if suffix_length >= file_size

          return [file_size - suffix_length, file_size - 1]
        end

        start_offset = Integer(start_part)
        return :invalid if start_offset.negative? || start_offset >= file_size

        if end_part.empty?
          return [start_offset, file_size - 1]
        end

        end_offset = Integer(end_part)
        return :invalid if end_offset < start_offset

        [start_offset, [end_offset, file_size - 1].min]
      rescue StandardError
        :invalid
      end

      def range_not_satisfiable_response(file_size)
        [416, text_headers.merge("content-range" => "bytes */#{file_size}", "content-length" => "0"), []]
      end
    end
  end
end
