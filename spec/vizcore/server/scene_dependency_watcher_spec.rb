# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "vizcore/server/scene_dependency_watcher"

RSpec.describe Vizcore::Server::SceneDependencyWatcher do
  FakeWatcher = Struct.new(:path, :callback, :started, :stopped) do
    def start
      self.started = true
    end

    def stop(timeout: 1.0)
      self.stopped = !timeout.nil?
    end

    def trigger
      callback.call(Pathname.new(path).expand_path)
    end
  end

  it "reloads the scene when a referenced GLSL file changes" do
    Dir.mktmpdir("vizcore-scene-dependency-watcher") do |dir|
      scene_path = File.join(dir, "scene.rb")
      shader_path = File.join(dir, "shaders", "liquid.frag")
      FileUtils.mkdir_p(File.dirname(shader_path))
      File.write(shader_path, "void main() {}")
      File.write(scene_path, scene_source("shaders/liquid.frag"))

      watchers = []
      watcher_factory = watcher_factory_for(watchers)
      yielded = nil
      definition = Vizcore::DSL::Engine.load_file(scene_path)

      watcher = described_class.new(scene_file: scene_path, definition: definition, watcher_factory: watcher_factory) do |updated, changed_path|
        yielded = [updated, changed_path]
      end

      watcher.start
      shader_watcher = watchers.find { |entry| entry.path == Pathname.new(shader_path).expand_path }
      shader_watcher.trigger
      watcher.stop

      definition, changed_path = yielded
      expect(changed_path).to eq(Pathname.new(shader_path).expand_path)
      expect(definition[:scenes].first[:layers].first[:glsl]).to eq("shaders/liquid.frag")
      expect(shader_watcher.started).to eq(true)
      expect(shader_watcher.stopped).to eq(true)
    end
  end

  it "refreshes GLSL dependency watchers after the scene changes" do
    Dir.mktmpdir("vizcore-scene-dependency-refresh") do |dir|
      scene_path = File.join(dir, "scene.rb")
      old_shader_path = File.join(dir, "shaders", "old.frag")
      new_shader_path = File.join(dir, "shaders", "new.frag")
      FileUtils.mkdir_p(File.dirname(old_shader_path))
      File.write(old_shader_path, "void main() {}")
      File.write(new_shader_path, "void main() {}")
      File.write(scene_path, scene_source("shaders/old.frag"))

      watchers = []
      watcher_factory = watcher_factory_for(watchers)
      definition = Vizcore::DSL::Engine.load_file(scene_path)
      yielded = nil

      watcher = described_class.new(scene_file: scene_path, definition: definition, watcher_factory: watcher_factory) do |updated, changed_path|
        yielded = [updated, changed_path]
      end
      watcher.start
      scene_watcher = watchers.find { |entry| entry.path == Pathname.new(scene_path).expand_path }
      old_shader_watcher = watchers.find { |entry| entry.path == Pathname.new(old_shader_path).expand_path }

      File.write(scene_path, scene_source("shaders/new.frag"))
      scene_watcher.trigger
      new_shader_watcher = watchers.find { |entry| entry.path == Pathname.new(new_shader_path).expand_path }
      watcher.stop

      expect(old_shader_watcher.stopped).to eq(true)
      expect(new_shader_watcher.started).to eq(true)
      expect(new_shader_watcher.stopped).to eq(true)
      expect(yielded.last).to eq(Pathname.new(scene_path).expand_path)
    end
  end

  def watcher_factory_for(watchers)
    Class.new do
      define_method(:initialize) do |path:, &block|
        @watcher = FakeWatcher.new(Pathname.new(path.to_s).expand_path, block, false, false)
        watchers << @watcher
      end

      define_method(:start) { @watcher.start }
      define_method(:stop) { |timeout: 1.0| @watcher.stop(timeout: timeout) }
    end
  end

  def scene_source(shader_path)
    <<~RUBY
      Vizcore.define do
        scene :shader_art do
          layer :liquid do
            glsl #{shader_path.inspect}
          end
        end
      end
    RUBY
  end
end
