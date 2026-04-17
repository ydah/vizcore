const canvas = document.querySelector("#vj-field");

if (canvas) {
  const context = canvas.getContext("2d", { alpha: true });
  const reducedMotionQuery = window.matchMedia("(prefers-reduced-motion: reduce)");
  const state = {
    width: 0,
    height: 0,
    ratio: 1,
    pointerX: 0,
    pointerY: 0,
    reduced: reducedMotionQuery.matches,
    animationFrame: 0
  };
  const palette = ["#ff2bbd", "#24f6ff", "#caff2e", "#ffe44d", "#ff405d", "#33ff91"];

  const resize = () => {
    state.ratio = Math.min(window.devicePixelRatio || 1, 2);
    state.width = Math.max(1, canvas.clientWidth);
    state.height = Math.max(1, canvas.clientHeight);
    canvas.width = Math.floor(state.width * state.ratio);
    canvas.height = Math.floor(state.height * state.ratio);
    context.setTransform(state.ratio, 0, 0, state.ratio, 0, 0);
    draw(performance.now());
  };

  const color = (index, alpha) => {
    const hex = palette[index % palette.length];
    const red = Number.parseInt(hex.slice(1, 3), 16);
    const green = Number.parseInt(hex.slice(3, 5), 16);
    const blue = Number.parseInt(hex.slice(5, 7), 16);
    return `rgba(${red}, ${green}, ${blue}, ${alpha})`;
  };

  const drawTunnel = (time) => {
    const centerX = state.width * (0.62 + state.pointerX * 0.08);
    const centerY = state.height * (0.48 + state.pointerY * 0.08);
    const radiusMax = Math.hypot(state.width, state.height) * 0.72;

    context.save();
    context.globalCompositeOperation = "lighter";
    for (let ring = 1; ring <= 24; ring += 1) {
      const progress = ring / 24;
      const radius = progress * radiusMax;
      const pulse = Math.sin(time * 0.0024 + ring * 0.72) * 14;
      context.beginPath();
      for (let point = 0; point <= 96; point += 1) {
        const theta = (point / 96) * Math.PI * 2;
        const wobble = Math.sin(theta * 5 + time * 0.0018 + ring) * 18 * progress;
        const x = centerX + Math.cos(theta + time * 0.0004) * (radius + pulse + wobble);
        const y = centerY + Math.sin(theta - time * 0.0003) * (radius * 0.62 + pulse + wobble);
        if (point === 0) {
          context.moveTo(x, y);
        } else {
          context.lineTo(x, y);
        }
      }
      context.closePath();
      context.lineWidth = Math.max(1.4, 6 - progress * 4);
      context.strokeStyle = color(ring, 0.32 + progress * 0.42);
      context.stroke();
    }
    context.restore();
  };

  const drawLasers = (time) => {
    const centerX = state.width * (0.62 + state.pointerX * 0.06);
    const centerY = state.height * (0.5 + state.pointerY * 0.06);
    const length = Math.hypot(state.width, state.height);

    context.save();
    context.globalCompositeOperation = "lighter";
    for (let index = 0; index < 42; index += 1) {
      const angle = index * 0.42 + time * 0.00065;
      const start = Math.sin(time * 0.001 + index) * 34;
      context.beginPath();
      context.moveTo(centerX + Math.cos(angle) * start, centerY + Math.sin(angle) * start);
      context.lineTo(centerX + Math.cos(angle) * length, centerY + Math.sin(angle) * length);
      context.lineWidth = index % 7 === 0 ? 3 : 1.2;
      context.strokeStyle = color(index + 2, index % 7 === 0 ? 0.62 : 0.28);
      context.stroke();
    }
    context.restore();
  };

  const drawSpectrum = (time) => {
    const bars = 46;
    const baseline = state.height * 0.86;
    const barWidth = state.width / bars;

    context.save();
    context.globalCompositeOperation = "lighter";
    for (let index = 0; index < bars; index += 1) {
      const wave = Math.sin(time * 0.004 + index * 0.55);
      const kick = Math.sin(time * 0.0016 + index * 0.17);
      const height = 22 + Math.abs(wave * kick) * state.height * 0.24;
      const x = index * barWidth;
      context.fillStyle = color(index, 0.16 + Math.abs(wave) * 0.32);
      context.fillRect(x, baseline - height, Math.max(2, barWidth - 4), height);
    }
    context.restore();
  };

  const drawNoise = (time) => {
    context.save();
    context.globalAlpha = 0.2;
    context.fillStyle = "#ffffff";
    for (let index = 0; index < 120; index += 1) {
      const x = (Math.sin(index * 43.12 + time * 0.0017) * 0.5 + 0.5) * state.width;
      const y = (Math.cos(index * 27.33 + time * 0.0011) * 0.5 + 0.5) * state.height;
      context.fillRect(x, y, 1.2, 1.2);
    }
    context.restore();
  };

  const draw = (time) => {
    context.clearRect(0, 0, state.width, state.height);
    context.fillStyle = "rgba(5, 0, 6, 0.72)";
    context.fillRect(0, 0, state.width, state.height);

    const gradient = context.createLinearGradient(0, 0, state.width, state.height);
    gradient.addColorStop(0, "rgba(255, 43, 189, 0.26)");
    gradient.addColorStop(0.45, "rgba(36, 246, 255, 0.12)");
    gradient.addColorStop(1, "rgba(202, 255, 46, 0.2)");
    context.fillStyle = gradient;
    context.fillRect(0, 0, state.width, state.height);

    drawLasers(time);
    drawTunnel(time);
    drawSpectrum(time);
    drawNoise(time);

    if (!state.reduced) {
      state.animationFrame = window.requestAnimationFrame(draw);
    }
  };

  const start = () => {
    window.cancelAnimationFrame(state.animationFrame);
    draw(performance.now());
  };

  window.addEventListener("resize", resize, { passive: true });
  window.addEventListener(
    "pointermove",
    (event) => {
      state.pointerX = event.clientX / Math.max(1, state.width) - 0.5;
      state.pointerY = event.clientY / Math.max(1, state.height) - 0.5;
    },
    { passive: true }
  );

  reducedMotionQuery.addEventListener("change", (event) => {
    state.reduced = event.matches;
    start();
  });

  resize();
}
