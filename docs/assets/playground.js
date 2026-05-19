const presets = {
  rings: {
    label: "Beat rings",
    source: `Vizcore.define do
  scene :readme_demo do
    layer :beat_rings do
      palette "#24f6ff", "#ff2bbd", "#caff2e"

      circle count: 4 do
        radius 92
        stroke 3
        map beat_pulse, to: :radius, gain: 160.0, min: 56, max: 164, release: 0.2
      end
    end
  end
end`
  },
  drop: {
    label: "Drop scene",
    source: `Vizcore.define do
  scene :intro do
    layer :title do
      type :text
      content "VIZCORE"
      font_size 92
      fill "#ffffff"
      map beat?, to: :opacity, range: 0.35..1.0
    end

    layer :grid do
      shader :neon_grid
      map mid, to: :intensity, gain: 1.8, range: 0.2..1.0
    end
  end

  scene :drop do
    layer :tunnel do
      shader :bass_tunnel
      map bass, to: :scale, range: 0.8..1.5, curve: :sqrt
      map beat_pulse, to: :flash
    end

    layer :particles do
      type :particle_field
      count 2400
      blend :screen
      map bass, to: :size, range: 2.0..8.0
      map treble, to: :sparkle
    end
  end

  transition from: :intro, to: :drop do
    on_bar 8
    effect :crossfade, duration: 1.0
  end
end`
  },
  scopes: {
    label: "Scopes",
    source: `Vizcore.define do
  scene :analysis do
    layer :wave do
      type :waveform
      source :audio
      style :ribbon
      map amplitude, to: :height, range: 0.15..0.7
    end

    layer :waterfall do
      type :spectrogram
      scroll :vertical
      bins 64
      map treble, to: :gain, range: 0.7..2.4
    end

    layer :mesh do
      type :wireframe_cube
      map bass, to: :scale, range: 0.75..1.35
      map mid, to: :rotation_speed, range: 0.2..1.8
    end
  end
end`
  }
};

const editor = document.querySelector("#editor");
const presetSelect = document.querySelector("#preset-select");
const runButton = document.querySelector("#run-button");
const resetButton = document.querySelector("#reset-button");
const rubyStatus = document.querySelector("#ruby-status");
const compileStatus = document.querySelector("#compile-status");
const jsonOutput = document.querySelector("#json-output");
const sceneTabs = document.querySelector("#scene-tabs");
const canvas = document.querySelector("#preview-canvas");
const sceneStat = document.querySelector("#scene-stat");
const audioStat = document.querySelector("#audio-stat");
const beatStat = document.querySelector("#beat-stat");
const errorOutput = document.querySelector("#error-output");
const context = canvas.getContext("2d");

const compileTimeoutMs = 9000;
let worker = null;
let requestId = 0;
let pendingCompile = null;
let latestRunId = 0;
let sceneDefinition = null;
let activeSceneName = "";
let lastFrameTime = performance.now();
let beatStartedAt = 0;
let animationFrame = 0;

const clamp = (value, min = 0, max = 1) => Math.min(Math.max(value, min), max);

const populatePresets = () => {
  Object.entries(presets).forEach(([key, preset]) => {
    const option = document.createElement("option");
    option.value = key;
    option.textContent = preset.label;
    presetSelect.append(option);
  });
  presetSelect.value = "rings";
  editor.value = presets.rings.source;
};

const setStatus = (message, detail = "") => {
  rubyStatus.textContent = message;
  compileStatus.textContent = detail;
};

const showError = (message, backtrace = []) => {
  errorOutput.hidden = false;
  errorOutput.textContent = [message, ...backtrace].filter(Boolean).join("\n");
};

const clearError = () => {
  errorOutput.hidden = true;
  errorOutput.textContent = "";
};

const restartWorker = () => {
  if (worker) {
    worker.terminate();
  }
  worker = new Worker(new URL("playground-worker.js", import.meta.url), { type: "module" });
  worker.addEventListener("message", handleWorkerMessage);
  worker.addEventListener("error", (event) => {
    rejectPending(new Error(event.message || "Ruby worker failed"));
    setStatus("Ruby wasm error", "Worker failed");
  });
};

const rejectPending = (error) => {
  if (!pendingCompile) return;

  clearTimeout(pendingCompile.timer);
  pendingCompile.reject(error);
  pendingCompile = null;
};

const cancelPendingCompile = () => {
  const error = Object.assign(new Error("Compile request was superseded"), { cancelled: true });
  rejectPending(error);
};

