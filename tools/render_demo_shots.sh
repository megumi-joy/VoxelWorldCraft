#!/bin/bash
# Runs a *DemoDriver under Xvfb + software GL inside the godot-xvfb container so
# the driver's get_viewport().get_texture().save_png() path (which is a no-op
# under plain --headless -- no viewport texture) actually produces PNGs for
# owner-facing visual proof. Mirrors record_movie_maker.sh's manual Xvfb setup
# (xvfb-run hangs in this container), but drives screenshots instead of a movie.
#
# Usage (inside container, project at /workspace, output at /output):
#   /workspace/tools/render_demo_shots.sh <frames> <scene> [-- <driver flags>]
# The driver saves its PNGs wherever its --*-shot-dir flag points; pass
# /output there so they land on the host mount, e.g.:
#   render_demo_shots.sh 4000 res://Scenes/World.tscn -- --menus-demo --menus-shot-dir=/output
set -euo pipefail
FRAMES="${1:?frame count required}"
SCENE="${2:-res://Scenes/World.tscn}"
shift $(( $# < 2 ? $# : 2 )) || true
EXTRA_ARGS=("$@")

Xvfb :99 -screen 0 1280x720x24 &
XVFB_PID=$!
for _ in $(seq 1 50); do
  [ -e /tmp/.X11-unix/X99 ] && break
  sleep 0.2
done
if [ ! -e /tmp/.X11-unix/X99 ]; then
  echo "FATAL: Xvfb socket never appeared" >&2
  exit 1
fi
export DISPLAY=:99
export LIBGL_ALWAYS_SOFTWARE=1

godot --path /workspace --rendering-driver opengl3 --audio-driver Dummy \
  --resolution 1280x720 --quit-after "$FRAMES" "$SCENE" "${EXTRA_ARGS[@]}"
EXIT_CODE=$?
kill "$XVFB_PID" 2>/dev/null || true
exit $EXIT_CODE
