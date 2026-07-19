#!/bin/bash
# Headless boot-and-quit smoke test: runs the given scene (default: World.tscn
# directly, so autoloads + World.gd's own player-spawn path both execute) for
# a short time under Xvfb + software Vulkan, then greps stderr/stdout for
# script/parse errors. Not a full gameplay test -- just proves the project
# (and any new autoloads) load without crashing.
set -euo pipefail
SCENE="${1:-res://Scenes/World.tscn}"
FRAMES="${2:-90}"
EXTRA_ARGS=("${@:3}")

Xvfb :99 -screen 0 1280x720x24 &
XVFB_PID=$!
for _ in $(seq 1 50); do
  [ -e /tmp/.X11-unix/X99 ] && break
  sleep 0.2
done
export DISPLAY=:99

godot --path /workspace --rendering-driver vulkan --audio-driver Dummy \
  --resolution 480x270 --write-movie /output/verify.avi --fixed-fps 30 \
  --quit-after "$FRAMES" "$SCENE" "${EXTRA_ARGS[@]}" \
  > /output/verify_log.txt 2>&1
EXIT_CODE=$?
kill "$XVFB_PID" 2>/dev/null || true
exit "$EXIT_CODE"
