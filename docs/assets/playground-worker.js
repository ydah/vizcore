import { DefaultRubyVM } from "https://cdn.jsdelivr.net/npm/@ruby/wasm-wasi@2.9.4/dist/browser/+esm";

const RUBY_WASM_URL = "https://cdn.jsdelivr.net/npm/@ruby/3.4-wasm-wasi@2.9.4/dist/ruby+stdlib.wasm";

const DSL_RUNTIME = `
require "base64"
require "json"
require "js"

module VizcorePlayground
  class Source
    attr_reader :kind, :name

    def initialize(kind, name = nil)
      @kind = kind.to_s
      @name = name&.to_s
    end

    def to_h
      output = { "source" => kind }
      output["name"] = name if name
      output
    end
  end

  module Normalizer
    module_function

    def value(input)
      case input
      when Source
        input.to_h
      when Symbol
        input.to_s
      when Range
        [input.begin, input.end]
      when Array
        input.map { |entry| value(entry) }
      when Hash
        input.each_with_object({}) { |(key, entry), output| output[key.to_s] = value(entry) }
      else
        input
      end
    end
  end

  module Sources
    def amplitude = Source.new("amplitude")
    def fft_spectrum = Source.new("fft_spectrum")
    def beat? = Source.new("beat")
    def beat = Source.new("beat")
    def beat_pulse = Source.new("beat_pulse")
    def beat_confidence = Source.new("beat_confidence")
    def bass = Source.new("band", "low")
    def low = Source.new("band", "low")
    def mid = Source.new("band", "mid")
    def treble = Source.new("band", "high")
    def high = Source.new("band", "high")
    def kick = Source.new("drum", "kick")
    def snare = Source.new("drum", "snare")
    def hihat = Source.new("drum", "hihat")

    def frequency_band(name)
      Source.new("band", name)
    end

    def onset(name = nil)
      name ? Source.new("onset", name) : Source.new("onset")
    end
  end

  class ShapeBuilder
    include Sources

    def initialize(type, attrs = {})
      @shape = { "type" => type.to_s, "mappings" => [] }.merge(Normalizer.value(attrs))
    end

    def map(source = nil, target = nil, **options)
      if source.is_a?(Hash)
        source.each { |entry_source, entry_target| add_mapping(entry_source, entry_target, options) }
      else
        add_mapping(source, target || options.delete(:to), options)
      end
    end

    def to_h = @shape

    private

    def add_mapping(source, target, options)
      @shape["mappings"] << {
        "source" => Normalizer.value(source),
        "target" => target.to_s,
        "transform" => Normalizer.value(options)
      }
    end

    def method_missing(name, *args, &block)
      return Source.new(name) if args.empty? && !block

      @shape[name.to_s] = args.length <= 1 ? Normalizer.value(args.first) : Normalizer.value(args)
    end

    def respond_to_missing?(_name, _include_private = false) = true
  end

  class LayerBuilder
    include Sources

    attr_reader :name

    def initialize(name)
      @name = name.to_s
      @type = "geometry"
      @shader = nil
      @params = {}
      @mappings = []
      @param_schema = []
    end

    def type(value)
      @type = value.to_s
    end

    def shader(value, **options)
      @type = "shader"
      @shader = value.to_s
      @params.merge!(Normalizer.value(options))
    end

    def glsl(path, **options)
      @type = "shader"
      @shader = "custom"
      @params["glsl"] = path.to_s
      @params.merge!(Normalizer.value(options))
    end

    def palette(*colors)
      @params["palette"] = colors.map(&:to_s)
    end

    def blend(value)
      @params["blend"] = value.to_s
    end

    def effect(value, **options)
      @params["effect"] = value.to_s
      @params["effect_options"] = Normalizer.value(options) unless options.empty?
    end

    def param(name, default:, range: nil, step: nil)
      schema = { "name" => name.to_s, "default" => default }
      if range
        schema["min"] = range.begin
        schema["max"] = range.end
      end
      schema["step"] = step if step
      @param_schema << schema
      @params["param_" + name.to_s] = default
    end

    def circle(count: 1, **attrs, &block)
      shape = ShapeBuilder.new(:circle, { count: count }.merge(attrs))
      shape.instance_eval(&block) if block
      (@params["shapes"] ||= []) << shape.to_h
    end

    def line(**attrs)
      (@params["shapes"] ||= []) << { "type" => "line" }.merge(Normalizer.value(attrs))
    end

    def map(source = nil, target = nil, **options)
      if source.is_a?(Hash)
        source.each { |entry_source, entry_target| add_mapping(entry_source, entry_target, options) }
      else
        add_mapping(source, target || options.delete(:to), options)
      end
    end

    def to_h
      output = {
        "name" => name,
        "type" => @type,
        "params" => @params,
        "mappings" => @mappings
      }
      output["shader"] = @shader if @shader
      output["param_schema"] = @param_schema unless @param_schema.empty?
      output
    end

    private

    def add_mapping(source, target, options)
      @mappings << {
        "source" => Normalizer.value(source),
        "target" => target.to_s,
        "transform" => Normalizer.value(options)
      }
    end

    def method_missing(name, *args, &block)
      return Source.new(name) if args.empty? && !block

      @params[name.to_s] = args.length <= 1 ? Normalizer.value(args.first) : Normalizer.value(args)
    end

    def respond_to_missing?(_name, _include_private = false) = true
  end

  class SceneBuilder
    def initialize(name)
      @name = name.to_s
      @layers = []
    end

    def layer(name, &block)
      builder = LayerBuilder.new(name)
      builder.instance_eval(&block) if block
      @layers << builder.to_h
    end

    def to_h
      { "name" => @name, "layers" => @layers }
    end
  end

  class TransitionBuilder
    def initialize(from, to)
      @transition = { "from" => from.to_s, "to" => to.to_s }
    end

    def on_bar(value)
      @transition["on_bar"] = value
    end

    def effect(value, **options)
      @transition["effect"] = value.to_s
      @transition["duration"] = options[:duration] if options.key?(:duration)
    end

    def to_h = @transition
  end

  class DefinitionBuilder
    include Sources

    def initialize
      @scenes = []
      @transitions = []
      @globals = {}
    end

    def scene(name, **_options, &block)
      builder = SceneBuilder.new(name)
      builder.instance_eval(&block) if block
      @scenes << builder.to_h
    end

    def transition(from:, to:, &block)
      builder = TransitionBuilder.new(from, to)
      builder.instance_eval(&block) if block
      @transitions << builder.to_h
    end

    def set(name, value)
      @globals[name.to_s] = Normalizer.value(value)
    end

    def to_h
      { "scenes" => @scenes, "transitions" => @transitions, "globals" => @globals }
    end

    def method_missing(_name, *_args, &_block)
      nil
    end

    def respond_to_missing?(_name, _include_private = false) = true
  end

  class << self
    attr_accessor :current_definition

    def compile_and_post(id, encoded)
      source = Base64.decode64(encoded).force_encoding("UTF-8")
      self.current_definition = nil
      definition = TOPLEVEL_BINDING.eval(source, "playground.rb", 1)
      definition = current_definition unless definition.is_a?(Hash)
      definition ||= { "scenes" => [], "transitions" => [], "globals" => {} }
      JS.global.postMessage({
        type: "compiled",
        id: id,
        definition_json: JSON.generate(definition)
      }.to_js)
    rescue Exception => error
      JS.global.postMessage({
        type: "error",
        id: id,
        message: error.message,
        backtrace: Array(error.backtrace).first(8)
      }.to_js)
    end
  end
end

module Vizcore
  def self.define(&block)
    builder = VizcorePlayground::DefinitionBuilder.new
    builder.instance_eval(&block) if block
    VizcorePlayground.current_definition = builder.to_h
  end
end
`;

