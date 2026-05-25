# frozen_string_literal: true

require "vizcore/deep_copy"

RSpec.describe Vizcore::DeepCopy do
  it "copies nested hashes and arrays without sharing containers" do
    original = { scene: { layers: [{ name: :main, params: { opacity: 1.0 } }] } }
    copied = described_class.copy(original)

    copied[:scene][:layers][0][:params][:opacity] = 0.5

    expect(original[:scene][:layers][0][:params][:opacity]).to eq(1.0)
    expect(copied[:scene][:layers][0][:params][:opacity]).to eq(0.5)
  end
end
