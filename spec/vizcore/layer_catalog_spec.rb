# frozen_string_literal: true

require "vizcore/layer_catalog"

RSpec.describe Vizcore::LayerCatalog do
  around do |example|
    described_class.reset_plugin_capabilities!
    example.run
    described_class.reset_plugin_capabilities!
  end

  it "exposes supported layer types and aliases" do
    expect(described_class.supported_types).to include(
      :geometry,
      :wireframe_cube,
      :radial_blob,
      :shader,
      :particle_field,
      :particles,
      :text,
      :text_layer,
      :svg,
      :svg_layer,
      :image,
      :image_layer,
      :photo,
      :video,
      :video_layer,
      :footage,
      :waveform,
      :waveform_layer,
      :spectrogram,
      :spectrogram_layer,
      :shape,
      :shapes,
      :shape_layer,
      :mesh,
      :mesh_layer,
      :preset_mesh
    )
    expect(described_class).to be_supported_type(:particle)
    expect(described_class).to be_supported_type(:mesh)
  end

  it "returns params and mappable params for a layer family" do
    params = described_class.params_for(:particles)

    expect(params).to include(count: "Integer", speed: "Float", palette: "Array<String>")
    expect(described_class.mappable_params_for(:particle_field)).to include(:speed, :size, :sparkle)
    expect(described_class.mappable_params_for(:svg)).to include(:scale, :rotation, :opacity)
    expect(described_class.mappable_params_for(:image)).to include(:scale, :rotation, :opacity)
    expect(described_class.mappable_params_for(:video)).to include(:playback_rate, :invert)
    expect(described_class.mappable_params_for(:waveform)).to include(:height, :opacity, :color_shift)
    expect(described_class.mappable_params_for(:spectrogram)).to include(:gain, :opacity)
    expect(described_class.mappable_params_for(:shape)).to include(:color_shift, :opacity)
    expect(described_class.mappable_params_for(:mesh)).to include(:scale, :deform, :opacity, :color_shift)
  end

  it "registers plugin layer capabilities" do
    capability = described_class.register_layer_capability(
      type: :laser_grid,
      aliases: %i[laser_layer],
      params: { beam_count: "Integer", intensity: "Float" },
      mappable_params: %i[intensity opacity],
      description: "Plugin laser layer."
    )

    expect(capability.type).to eq(:laser_grid)
    expect(described_class.supported_types).to include(:laser_grid, :laser_layer)
    expect(described_class.params_for(:laser_layer)).to include(
      opacity: "Float",
      beam_count: "Integer",
      intensity: "Float"
    )
    expect(described_class.mappable_params_for(:laser_grid)).to include(:intensity, :opacity)
  end

  it "rejects plugin capabilities that conflict with built-in types" do
    expect do
      described_class.register_layer_capability(type: :mesh)
    end.to raise_error(ArgumentError, /built-in type: mesh/)
  end
end
