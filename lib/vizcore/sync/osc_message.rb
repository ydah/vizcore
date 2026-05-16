# frozen_string_literal: true

module Vizcore
  module Sync
    # Minimal OSC 1.0 message parser for control sync.
    class OscMessage
      attr_reader :address, :arguments

      # @param data [String]
      # @return [Vizcore::Sync::OscMessage, nil]
      def self.parse(data)
        parser = Parser.new(data)
        address = parser.read_string
        return nil unless address&.start_with?("/")

        tags = parser.read_string
        arguments = parser.read_arguments(tags)
        new(address: address, arguments: arguments)
      rescue StandardError
        nil
      end

      # @param address [String]
      # @param arguments [Array]
      def initialize(address:, arguments: [])
        @address = address
        @arguments = Array(arguments)
      end

      # @api private
      class Parser
        # @param data [String]
        def initialize(data)
          @data = data.to_s.b
          @offset = 0
        end

        # @return [String, nil]
        def read_string
          start = @offset
          @offset += 1 while @offset < @data.bytesize && @data.getbyte(@offset) != 0
          return nil if @offset >= @data.bytesize

          value = @data.byteslice(start...@offset).to_s.force_encoding(Encoding::UTF_8)
          @offset += 1
          align_offset
          value
        end

        # @param tags [String, nil]
        # @return [Array]
        def read_arguments(tags)
          return [] if tags.to_s.empty?
          return [] unless tags.start_with?(",")

          tags[1..].to_s.each_char.map do |tag|
            read_argument(tag)
          end
        end

        private

        def read_argument(tag)
          case tag
          when "i"
            read_int32
          when "f"
            read_float32
          when "s"
            read_string
          when "T"
            true
          when "F"
            false
          else
            nil
          end
        end

        def read_int32
          value = read_bytes(4).unpack1("N")
          value >= 0x80000000 ? value - 0x100000000 : value
        end

        def read_float32
          read_bytes(4).unpack1("g")
        end

        def read_bytes(length)
          raise ArgumentError, "OSC payload truncated" if @offset + length > @data.bytesize

          @data.byteslice(@offset, length).tap do
            @offset += length
          end
        end

        def align_offset
          @offset += 1 while (@offset % 4).positive?
        end
      end
    end
  end
end
