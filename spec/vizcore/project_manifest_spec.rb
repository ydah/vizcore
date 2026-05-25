# frozen_string_literal: true

require "tmpdir"
require "vizcore/project_manifest"

RSpec.describe Vizcore::ProjectManifest do
  it "loads project defaults and expands relative paths from the manifest directory" do
    Dir.mktmpdir("vizcore-project-manifest") do |dir|
      manifest_path = File.join(dir, "vizcore.yml")
      File.write(
        manifest_path,
        <<~YAML
          scene: scenes/show.rb
          audio:
            source: file
            file: audio/show.wav
          control_preset: controls/live.json
          plugin_assets:
            - frontend/base-renderer.js
          sync:
            osc:
              port: 9000
          plugins:
            - vizcore-laser-grid
            - require: ./lib/local_plugin
              frontend: frontend/local-plugin.js
          profiles:
            show:
              scene: scenes/show_profile.rb
              control_preset: controls/show.json
              plugins:
                - require: ./lib/show_plugin
                  asset: frontend/show-plugin.js
        YAML
      )

      manifest = described_class.load(manifest_path)

      expect(manifest.config_defaults).to include(
        scene_file: Pathname.new(dir).join("scenes/show.rb").expand_path,
        audio_source: "file",
        audio_file: Pathname.new(dir).join("audio/show.wav").expand_path,
        control_preset: Pathname.new(dir).join("controls/live.json").expand_path,
        osc_port: 9000,
        plugin_assets: [
          Pathname.new(dir).join("frontend/local-plugin.js").expand_path,
          Pathname.new(dir).join("frontend/base-renderer.js").expand_path
        ]
      )
      expect(manifest.plugins).to eq(["vizcore-laser-grid", "./lib/local_plugin"])
      expect(manifest.profile_names).to eq(["show"])
      expect(manifest.config_defaults(profile: "show")).to include(
        scene_file: Pathname.new(dir).join("scenes/show_profile.rb").expand_path,
        control_preset: Pathname.new(dir).join("controls/show.json").expand_path,
        plugin_assets: [
          Pathname.new(dir).join("frontend/local-plugin.js").expand_path,
          Pathname.new(dir).join("frontend/show-plugin.js").expand_path,
          Pathname.new(dir).join("frontend/base-renderer.js").expand_path
        ]
      )
      expect(manifest.plugins(profile: "show")).to eq(["vizcore-laser-grid", "./lib/local_plugin", "./lib/show_plugin"])
    end
  end

  it "rejects plugin assets outside the manifest root" do
    Dir.mktmpdir("vizcore-project-manifest") do |dir|
      manifest_path = File.join(dir, "vizcore.yml")
      File.write(
        manifest_path,
        <<~YAML
          scene: scenes/show.rb
          plugin_assets:
            - ../outside.js
        YAML
      )

      expect do
        described_class.load(manifest_path).plugin_assets
      end.to raise_error(ArgumentError, /Plugin asset must stay inside/)
    end
  end

  it "rejects unsupported plugin asset extensions" do
    Dir.mktmpdir("vizcore-project-manifest") do |dir|
      manifest_path = File.join(dir, "vizcore.yml")
      File.write(
        manifest_path,
        <<~YAML
          scene: scenes/show.rb
          plugin_assets:
            - frontend/plugin.txt
        YAML
      )

      expect do
        described_class.load(manifest_path).plugin_assets
      end.to raise_error(ArgumentError, /Unsupported plugin asset extension/)
    end
  end
end
