# frozen_string_literal: true

require "json"
require "vizcore"

RSpec.describe "DSL snapshots" do
  SNAPSHOT_ROOT = Vizcore.root.join("spec", "fixtures", "snapshots")

  it "keeps intro_drop DSL IR stable" do
    definition = Vizcore::DSL::Engine.load_file("examples/intro_drop.rb")
    snapshot = JSON.parse(SNAPSHOT_ROOT.join("intro_drop_dsl.json").read)

    expect(snapshot_payload(definition)).to eq(snapshot)
  end

  def snapshot_payload(value)
    case value
    when Hash
      value.keys.sort_by(&:to_s).each_with_object({}) do |key, output|
        output[key.to_s] = snapshot_payload(value[key])
      end
    when Array
      value.map { |entry| snapshot_payload(entry) }
    when Symbol
      value.to_s
    when Proc
      "<proc>"
    else
      value
    end
  end
end
