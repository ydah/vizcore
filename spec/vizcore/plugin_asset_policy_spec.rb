# frozen_string_literal: true

require "tmpdir"
require "vizcore/plugin_asset_policy"

RSpec.describe Vizcore::PluginAssetPolicy do
  it "accepts JavaScript plugin assets from allowed extensions and MIME types" do
    Dir.mktmpdir("vizcore-plugin-asset-policy") do |dir|
      root = Pathname.new(dir).expand_path
      asset_path = root.join("renderer.mjs")
      asset_path.write("globalThis.__plugin = true;")

      result = described_class.validate!(asset_path, root: root)

      expect(result).to eq(asset_path.expand_path)
    end
  end

  it "rejects plugin assets outside manifest root" do
    Dir.mktmpdir("vizcore-plugin-asset-policy") do |dir|
      root = Pathname.new(dir).expand_path
      outside = root.parent.join("outside-plugin.js")
      outside.write("")

      expect do
        described_class.validate!(outside, root: root)
      end.to raise_error(ArgumentError, /Plugin asset must stay inside/)
    end
  end

  it "rejects unsupported plugin asset extensions" do
    Dir.mktmpdir("vizcore-plugin-asset-policy") do |dir|
      root = Pathname.new(dir).expand_path
      asset_path = root.join("plugin.txt")
      asset_path.write("")

      expect do
        described_class.validate!(asset_path, root: root)
      end.to raise_error(ArgumentError, /Unsupported plugin asset extension/)
    end
  end

  it "rejects plugin assets with unsupported MIME types" do
    Dir.mktmpdir("vizcore-plugin-asset-policy") do |dir|
      root = Pathname.new(dir).expand_path
      asset_path = root.join("plugin.js")
      asset_path.write("")

      allow(Rack::Mime).to receive(:mime_type).and_wrap_original do |original_method, extname, fallback|
        next original_method.call(extname, fallback) unless extname == ".js"

        "text/plain"
      end

      expect do
        described_class.validate!(asset_path, root: root)
      end.to raise_error(ArgumentError, /Unsupported plugin asset MIME type/)
    end
  end
end
