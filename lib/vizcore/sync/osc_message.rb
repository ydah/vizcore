# frozen_string_literal: true

module Vizcore
  module Sync
    # Minimal OSC 1.0 message parser for control sync.
    class OscMessage
      attr_reader :address, :arguments, :timetag

      # @param data [String]
      # @return [Vizcore::Sync::OscMessage, Array<Vizcore::Sync::OscMessage>, nil]
      def self.parse(data)
        parser = Parser.new(data)
        parser.parse_packet
      rescue StandardError
        nil
      end

      # @param address [String]
      # @param arguments [Array]
      # @param timetag [Float, nil]
      def initialize(address:, arguments: [], timetag: nil)
        @address = address
        @arguments = Array(arguments)
        @timetag = timetag
      end

      # @api private
      class Parser
        BUNDLE_SIGNATURE = "#bundle"
        NTP_TO_UNIX_OFFSET = 2_208_988_800

        # @param data [String]
        def initialize(data)
          @data = data.to_s.b
          @offset = 0
        end

        # @return [Vizcore::Sync::OscMessage, Array<Vizcore::Sync::OscMessage>, nil]
        def parse_packet(default_timetag: nil)
          signature_or_address = read_string
          return nil unless signature_or_address

          return parse_bundle if signature_or_address == BUNDLE_SIGNATURE
          parse_message(signature_or_address, timetag: default_timetag)
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

        def parse_bundle
          bundle_timetag = parse_timetag(read_uint64)
          messages = []

          until @offset >= @data.bytesize
            break if @offset + 4 > @data.bytesize
            message_size = read_int32
            break if message_size <= 0

            message_data = read_bytes(message_size)
            parsed = Parser.new(message_data).parse_packet(default_timetag: bundle_timetag)
            messages.concat(Array(parsed))
          end

          messages
        end

        def parse_message(address, timetag: nil)
          return nil unless address&.start_with?("/")

          tags = read_string
          arguments = read_arguments(tags)
          OscMessage.new(address: address, arguments: arguments, timetag: timetag)
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

        def read_uint64
          read_bytes(8).unpack1("Q>")
        end

        def read_bytes(length)
          raise ArgumentError, "OSC payload truncated" if @offset + length > @data.bytesize

          @data.byteslice(@offset, length).tap do
            @offset += length
          end
        end

        def parse_timetag(raw)
          return nil if raw == 0

          seconds = (raw >> 32) - NTP_TO_UNIX_OFFSET
          fraction = raw & 0xFFFF_FFFF
          seconds + (fraction / 4_294_967_296.0)
        end

        def align_offset
          @offset += 1 while (@offset % 4).positive?
        end
      end
    end
  end
end
