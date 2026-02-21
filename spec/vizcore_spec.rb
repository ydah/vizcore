# frozen_string_literal: true

RSpec.describe Vizcore do
  it "has a version number" do
    expect(Vizcore::VERSION).not_to be nil
  end

  it "exposes the project root path" do
    expect(Vizcore.root).to be_a(Pathname)
    expect(Vizcore.root.join("lib", "vizcore.rb")).to exist
  end
end
