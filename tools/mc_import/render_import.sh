#!/bin/bash
# Minecraft world importer, pipeline step 4: LOAD converted_blocks.json (from
# run_import.sh) into the actual Godot engine via Chunk.setup_import() /
# Scripts/Import/MCImportView.gd, and render it headlessly to a PNG (+ a
# short MP4 clip) for visual verification. Reuses the project's existing
# proven Xvfb/Movie-Maker recipe (tools/record_movie_maker.sh) rather than
# inventing a second screenshot mechanism -- see that script's header for
# why Movie Maker mode (not a plain screen capture) is used under llvmpipe,
# and for the one-time `localhost/godot-xvfb:4.3` image build. This script
# additionally needs ffmpeg in the image (`localhost/godot-xvfb-ffmpeg:4.3`,
# built the same way with `ffmpeg` added to the `apt-get install` line).
#
# Usage (run on the host; this script does the podman invocations itself):
#   PROJECT_DIR=/path/to/voxel-mcimport \
#   IMPORT_JSON_DIR=/path/to/output \
#   DELIVER_DIR=/home/yip/games-video-out/mc_import \
#     tools/mc_import/render_import.sh [frames] [WxH]
set -euo pipefail

FRAMES="${1:-30}"
RES="${2:-960x540}"
PROJECT_DIR="${PROJECT_DIR:?set PROJECT_DIR=/path/to/voxel-mcimport checkout}"
IMPORT_JSON_DIR="${IMPORT_JSON_DIR:?set IMPORT_JSON_DIR=/path/to/output (from run_import.sh)}"
DELIVER_DIR="${DELIVER_DIR:?set DELIVER_DIR=/path/to/deliverable/dir}"
RENDER_TMP="${RENDER_TMP:-$(mktemp -d)}"

mkdir -p "$DELIVER_DIR" "$RENDER_TMP"

podman run --rm \
  -v "$PROJECT_DIR":/workspace:Z \
  -v "$RENDER_TMP":/output:Z \
  -v "$IMPORT_JSON_DIR":/import:ro,Z \
  --entrypoint bash localhost/godot-xvfb-ffmpeg:4.3 \
  /workspace/tools/record_movie_maker.sh "$FRAMES" /output/mc_import.avi "$RES" \
  res://Scenes/Import/MCImportView.tscn -- --import-json=/import/converted_blocks.json

podman run --rm \
  -v "$RENDER_TMP":/output:Z \
  -v "$DELIVER_DIR":/deliver:Z \
  --entrypoint bash localhost/godot-xvfb-ffmpeg:4.3 -c '
    set -euo pipefail
    ffmpeg -y -i /output/mc_import.avi -vframes 1 -update 1 /deliver/imported_world.png
    ffmpeg -y -i /output/mc_import.avi -vf "scale='"'"'min(720,iw)'"'"':'"'"'-2'"'"'" \
      -c:v libx264 -pix_fmt yuv420p -movflags +faststart /deliver/imported_world.mp4
  '

echo "Wrote: $DELIVER_DIR/imported_world.png, $DELIVER_DIR/imported_world.mp4"
