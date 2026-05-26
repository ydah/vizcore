# frozen_string_literal: true

require "vizcore/sync/osc_message"

RSpec.describe Vizcore::Sync::OscMessage do
  it "parses OSC bundles with NTP timetags" do
    direct = osc_string("/vizcore/scene") +
             osc_string(",s") +
             osc_string("drop")
    nested = osc_string("/vizcore/tap") + osc_string("")
    nested_bundle = osc_string("#bundle") +
                    [0].pack("Q>") +
                    [nested.bytesize].pack("N") +
                    nested
    bundle = osc_string("#bundle") +
             [((1_600_000_123 + OSC_NTP_OFFSET) << 32)].pack("Q>") +
             [direct.bytesize].pack("N") +
             direct +
             [nested_bundle.bytesize].pack("N") +
             nested_bundle

    messages = described_class.parse(bundle)

    expect(messages).to be_an(Array)
    expect(messages.size).to eq(2)
    expect(messages[0].address).to eq("/vizcore/scene")
    expect(messages[0].timetag).to eq(1_600_000_123.0)
    expect(messages[1].address).to eq("/vizcore/tap")
    expect(messages[1].timetag).to be_nil
  end

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

  it "ignores malformed bundle entries and keeps valid messages" do
    valid = osc_string("/vizcore/scene") +
            osc_string(",s") +
            osc_string("drop")
    malformed_size = [16_777_216].pack("N")
    bundle = osc_string("#bundle") +
             [0].pack("Q>") +
             [valid.bytesize].pack("N") +
             valid +
             malformed_size +
             "\x00\x00\x00"

    messages = described_class.parse(bundle)

    expect(messages).to be_an(Array)
    expect(messages.size).to eq(1)
    expect(messages.first.address).to eq("/vizcore/scene")
  end

  it "supports unknown typetags without raising" do
    payload = osc_string("/vizcore/live") +
              osc_string(",z")

    message = described_class.parse(payload)

    expect(message).to be_a(described_class)
    expect(message.arguments).to eq([nil])
  end

  def osc_string(value)
    bytes = value.to_s.b + "\0"
    bytes << "\0" while (bytes.bytesize % 4).positive?
    bytes
  end

  OSC_NTP_OFFSET = 2_208_988_800
end
