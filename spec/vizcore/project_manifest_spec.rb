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
          sync:
            osc:
              port: 9000
          plugins:
            - vizcore-laser-grid
        YAML
      )

      manifest = described_class.load(manifest_path)

      expect(manifest.config_defaults).to include(
        scene_file: Pathname.new(dir).join("scenes/show.rb").expand_path,
        audio_source: "file",
        audio_file: Pathname.new(dir).join("audio/show.wav").expand_path,
        control_preset: Pathname.new(dir).join("controls/live.json").expand_path,
        osc_port: 9000
      )
      expect(manifest.plugins).to eq(["vizcore-laser-grid"])
    end
  end
end
