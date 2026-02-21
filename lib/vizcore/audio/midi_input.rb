# frozen_string_literal: true

require "thread"
require_relative "../errors"

module Vizcore
  module Audio
    class MidiInput
      Event = Struct.new(:type, :channel, :data1, :data2, :raw, :timestamp, keyword_init: true)
      DEFAULT_POLL_INTERVAL = 0.01

      class << self
        def available_devices(backend: nil)
          midi_backend = backend || load_backend
          return [] unless midi_backend

          midi_backend::Input.all.each_with_index.map do |device, index|
            {
              id: extract_device_id(device, index),
              name: extract_device_name(device)
            }
          end
        rescue StandardError
          []
        end

        private

        def load_backend
          require "unimidi"
          UniMIDI
        rescue LoadError
          nil
        end

        def extract_device_id(device, fallback)
          return device.device_id if device.respond_to?(:device_id)
          fallback
        end

        def extract_device_name(device)
          return device.name if device.respond_to?(:name) && device.name
          "unknown-midi-device"
        end
      end

      def initialize(device: nil, backend: nil, poll_interval: DEFAULT_POLL_INTERVAL)
        @device = device
        @backend = backend || self.class.send(:load_backend)
        @poll_interval = Float(poll_interval)
        @running = false
        @thread = nil
        @input = nil
        @events = Queue.new
        @callback = nil
        @last_error = nil
      end

      attr_reader :last_error

      def start(&callback)
        return self if running?

        @callback = callback if block_given?
        @input = open_input
        return self unless @input

        @running = true
        @thread = Thread.new { consume_loop }
        self
      end

      def stop
        @running = false
        join_thread
        close_input
        self
      end

      def running?
        @running
      end

      def poll(max = nil)
        limit = max ? Integer(max) : nil
        result = []

        while limit.nil? || result.length < limit
          begin
            result << @events.pop(true)
          rescue ThreadError
            break
          end
        end

        result
      end

      private

      def open_input
        return nil unless @backend

        devices = @backend::Input.all
        return nil if devices.empty?

        device = select_device(devices)
        unless device
          @last_error = AudioSourceError.new("MIDI device not found: #{@device}")
          return nil
        end

        device.respond_to?(:open) ? device.open : device
      rescue StandardError => e
        @last_error = AudioSourceError.new("MIDI open failed: #{e.message}")
        nil
      end

      def select_device(devices)
        return devices.first if @device.nil? || @device == :default || @device == :first
        return devices[@device] if @device.is_a?(Integer)

        needle = @device.to_s.downcase
        devices.find do |device|
          name = device.respond_to?(:name) ? device.name.to_s.downcase : ""
          id = device.respond_to?(:device_id) ? device.device_id.to_s.downcase : ""
          name == needle || id == needle
        end
      end

      def consume_loop
        while @running
          raw_message = read_message
          unless raw_message
            sleep(@poll_interval)
            next
          end

          event = parse_message(raw_message)
          next unless event

          @events << event
          @callback&.call(event)
        end
      rescue StandardError => e
        @last_error = AudioSourceError.new("MIDI consume loop failed: #{e.message}")
        @running = false
      end

      def read_message
        return nil unless @input
        return @input.gets if @input.respond_to?(:gets)
        return @input.read if @input.respond_to?(:read)

        nil
      rescue StandardError => e
        @last_error = AudioSourceError.new("MIDI read failed: #{e.message}")
        nil
      end

      def parse_message(raw_message)
        bytes = normalize_message(raw_message)
        return nil if bytes.empty?

        status = bytes[0]
        command = status & 0xF0
        channel = status & 0x0F
        data1 = bytes[1] || 0
        data2 = bytes[2] || 0

        Event.new(
          type: detect_event_type(command, data2),
          channel: channel,
          data1: data1,
          data2: data2,
          raw: bytes,
          timestamp: Time.now.to_f
        )
      end

      def normalize_message(raw_message)
        values =
          if raw_message.respond_to?(:data)
            Array(raw_message.data)
          else
            Array(raw_message)
          end

        values.map { |value| Integer(value) & 0xFF }
      rescue StandardError => e
        @last_error = AudioSourceError.new("MIDI message parse failed: #{e.message}")
        []
      end

      def detect_event_type(command, data2)
        case command
        when 0x80
          :note_off
        when 0x90
          data2.zero? ? :note_off : :note_on
        when 0xB0
          :control_change
        when 0xC0
          :program_change
        else
          :unknown
        end
      end

      def join_thread
        thread = @thread
        @thread = nil
        return unless thread

        thread.join(0.3)
        thread.kill if thread.alive?
      end

      def close_input
        input = @input
        @input = nil
        return unless input
        return unless input.respond_to?(:close)

        input.close
      rescue StandardError => e
        @last_error = AudioSourceError.new("MIDI close failed: #{e.message}")
        nil
      end
    end
  end
end
