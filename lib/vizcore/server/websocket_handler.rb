# frozen_string_literal: true

require "json"
require "set"
require "thread"
require_relative "../errors"

module Vizcore
  module Server
    # Stateless WebSocket endpoint manager for frame broadcast transport.
    class WebSocketHandler
      PROTOCOL_VERSION = "vizcore.frame.v1"
      MAX_BUFFERED_FRAME_BYTES = 1_000_000
      DROPPABLE_MESSAGE_TYPES = Set["audio_frame"].freeze

      class << self
        # Rack endpoint for WebSocket upgrade handling.
        #
        # @param env [Hash]
        # @return [Array]
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

        # Broadcast one typed payload to all active websocket clients.
        #
        # @param type [String]
        # @param payload [Hash]
        # @return [Boolean] false when websocket backend is unavailable
        def broadcast(type:, payload:)
          return false unless faye_websocket_class

          message = JSON.generate(protocol: PROTOCOL_VERSION, type: type, payload: payload)

          each_socket do |socket|
            send_message(socket, message, type: type)
          end

          true
        end

        # Send one typed payload to a single websocket client.
        #
        # @param socket [#send]
        # @param type [String]
        # @param payload [Hash]
        # @return [Boolean] false when websocket backend is unavailable
        def send_to(socket, type:, payload:)
          return false unless faye_websocket_class

          message = JSON.generate(protocol: PROTOCOL_VERSION, type: type, payload: payload)
          send_message(socket, message, type: type)
          true
        end

        # @return [Integer]
        def connection_count
          mutex.synchronize { sockets.size }
        end

        # @return [StandardError, nil]
        def last_error
          mutex.synchronize { @last_error }
        end

        # @return [Integer]
        def dropped_frame_count
          mutex.synchronize { @dropped_frame_count || 0 }
        end

        # @return [Hash] current websocket backpressure metrics for control/status surfaces.
        def backpressure_status
          mutex.synchronize do
            clients = sockets.map { |socket| backpressure_client_status(socket) }
            {
              threshold_bytes: MAX_BUFFERED_FRAME_BYTES,
              active_clients: sockets.size,
              total: {
                dropped_frames: socket_backpressure_totals[:dropped_frames],
                dropped_payload_bytes: socket_backpressure_totals[:dropped_payload_bytes],
                sent_frames: socket_backpressure_totals[:sent_frames],
                sent_payload_bytes: socket_backpressure_totals[:sent_payload_bytes],
                avg_payload_bytes: average(
                  socket_backpressure_totals[:sent_payload_bytes],
                  socket_backpressure_totals[:sent_frames]
                )
              },
              clients: clients
            }
          end
        end

        # Register one inbound message handler for client -> server control messages.
        #
        # @yieldparam message [Hash]
        # @return [void]
        def on_message(&block)
          mutex.synchronize { @message_handler = block }
        end

        # Clear inbound message handler.
        #
        # @return [void]
        def clear_message_handler
          mutex.synchronize { @message_handler = nil }
        end

        private

        def faye_websocket_class
          require "faye/websocket"
          Faye::WebSocket
        rescue LoadError
          nil
        end

        def send_message(socket, message, type:)
          message_bytes = message.bytesize
          return if drop_for_backpressure?(socket, type, payload_bytes: message_bytes)

          if event_machine_reactor_running?
            EventMachine.schedule { safe_send(socket, message, type: type, payload_bytes: message_bytes) }
          else
            safe_send(socket, message, type: type, payload_bytes: message_bytes)
          end
        end

        def safe_send(socket, message, type:, payload_bytes:)
          return if drop_for_backpressure?(socket, type, payload_bytes: payload_bytes)

          socket.send(message)
          record_message_sent(socket, payload_bytes)
        rescue StandardError => e
          set_last_error(e)
          unregister(socket)
        end

        def drop_for_backpressure?(socket, type, payload_bytes: nil)
          return false unless DROPPABLE_MESSAGE_TYPES.include?(type.to_s)

          buffered_amount = socket_buffered_amount(socket)
          begin
            buffered_amount = Integer(buffered_amount) if buffered_amount
          rescue ArgumentError, TypeError
            buffered_amount = nil
          end

          if buffered_amount && buffered_amount > MAX_BUFFERED_FRAME_BYTES
            mutex.synchronize do
              refresh_socket_backpressure_metrics(socket, buffered_amount: buffered_amount)
              increment_dropped_frame_count
              increment_client_drop(socket, payload_bytes: payload_bytes)
            end
            return true
          end

          if buffered_amount
            mutex.synchronize { refresh_socket_backpressure_metrics(socket, buffered_amount: buffered_amount) }
          end

          false
        end

        def socket_buffered_amount(socket)
          return socket.buffered_amount if socket.respond_to?(:buffered_amount)
          return socket.bufferedAmount if socket.respond_to?(:bufferedAmount)

          nil
        rescue StandardError
          nil
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

        def handle_message(socket, raw_message)
          message = JSON.parse(raw_message)
          dispatch_message(message, socket)
          message
        rescue JSON::ParserError => e
          set_last_error(e)
          nil
        end

        def register(socket)
          mutex.synchronize do
            sockets << socket
            socket_backpressure_metrics[socket_id(socket)] = default_backpressure_metrics
          end
        end

        def unregister(socket)
          mutex.synchronize do
            sockets.delete(socket)
            socket_backpressure_metrics.delete(socket_id(socket))
          end
        end

        def each_socket(&block)
          snapshot = mutex.synchronize { sockets.dup }
          snapshot.each(&block)
        end

        def sockets
          @sockets ||= Set.new
        end

        def socket_backpressure_metrics
          @socket_backpressure_metrics ||= {}
        end

        def socket_backpressure_totals
          @socket_backpressure_totals ||= {
            dropped_frames: 0,
            dropped_payload_bytes: 0,
            sent_frames: 0,
            sent_payload_bytes: 0
          }
        end

        def backpressure_client_status(socket)
          metrics = client_backpressure_metrics(socket)
          {
            id: socket_id(socket).to_s,
            buffered_amount: metrics[:buffered_amount],
            peak_buffered_amount: metrics[:peak_buffered_amount],
            dropped_frames: metrics[:dropped_frames],
            dropped_payload_bytes: metrics[:dropped_payload_bytes],
            sent_frames: metrics[:sent_frames],
            sent_payload_bytes: metrics[:sent_payload_bytes],
            avg_payload_bytes: average(metrics[:sent_payload_bytes], metrics[:sent_frames]),
            estimated_lag_frames: estimated_lag_frames(
              metrics[:buffered_amount],
              metrics[:sent_payload_bytes],
              metrics[:sent_frames]
            ),
            last_payload_bytes: metrics[:last_payload_bytes]
          }
        end

        def socket_id(socket)
          socket.object_id
        end

        def client_backpressure_metrics(socket)
          socket_backpressure_metrics.fetch(socket_id(socket)) do
            socket_backpressure_metrics[socket_id(socket)] = default_backpressure_metrics
          end
        end

        def refresh_socket_backpressure_metrics(socket, buffered_amount: nil)
          metrics = client_backpressure_metrics(socket)
          amount = buffered_amount.nil? ? socket_buffered_amount(socket) : buffered_amount
          return metrics unless amount

          integer_amount = amount.to_i
          metrics[:buffered_amount] = integer_amount
          metrics[:peak_buffered_amount] = [metrics[:peak_buffered_amount], integer_amount].max
          metrics
        end

        def increment_client_drop(socket, payload_bytes: nil)
          payload_bytes = Integer(payload_bytes || 0)
          metrics = client_backpressure_metrics(socket)
          metrics[:dropped_frames] += 1
          metrics[:dropped_payload_bytes] += payload_bytes
          socket_backpressure_totals[:dropped_frames] += 1
          socket_backpressure_totals[:dropped_payload_bytes] += payload_bytes
        end

        def record_message_sent(socket, payload_bytes)
          payload_bytes = Integer(payload_bytes || 0)
          buffered_amount = socket_buffered_amount(socket)
          buffered_amount = Integer(buffered_amount) if buffered_amount

          mutex.synchronize do
            metrics = client_backpressure_metrics(socket)
            metrics[:sent_frames] += 1
            metrics[:sent_payload_bytes] += payload_bytes
            metrics[:last_payload_bytes] = payload_bytes
            socket_backpressure_totals[:sent_frames] += 1
            socket_backpressure_totals[:sent_payload_bytes] += payload_bytes
            refresh_socket_backpressure_metrics(socket, buffered_amount: buffered_amount) if buffered_amount
          end
        end

        def average(numerator, denominator)
          return 0.0 if denominator.to_i <= 0

          numerator.to_f / denominator.to_f
        end

        def estimated_lag_frames(buffered_amount, payload_bytes, sent_frames)
          avg_payload_bytes = average(payload_bytes, sent_frames)
          return 0.0 if avg_payload_bytes <= 0.0

          buffered_amount.to_f / avg_payload_bytes
        end

        def default_backpressure_metrics
          {
            buffered_amount: 0,
            peak_buffered_amount: 0,
            dropped_frames: 0,
            dropped_payload_bytes: 0,
            sent_frames: 0,
            sent_payload_bytes: 0,
            last_payload_bytes: 0
          }
        end

        def mutex
          @mutex ||= Mutex.new
        end

        def set_last_error(error)
          mutex.synchronize { @last_error = error }
        end

        def increment_dropped_frame_count
          @dropped_frame_count = (@dropped_frame_count || 0) + 1
        end

        def dispatch_message(message, socket)
          handler = mutex.synchronize { @message_handler }
          return unless handler
          return unless message.is_a?(Hash)

          handler.call(message, socket)
        rescue StandardError => e
          set_last_error(e)
          nil
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
