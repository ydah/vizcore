# frozen_string_literal: true

require "json"
require "set"
require "thread"

module Vizcore
  module Server
    class WebSocketHandler
      class << self
        def call(env)
          websocket_klass = faye_websocket_class
          return dependency_error_response unless websocket_klass
          return [426, text_headers, ["WebSocket upgrade required"]] unless websocket_klass.websocket?(env)

          socket = websocket_klass.new(env, nil, ping: 15)

          socket.on(:open) { register(socket) }
          socket.on(:close) { unregister(socket) }
          socket.on(:message) { |event| handle_message(socket, event.data) }

          socket.rack_response
        end

        def broadcast(type:, payload:)
          return false unless faye_websocket_class

          message = JSON.generate(type: type, payload: payload)

          each_socket do |socket|
            send_message(socket, message)
          end

          true
        end

        def connection_count
          mutex.synchronize { sockets.size }
        end

        private

        def faye_websocket_class
          require "faye/websocket"
          Faye::WebSocket
        rescue LoadError
          nil
        end

        def send_message(socket, message)
          if event_machine_reactor_running?
            EventMachine.schedule { safe_send(socket, message) }
          else
            safe_send(socket, message)
          end
        end

        def safe_send(socket, message)
          socket.send(message)
        rescue StandardError
          unregister(socket)
        end

        def event_machine_reactor_running?
          require "eventmachine"
          EventMachine.reactor_running?
        rescue LoadError
          false
        end

        def dependency_error_response
          [500, json_headers, [JSON.generate(error: "Missing dependency: faye-websocket")]]
        end

        def handle_message(_socket, raw_message)
          JSON.parse(raw_message)
        rescue JSON::ParserError
          nil
        end

        def register(socket)
          mutex.synchronize { sockets << socket }
        end

        def unregister(socket)
          mutex.synchronize { sockets.delete(socket) }
        end

        def each_socket(&block)
          snapshot = mutex.synchronize { sockets.dup }
          snapshot.each(&block)
        end

        def sockets
          @sockets ||= Set.new
        end

        def mutex
          @mutex ||= Mutex.new
        end

        def text_headers
          { "content-type" => "text/plain; charset=utf-8" }
        end

        def json_headers
          { "content-type" => "application/json; charset=utf-8" }
        end
      end
    end
  end
end