const handleWorkerMessage = (event) => {
  const message = event.data || {};
  if (message.type === "ready") {
    setStatus("Ruby wasm ready", "Loaded");
    return;
  }
  if (message.type === "status") {
    setStatus(message.message, "Working");
    return;
  }
  if (!pendingCompile || message.id !== pendingCompile.id) return;

  clearTimeout(pendingCompile.timer);
  const pending = pendingCompile;
  pendingCompile = null;

  if (message.type === "compiled") {
    pending.resolve(JSON.parse(message.definition_json || "{}"));
    return;
  }

  pending.reject(Object.assign(new Error(message.message || "Ruby compile failed"), {
    backtrace: message.backtrace || []
  }));
};

const compileScene = (source) => {
  if (!worker) {
    restartWorker();
  }

  if (pendingCompile) {
    cancelPendingCompile();
  }

  requestId += 1;
  const id = requestId;

  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      rejectPending(new Error("Ruby evaluation timed out"));
      restartWorker();
    }, compileTimeoutMs);

    pendingCompile = { id, timer, resolve, reject };
    worker.postMessage({ type: "compile", id, source });
  });
};

const runEditor = async () => {
  const runId = latestRunId + 1;
  latestRunId = runId;
  clearError();
  runButton.disabled = true;
  setStatus("Ruby wasm", "Compiling");

  try {
    const definition = await compileScene(editor.value);
    if (runId !== latestRunId) return;

    sceneDefinition = normalizeDefinition(definition);
    activeSceneName = sceneDefinition.scenes[0]?.name || "";
    jsonOutput.textContent = JSON.stringify(sceneDefinition, null, 2);
    renderSceneTabs();
    setStatus("Ruby wasm ready", "Compiled");
  } catch (error) {
    if (error.cancelled) return;

    showError(error.message, error.backtrace);
    setStatus("Ruby wasm error", "Compile failed");
  } finally {
    if (runId === latestRunId) {
      runButton.disabled = false;
    }
  }
};

const normalizeDefinition = (definition) => {
  const scenes = Array.isArray(definition?.scenes) ? definition.scenes : [];
  return {
    scenes: scenes.map((scene) => ({
      name: String(scene?.name || "scene"),
      layers: Array.isArray(scene?.layers) ? scene.layers : []
    })),
    transitions: Array.isArray(definition?.transitions) ? definition.transitions : [],
    globals: definition?.globals && typeof definition.globals === "object" ? definition.globals : {}
  };
};

const renderSceneTabs = () => {
  sceneTabs.replaceChildren();
  const scenes = sceneDefinition?.scenes || [];
  scenes.forEach((scene) => {
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = scene.name;
    button.className = scene.name === activeSceneName ? "scene-tab active" : "scene-tab";
    button.addEventListener("click", () => {
      activeSceneName = scene.name;
      renderSceneTabs();
    });
    sceneTabs.append(button);
  });
};

const resizeCanvas = () => {
  const rect = canvas.getBoundingClientRect();
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  const width = Math.max(1, Math.floor(rect.width * dpr));
  const height = Math.max(1, Math.floor(rect.height * dpr));
  if (canvas.width === width && canvas.height === height) return;

  canvas.width = width;
  canvas.height = height;
};

const buildAudio = (time) => {
  const beatInterval = 0.5;
  const beatPhase = time % beatInterval;
  const beat = beatPhase < 0.07;
  if (beat && time - beatStartedAt > 0.2) {
    beatStartedAt = time;
  }

  const beatPulse = clamp(1 - (time - beatStartedAt) * 4);
  const low = clamp(0.48 + Math.sin(time * 3.2) * 0.28 + beatPulse * 0.32);
  const mid = clamp(0.44 + Math.sin(time * 4.7 + 1.1) * 0.24);
  const high = clamp(0.36 + Math.sin(time * 8.3 + 0.7) * 0.26 + (beat ? 0.22 : 0));
  const amplitude = clamp((low + mid + high) / 3);
  const fft = Array.from({ length: 32 }, (_, index) => {
    const wave = Math.sin(time * (1.4 + index * 0.08) + index * 0.41);
    const falloff = 1 - index / 42;
    return clamp((0.45 + wave * 0.4) * falloff + beatPulse * 0.18);
  });

  return {
    amplitude,
    beat,
    beat_pulse: beatPulse,
    beat_confidence: clamp(beatPulse + 0.2),
    bands: { sub: low * 0.78, low, mid, high },
    drums: { kick: low * beatPulse, snare: mid * (beat ? 0.8 : 0.2), hihat: high },
    onsets: { low: beatPulse, mid: mid * 0.35, high: high * 0.4 },
    onset: Math.max(beatPulse, high * 0.3),
    fft,
    bpm: 120,
    beat_count: Math.floor(time / beatInterval)
  };
};

