# frozen_string_literal: true

require "vizcore/renderer/png_writer"

RSpec.describe Vizcore::Renderer::PngWriter do
  it "encodes RGBA pixels as a PNG" do
    rgba = [
      255, 0, 0, 255,
      0, 255, 0, 255,
      0, 0, 255, 255,
      255, 255, 255, 255
    ].pack("C*")

    png = described_class.encode(width: 2, height: 2, rgba: rgba)

    expect(png.byteslice(0, 8)).to eq(described_class::SIGNATURE)
    expect(png).to include("IHDR")
    expect(png).to include("IDAT")
    expect(png).to include("IEND")
  end
end
