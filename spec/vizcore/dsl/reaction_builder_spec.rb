# frozen_string_literal: true

require "vizcore/dsl/reaction_builder"

RSpec.describe Vizcore::DSL::ReactionBuilder do
  it "collects change and trigger reactions through the supplied mapping factory" do
    builder = described_class.new(
      mapping_factory: lambda do |target, options|
        { target: target.to_sym, transform: options }
      end
    )

    mappings = builder.evaluate do
      change :speed, gain: 2.0
      trigger :burst
    end

    expect(mappings).to eq(
      [
        { target: :speed, transform: { gain: 2.0 } },
        { target: :burst, transform: {} }
      ]
    )
  end

  it "rejects empty reaction blocks" do
    builder = described_class.new(mapping_factory: ->(_target, _options) { {} })

    expect do
      builder.evaluate { nil }
    end.to raise_error(ArgumentError, /at least one change or trigger/)
  end
end