const sourceValue = (source, audio) => {
  if (!source || typeof source !== "object") return 0;

  if (source.source === "amplitude") return audio.amplitude;
  if (source.source === "fft_spectrum") return average(audio.fft);
  if (source.source === "beat") return audio.beat ? 1 : 0;
  if (source.source === "beat_pulse") return audio.beat_pulse;
  if (source.source === "beat_confidence") return audio.beat_confidence;
  if (source.source === "band") return Number(audio.bands?.[source.name] || 0);
  if (source.source === "drum") return Number(audio.drums?.[source.name] || 0);
  if (source.source === "onset") {
    return source.name ? Number(audio.onsets?.[source.name] || 0) : Number(audio.onset || 0);
  }

  return 0;
};

const average = (values) => {
  if (!Array.isArray(values) || values.length === 0) return 0;
  return values.reduce((sum, value) => sum + Number(value || 0), 0) / values.length;
};

const applyTransform = (value, transform = {}) => {
  let output = Number(value || 0);
  const deadzone = Number(transform.deadzone || 0);
  if (Math.abs(output) < deadzone) output = 0;

  output *= Number(transform.gain || 1);

  if (transform.curve === "sqrt") output = Math.sqrt(Math.max(output, 0));
  if (transform.curve === "square") output *= output;
  if (transform.curve === "ease_out") output = 1 - Math.pow(1 - clamp(output), 2);

  if (Array.isArray(transform.range) && transform.range.length >= 2) {
    const min = Number(transform.range[0]);
    const max = Number(transform.range[1]);
    output = min + clamp(output) * (max - min);
  }

  if (transform.min !== undefined) output = Math.max(output, Number(transform.min));
  if (transform.max !== undefined) output = Math.min(output, Number(transform.max));
  return output;
};

const layerParams = (layer, audio) => {
  const params = { ...(layer?.params || {}) };
  const mappings = Array.isArray(layer?.mappings) ? layer.mappings : [];
  mappings.forEach((mapping) => {
    if (!mapping?.target) return;
    params[mapping.target] = applyTransform(sourceValue(mapping.source, audio), mapping.transform);
  });
  return params;
};

const shapeParams = (shape, audio) => {
  const params = { ...shape };
  const mappings = Array.isArray(shape?.mappings) ? shape.mappings : [];
  mappings.forEach((mapping) => {
    if (!mapping?.target) return;
    params[mapping.target] = applyTransform(sourceValue(mapping.source, audio), mapping.transform);
  });
  return params;
};

const render = (now) => {
  resizeCanvas();
  const delta = Math.min((now - lastFrameTime) / 1000, 0.05);
  lastFrameTime = now;
  const time = now / 1000;
  const audio = buildAudio(time);

  drawFrame(time, delta, audio);
  updateStats(audio);
  animationFrame = requestAnimationFrame(render);
};

const drawFrame = (time, _delta, audio) => {
  const width = canvas.width;
  const height = canvas.height;
  context.clearRect(0, 0, width, height);
  drawBackground(width, height, audio);

  const scene = currentScene();
  if (!scene) {
    drawIdle(width, height, time, audio);
    return;
  }

  scene.layers.forEach((layer, index) => {
    const params = layerParams(layer, audio);
    const type = String(layer?.type || "geometry");
    const shader = String(layer?.shader || "");

    context.save();
    context.globalCompositeOperation = blendMode(params.blend);
    context.globalAlpha = clamp(Number(params.opacity ?? 1), 0, 1);

    if (type === "shader") drawShaderLayer(width, height, shader, params, audio, time, index);
    if (type === "particle_field") drawParticles(width, height, params, audio, time);
    if (type === "text") drawText(width, height, params, audio);
    if (type === "waveform") drawWaveform(width, height, params, audio, time);
    if (type === "spectrogram") drawSpectrogram(width, height, params, audio);
    if (type === "wireframe_cube" || type === "mesh") drawWireframe(width, height, params, audio, time);
    drawShapes(width, height, params, audio);

    context.restore();
  });
};

const currentScene = () => {
  const scenes = sceneDefinition?.scenes || [];
  return scenes.find((scene) => scene.name === activeSceneName) || scenes[0] || null;
};

const blendMode = (mode) => {
  if (mode === "screen") return "screen";
  if (mode === "add") return "lighter";
  if (mode === "multiply") return "multiply";
  if (mode === "difference") return "difference";
  return "source-over";
};

