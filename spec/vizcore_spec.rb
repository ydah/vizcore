# frozen_string_literal: true

require "tmpdir"

RSpec.describe Vizcore do
  around do |example|
    Vizcore::LayerCatalog.reset_plugin_capabilities!
    example.run
    Vizcore::LayerCatalog.reset_plugin_capabilities!
  end

  it "has a version number" do
    expect(Vizcore::VERSION).not_to be nil
  end

  it "exposes the project root path" do
    expect(Vizcore.root).to be_a(Pathname)
    expect(Vizcore.root.join("lib", "vizcore.rb")).to exist
  end

  it "loads plugins that register layer capabilities" do
    Dir.mktmpdir("vizcore-plugin") do |dir|
      plugin_path = Pathname.new(dir).join("vizcore_test_plugin.rb")
      plugin_path.write(<<~RUBY)
        Vizcore.register_layer_capability(
          type: :test_plugin_layer,
          params: { amount: "Float" },
          mappable_params: [:amount],
          description: "Test plugin layer."
        )
      RUBY

      $LOAD_PATH.unshift(dir)
      begin
        expect(Vizcore.plugin("vizcore_test_plugin")).to eq(true)
      ensure
        $LOAD_PATH.delete(dir)
      end

      expect(Vizcore::LayerCatalog).to be_supported_type(:test_plugin_layer)
      expect(Vizcore::LayerCatalog.params_for(:test_plugin_layer)).to include(amount: "Float")
    end
  end
end
