#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSET_DIR="$ROOT_DIR/docs/assets"
FRAME_DIR="$ASSET_DIR/.demo_frames"
TOTAL_FRAMES=72

mkdir -p "$FRAME_DIR"
rm -f "$FRAME_DIR"/frame-*.png "$ASSET_DIR/demo.gif" "$ASSET_DIR/demo-poster.png"

for i in $(seq 0 $((TOTAL_FRAMES - 1))); do
  if (( i < 24 )); then
    bg_from="#081022"
    bg_to="#1a3e7a"
    scene_a="#88f2ff"
    scene_b="#2e3f69"
    scene_c="#2e3f69"
  elif (( i < 48 )); then
    bg_from="#1a0a20"
    bg_to="#6d225f"
    scene_a="#3a2e4b"
    scene_b="#d9a0ff"
    scene_c="#3a2e4b"
  else
    bg_from="#071a12"
    bg_to="#1b7054"
    scene_a="#2b4c40"
    scene_b="#2b4c40"
    scene_c="#87ffcb"
  fi

  draw_cmd="fill #0a1425aa rectangle 24,18 936,522 "
  draw_cmd+="fill ${scene_a} circle 58,56 70,56 fill ${scene_b} circle 94,56 106,56 fill ${scene_c} circle 130,56 142,56 "
  for b in $(seq 0 13); do
    phase=$(((i * 11 + b * 23) % 240))
    if (( phase > 120 )); then
      amp=$((240 - phase))
    else
      amp=$phase
    fi

    height=$((45 + amp * 2))
    x1=$((52 + b * 61))
    x2=$((x1 + 40))
    y2=472
    y1=$((y2 - height))

    case $((b % 3)) in
      0) color="#74e9ff" ;;
      1) color="#9b8dff" ;;
      *) color="#7af7b2" ;;
    esac

    draw_cmd+="fill ${color} roundrectangle ${x1},${y1} ${x2},${y2} 7,7 "
  done

  if (( i % 8 == 0 )); then
    draw_cmd+="fill #ffffff66 circle 784,142 844,142 "
  else
    draw_cmd+="fill #ffffff2a circle 784,142 816,142 "
  fi

  magick \
    -size 960x540 "gradient:${bg_from}-${bg_to}" \
    -draw "$draw_cmd" \
    "$FRAME_DIR/frame-$(printf '%03d' "$i").png"
done

magick -delay 7 -loop 0 "$FRAME_DIR"/frame-*.png "$ASSET_DIR/demo.gif"
cp "$FRAME_DIR/frame-036.png" "$ASSET_DIR/demo-poster.png"
rm -rf "$FRAME_DIR"

echo "Generated:"
echo "  - $ASSET_DIR/demo.gif"
echo "  - $ASSET_DIR/demo-poster.png"
