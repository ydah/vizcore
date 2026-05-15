# frozen_string_literal: true

require "vizcore/layer_catalog"

RSpec.describe Vizcore::LayerCatalog do
  it "exposes supported layer types and aliases" do
    expect(described_class.supported_types).to include(:geometry, :wireframe_cube, :radial_blob, :shader, :particle_field, :particles, :text, :text_layer, :svg, :svg_layer)
    expect(described_class).to be_supported_type(:particle)
    expect(described_class).not_to be_supported_type(:video)
  end

  it "returns params and mappable params for a layer family" do
    params = described_class.params_for(:particles)

    expect(params).to include(count: "Integer", speed: "Float", palette: "Array<String>")
    expect(described_class.mappable_params_for(:particle_field)).to include(:speed, :size, :sparkle)
    expect(described_class.mappable_params_for(:svg)).to include(:scale, :rotation, :opacity)
  end
end
