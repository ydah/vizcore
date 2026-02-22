# frozen_string_literal: true

require "json"
require "pathname"
require "rack"
require_relative "websocket_handler"

module Vizcore
  module Server
    # Rack app serving frontend assets, health endpoint, and WebSocket upgrade.
    class RackApp
      AUDIO_FILE_PATH = "/audio-file"
      RUNTIME_PATH = "/runtime"

      # @param frontend_root [Pathname]
      # @param websocket_path [String]
      # @param audio_source [Symbol, String, nil]
      # @param audio_file [String, Pathname, nil]
      def initialize(frontend_root:, websocket_path: "/ws", audio_source: nil, audio_file: nil)
        @frontend_root = frontend_root.expand_path
        @websocket_path = websocket_path
        @audio_source = audio_source&.to_sym
        @audio_file = audio_file ? Pathname.new(audio_file).expand_path : nil
      end

      # @param env [Hash]
      # @return [Array(Integer, Hash, Array<String>)]
      def call(env)
        request = Rack::Request.new(env)

        return WebSocketHandler.call(env) if request.path_info == @websocket_path
        return health_response if request.path_info == "/health"
        return runtime_response if request.path_info == RUNTIME_PATH
        return audio_file_response(request) if request.path_info == AUDIO_FILE_PATH

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
          audio_file_url: nil
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

      def serve_static(path_info)
        path = path_info == "/" ? "index.html" : path_info.delete_prefix("/")
        full_path = File.expand_path(path, @frontend_root.to_s)

        return not_found_response unless full_path.start_with?(@frontend_root.to_s)
        return not_found_response unless File.file?(full_path)

        body = File.binread(full_path)
        headers = {
          "content-type" => Rack::Mime.mime_type(File.extname(full_path), "text/plain"),
          "content-length" => body.bytesize.to_s,
          "cache-control" => "no-store, max-age=0, must-revalidate"
        }
        [200, headers, [body]]
      end

      def not_found_response
        [404, text_headers.merge("content-length" => "9"), ["Not Found"]]
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
