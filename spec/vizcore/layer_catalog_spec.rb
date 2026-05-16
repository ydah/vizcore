# frozen_string_literal: true

require "vizcore/layer_catalog"

RSpec.describe Vizcore::LayerCatalog do
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
      :shape_layer
    )
    expect(described_class).to be_supported_type(:particle)
    expect(described_class).not_to be_supported_type(:mesh)
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
  end
end
