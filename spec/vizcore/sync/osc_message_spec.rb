# frozen_string_literal: true

require "vizcore/sync/osc_message"

RSpec.describe Vizcore::Sync::OscMessage do
  it "parses OSC strings, integers, floats, and booleans" do
    payload = osc_string("/vizcore/scene") +
              osc_string(",sifTF") +
              osc_string("drop") +
              [42].pack("N") +
              [0.5].pack("g")

    message = described_class.parse(payload)

    expect(message.address).to eq("/vizcore/scene")
    expect(message.arguments[0]).to eq("drop")
    expect(message.arguments[1]).to eq(42)
    expect(message.arguments[2]).to be_within(0.0001).of(0.5)
    expect(message.arguments[3]).to eq(true)
    expect(message.arguments[4]).to eq(false)
  end

  it "returns nil for invalid OSC packets" do
    expect(described_class.parse("not osc")).to be_nil
  end

  def osc_string(value)
    bytes = value.to_s.b + "\0"
    bytes << "\0" while (bytes.bytesize % 4).positive?
    bytes
  end
end
