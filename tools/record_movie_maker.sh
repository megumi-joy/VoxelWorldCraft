#!/bin/bash
# Records gameplay video via Godot's Movie Maker mode, running headless inside
# podman with a virtual display. Movie Maker renders every frame fully at a
# FIXED target fps (--fixed-fps) regardless of how slow the underlying
# renderer is, so the output is always smooth even on software rendering
# (llvmpipe) -- unlike a plain screen capture, which would show real wall-clock
# render speed (choppy under swiftshader/llvmpipe).
#
# One-time setup (build the xvfb-enabled Godot image; barichello/godot-ci:4.3
# has no Xvfb):
#   cat > /tmp/Dockerfile.xvfb <<'EOF'
#   FROM docker.io/barichello/godot-ci:4.3
#   RUN apt-get update && apt-get install -y --no-install-recommends xvfb \
#       && rm -rf /var/lib/apt/lists/*
#   EOF
#   podman build -t localhost/godot-xvfb:4.3 -f /tmp/Dockerfile.xvfb /tmp
#
# Usage (run inside the container, project mounted at /workspace, output dir
# mounted at /output):
#   podman run --rm \
#     -v /path/to/project:/workspace:Z \
#     -v /path/to/output/dir:/output:Z \
#     --entrypoint bash localhost/godot-xvfb:4.3 \
#     /workspace/tools/render_gameplay_movie.sh <frames> <out.avi> <WxH> [scene] [-- extra args]
#
# Then convert AVI -> compact MP4 (H.264/yuv420p/faststart) on the host:
#   ffmpeg -y -i out.avi -vf "scale='min(720,iw)':'-2'" \
#     -c:v libx264 -pix_fmt yuv420p -movflags +faststart out.mp4
#
# NOTE: the standard `xvfb-run` wrapper HANGS forever in this container (its
# SIGUSR1 readiness handshake never completes). We start Xvfb manually and
# poll for its X11 socket file instead.
#
# Render cost is dominated by output resolution far more than scene
# complexity (llvmpipe is fill-rate bound) -- prefer rendering small (e.g.
# 480x270) and let ffmpeg's `scale` filter do any upscale/fit later, rather
# than rendering large and downscaling.
set -euo pipefail
FRAMES="${1:?frame count required}"
OUT="${2:?output .avi path required}"
RES="${3:-480x270}"
SCENE="${4:-}"   # optional: res://Scenes/Whatever.tscn (defaults to project's run/main_scene)
shift $(( $# < 4 ? $# : 4 )) || true
EXTRA_ARGS=("$@")  # anything after -- is passed through to the running project (OS.get_cmdline_args())

# Xvfb's virtual screen must be at least as large as the requested render
# resolution ($RES) -- an unmanaged (no window manager) X11 window CAN be
# created larger than the root window, but it is safer and correctness-
# proven not to rely on that; size the virtual screen to the render target
# itself (with a floor of 1280x720 for tiny target resolutions).
XVFB_W="${RES%x*}"
XVFB_H="${RES#*x}"
[ "$XVFB_W" -lt 1280 ] && XVFB_W=1280
[ "$XVFB_H" -lt 720 ] && XVFB_H=720
Xvfb :99 -screen 0 "${XVFB_W}x${XVFB_H}x24" &
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

GODOT_ARGS=(--path /workspace --rendering-driver opengl3 --audio-driver Dummy
            --resolution "$RES" --write-movie "$OUT" --fixed-fps 60
            --quit-after "$FRAMES")
[ -n "$SCENE" ] && GODOT_ARGS+=("$SCENE")

godot "${GODOT_ARGS[@]}" "${EXTRA_ARGS[@]}"
EXIT_CODE=$?
kill "$XVFB_PID" 2>/dev/null || true
exit $EXIT_CODE
