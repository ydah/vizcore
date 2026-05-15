# frozen_string_literal: true

RSpec.describe "vizcore.gemspec" do
  let(:specification) { Gem::Specification.load("vizcore.gemspec") }

  it "packages runtime examples, browser assets, static site and signatures" do
    expect(specification.files).to include(
      "exe/vizcore",
      "frontend/index.html",
      "frontend/src/main.js",
      "examples/basic.rb",
      "examples/ruby_crystal_show.rb",
      "examples/assets/complex_demo_loop.wav",
      "docs/index.html",
      "docs/assets/site.css",
      "sig/vizcore.rbs"
    )
  end

  it "does not package frontend test files" do
    expect(specification.files.grep(%r{\Afrontend/test/})).to be_empty
  end
end
