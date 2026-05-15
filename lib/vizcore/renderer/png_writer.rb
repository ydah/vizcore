# frozen_string_literal: true

require "zlib"

module Vizcore
  module Renderer
    # Minimal PNG encoder for RGBA pixel buffers.
    class PngWriter
      SIGNATURE = "\x89PNG\r\n\x1A\n".b
      COLOR_TYPE_RGBA = 6
      BIT_DEPTH = 8

      class << self
        # @param width [Integer]
        # @param height [Integer]
        # @param rgba [String] RGBA bytes, row-major
        # @return [String] PNG bytes
        def encode(width:, height:, rgba:)
          width = Integer(width)
          height = Integer(height)
          pixels = rgba.to_s.b
          expected_size = width * height * 4
          raise ArgumentError, "RGBA buffer must be #{expected_size} bytes" unless pixels.bytesize == expected_size

          SIGNATURE + chunk("IHDR", ihdr(width, height)) + chunk("IDAT", Zlib::Deflate.deflate(scanlines(width, height, pixels))) + chunk("IEND", "".b)
        end

        # @return [void]
        def write(path:, width:, height:, rgba:)
          File.binwrite(path, encode(width: width, height: height, rgba: rgba))
        end

        private

        def ihdr(width, height)
          [width, height, BIT_DEPTH, COLOR_TYPE_RGBA, 0, 0, 0].pack("NNCCCCC")
        end

        def scanlines(width, height, pixels)
          row_size = width * 4
          output = +""
          output.force_encoding(Encoding::BINARY)
          height.times do |row|
            output << "\x00".b
            output << pixels.byteslice(row * row_size, row_size)
          end
          output
        end

        def chunk(type, data)
          typed_data = type.b + data.b
          [data.bytesize].pack("N") + typed_data + [Zlib.crc32(typed_data)].pack("N")
        end
      end
    end
  end
end
