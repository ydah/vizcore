# frozen_string_literal: true

require "tmpdir"
require "vizcore/dsl/file_watcher"

RSpec.describe Vizcore::DSL::FileWatcher do
  FakeListener = Struct.new(:callback, :started, :stopped) do
    def start
      self.started = true
    end

    def stop
      self.stopped = true
    end

    def trigger(modified: [], added: [], removed: [])
      callback.call(modified, added, removed)
    end
  end

  it "invokes callback on matching listener events" do
    Dir.mktmpdir("vizcore-file-watcher") do |dir|
      path = File.join(dir, "scene.rb")
      File.write(path, "Vizcore.define {}")

      listener = nil
      changed = nil
      watcher = described_class.new(
        path: path,
        listener_factory: lambda do |_directory, _pattern, &block|
          listener = FakeListener.new(block, false, false)
        end
      ) do |changed_path|
        changed = changed_path
      end

      watcher.start
      listener.trigger(modified: [path])
      watcher.stop

      expect(listener.started).to eq(true)
      expect(listener.stopped).to eq(true)
      expect(changed).to eq(Pathname.new(path).expand_path)
    end
  end
end