const drawBackground = (width, height, audio) => {
  const gradient = context.createLinearGradient(0, 0, width, height);
  gradient.addColorStop(0, "#06110f");
  gradient.addColorStop(0.5, "#0b1220");
  gradient.addColorStop(1, "#130812");
  context.fillStyle = gradient;
  context.fillRect(0, 0, width, height);

  context.strokeStyle = `rgba(56, 189, 248, ${0.06 + audio.amplitude * 0.08})`;
  context.lineWidth = 1;
  const grid = Math.max(44, width / 20);
  for (let x = 0; x <= width; x += grid) {
    context.beginPath();
    context.moveTo(x, 0);
    context.lineTo(x, height);
    context.stroke();
  }
  for (let y = 0; y <= height; y += grid) {
    context.beginPath();
    context.moveTo(0, y);
    context.lineTo(width, y);
    context.stroke();
  }
};

const drawIdle = (width, height, time, audio) => {
  context.save();
  context.translate(width / 2, height / 2);
  for (let index = 0; index < 9; index += 1) {
    const radius = 70 + index * 36 + Math.sin(time * 2 + index) * 12 + audio.beat_pulse * 42;
    context.strokeStyle = color(index, 0.35);
    context.lineWidth = 2;
    context.beginPath();
    context.arc(0, 0, radius, 0, Math.PI * 2);
    context.stroke();
  }
  context.restore();
};

const drawShaderLayer = (width, height, shader, params, audio, time, index) => {
  if (shader.includes("rings") || shader.includes("tunnel")) {
    context.save();
    context.translate(width / 2, height / 2);
    const scale = Number(params.scale || 1);
    for (let ring = 0; ring < 14; ring += 1) {
      const radius = (ring * 42 + (time * 50) % 42) * scale + audio.beat_pulse * 48;
      context.strokeStyle = color(ring + index, 0.18 + audio.amplitude * 0.35);
      context.lineWidth = 2 + audio.beat_pulse * 5;
      context.beginPath();
      context.arc(0, 0, radius, 0, Math.PI * 2);
      context.stroke();
    }
    context.restore();
    return;
  }

  const stripes = 18;
  for (let stripe = 0; stripe < stripes; stripe += 1) {
    const y = (stripe / stripes) * height;
    const offset = Math.sin(time * 2 + stripe * 0.8) * 90 * audio.bands.mid;
    context.fillStyle = color(stripe + index, 0.1 + audio.amplitude * 0.18);
    context.fillRect(offset, y, width, height / stripes + 2);
  }
};

const drawParticles = (width, height, params, audio, time) => {
  const count = Math.min(Number(params.count || 900), 1100);
  const size = Number(params.size || 2.5);
  const sparkle = Number(params.sparkle || audio.bands.high);
  context.fillStyle = `rgba(248, 250, 252, ${0.24 + sparkle * 0.46})`;
  for (let index = 0; index < count; index += 1) {
    const seed = index * 12.9898;
    const angle = seed + time * (0.15 + audio.bands.low);
    const orbit = ((index % 97) / 97) * Math.min(width, height) * 0.55;
    const x = width / 2 + Math.cos(angle) * orbit + Math.sin(seed) * width * 0.08;
    const y = height / 2 + Math.sin(angle * 1.17) * orbit * 0.65;
    context.fillRect(x, y, size, size);
  }
};

const drawText = (width, height, params, audio) => {
  const text = String(params.content || "VIZCORE");
  const opacity = Number(params.opacity ?? 1);
  context.globalAlpha *= clamp(opacity + audio.beat_pulse * 0.2);
  context.fillStyle = String(params.fill || "#f8fafc");
  context.font = `700 ${Number(params.font_size || 72)}px IBM Plex Sans, system-ui, sans-serif`;
  context.textAlign = "center";
  context.textBaseline = "middle";
  context.shadowColor = "rgba(34, 197, 94, 0.45)";
  context.shadowBlur = 24 + audio.beat_pulse * 28;
  text.split("\\n").forEach((line, index, lines) => {
    context.fillText(line, width / 2, height / 2 + (index - (lines.length - 1) / 2) * 92);
  });
};

const drawWaveform = (width, height, params, audio, time) => {
  const waveHeight = Number(params.height || 0.35) * height;
  context.strokeStyle = "rgba(36, 246, 255, 0.86)";
  context.lineWidth = 3;
  context.beginPath();
  for (let x = 0; x <= width; x += 8) {
    const unit = x / width;
    const y = height / 2 + Math.sin(unit * Math.PI * 8 + time * 5) * waveHeight * (0.25 + audio.amplitude);
    if (x === 0) context.moveTo(x, y);
    else context.lineTo(x, y);
  }
  context.stroke();
};

