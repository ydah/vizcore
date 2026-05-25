# frozen_string_literal: true

require "stringio"
require "vizcore/server"

RSpec.describe Vizcore::Server do
  describe ".start" do
    let(:output) { StringIO.new }
    let(:runner) { instance_double(Vizcore::Server::Runner, run: :started) }

    before do
      allow(Vizcore::Server::Runner).to receive(:new).and_return(runner)
    end

    it "starts a runner with an explicit config" do
      config = Vizcore::Config.new(scene_file: "examples/basic.rb", audio_source: :dummy)

      expect(described_class.start(config, output: output)).to eq(:started)
      expect(Vizcore::Server::Runner).to have_received(:new).with(config, output: output)
      expect(runner).to have_received(:run)
    end

    it "builds a config from keyword options" do
      described_class.start(scene_file: "examples/basic.rb", audio_source: :dummy, port: 4_580, output: output)

      expect(Vizcore::Server::Runner).to have_received(:new).with(
        have_attributes(scene_file: Pathname.new("examples/basic.rb").expand_path, audio_source: :dummy, port: 4_580),
        output: output
      )
    end
  end
end