let vmPromise = null;

const postStatus = (message) => {
  self.postMessage({ type: "status", message });
};

const compileWasm = async (response) => {
  try {
    return await WebAssembly.compileStreaming(response);
  } catch (_error) {
    const fallbackResponse = await fetch(RUBY_WASM_URL);
    return WebAssembly.compile(await fallbackResponse.arrayBuffer());
  }
};

const initializeVm = async () => {
  postStatus("Loading Ruby wasm");
  const response = await fetch(RUBY_WASM_URL);
  const rubyModule = await compileWasm(response);
  const { vm } = await DefaultRubyVM(rubyModule);
  vm.eval(DSL_RUNTIME);
  self.postMessage({ type: "ready" });
  return vm;
};

const getVm = () => {
  vmPromise ||= initializeVm();
  return vmPromise;
};

const encodeBase64 = (source) => {
  const bytes = new TextEncoder().encode(source);
  let binary = "";
  const chunkSize = 0x8000;
  for (let index = 0; index < bytes.length; index += chunkSize) {
    const chunk = bytes.subarray(index, index + chunkSize);
    binary += String.fromCharCode(...chunk);
  }
  return btoa(binary);
};

self.addEventListener("message", async (event) => {
  const message = event.data || {};
  if (message.type !== "compile") return;

  try {
    const vm = await getVm();
    postStatus("Evaluating Ruby DSL");
    vm.eval('VizcorePlayground.compile_and_post(' + Number(message.id) + ', "' + encodeBase64(String(message.source || "")) + '")');
  } catch (error) {
    self.postMessage({
      type: "error",
      id: message.id,
      message: error instanceof Error ? error.message : String(error),
      backtrace: []
    });
  }
});