const drawSpectrogram = (width, height, params, audio) => {
  const bins = Math.min(Number(params.bins || 32), 96);
  const gain = Number(params.gain || 1);
  const barWidth = width / bins;
  for (let index = 0; index < bins; index += 1) {
    const value = clamp((audio.fft[index % audio.fft.length] || 0) * gain);
    context.fillStyle = color(index, 0.2 + value * 0.55);
    context.fillRect(index * barWidth, height * (1 - value), Math.ceil(barWidth), height * value);
  }
};

const drawWireframe = (width, height, params, audio, time) => {
  const scale = Math.min(width, height) * 0.18 * Number(params.scale || 1);
  const speed = Number(params.rotation_speed || 1);
  const points = [
    [-1, -1, -1], [1, -1, -1], [1, 1, -1], [-1, 1, -1],
    [-1, -1, 1], [1, -1, 1], [1, 1, 1], [-1, 1, 1]
  ].map(([x, y, z]) => projectPoint(x, y, z, scale, time * speed, width, height));
  const edges = [[0,1], [1,2], [2,3], [3,0], [4,5], [5,6], [6,7], [7,4], [0,4], [1,5], [2,6], [3,7]];
  context.strokeStyle = `rgba(163, 230, 53, ${0.5 + audio.amplitude * 0.35})`;
  context.lineWidth = 2;
  edges.forEach(([a, b]) => {
    context.beginPath();
    context.moveTo(points[a][0], points[a][1]);
    context.lineTo(points[b][0], points[b][1]);
    context.stroke();
  });
};

const projectPoint = (x, y, z, scale, rotation, width, height) => {
  const cos = Math.cos(rotation);
  const sin = Math.sin(rotation);
  const rx = x * cos - z * sin;
  const rz = x * sin + z * cos + 4;
  const perspective = scale / rz;
  return [width / 2 + rx * perspective * 4, height / 2 + y * perspective * 4];
};

const drawShapes = (width, height, params, audio) => {
  const shapes = Array.isArray(params.shapes) ? params.shapes : [];
  shapes.forEach((shape, shapeIndex) => {
    const resolved = shapeParams(shape, audio);
    if (resolved.type === "circle") {
      const count = Math.max(1, Number(resolved.count || 1));
      for (let index = 0; index < count; index += 1) {
        const radius = Number(resolved.radius || 90) + index * 42;
        context.strokeStyle = color(index + shapeIndex, 0.5);
        context.lineWidth = Number(resolved.stroke || 3);
        context.beginPath();
        context.arc(width / 2, height / 2, radius, 0, Math.PI * 2);
        context.stroke();
      }
    }
    if (resolved.type === "line") {
      context.strokeStyle = color(shapeIndex, 0.55);
      context.lineWidth = Number(resolved.stroke || 2);
      context.beginPath();
      context.moveTo(Number(resolved.x1 || 0), Number(resolved.y1 || height / 2));
      context.lineTo(Number(resolved.x2 || width), Number(resolved.y2 || height / 2));
      context.stroke();
    }
  });
};

const color = (index, alpha = 1) => {
  const palette = [
    [36, 246, 255],
    [255, 43, 189],
    [202, 255, 46],
    [250, 204, 21],
    [251, 113, 133]
  ];
  const entry = palette[index % palette.length];
  return `rgba(${entry[0]}, ${entry[1]}, ${entry[2]}, ${alpha})`;
};

const updateStats = (audio) => {
  const scene = currentScene();
  sceneStat.textContent = `Scene: ${scene?.name || "--"}`;
  audioStat.textContent = `Amplitude: ${audio.amplitude.toFixed(3)}`;
  beatStat.textContent = `Beat: ${audio.beat ? "ON" : "off"} | BPM: ${audio.bpm}`;
  beatStat.classList.toggle("active", audio.beat);
};

const bindEvents = () => {
  runButton.addEventListener("click", runEditor);
  resetButton.addEventListener("click", () => {
    editor.value = presets[presetSelect.value].source;
    runEditor();
  });
  presetSelect.addEventListener("change", () => {
    editor.value = presets[presetSelect.value].source;
    runEditor();
  });
  window.addEventListener("resize", resizeCanvas);
};

populatePresets();
bindEvents();
restartWorker();
runEditor();
animationFrame = requestAnimationFrame(render);

window.addEventListener("beforeunload", () => {
  cancelAnimationFrame(animationFrame);
  if (worker) worker.terminate();
});
