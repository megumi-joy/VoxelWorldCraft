#!/bin/bash
# Minecraft world importer, pipeline step 2+3: parse a real Anvil (.mca)
# region file and map it to VoxelWorldCraft block ids, in one podman
# container (Python is blocked on the host -- see repo CLAUDE.md/rails).
#
# Step 1 (GET a world) is deliberately NOT automated here: RAILS say don't
# commit downloaded world files, and a small real-world .mca fixture is easy
# to fetch by hand (this prototype used
# github.com/MestreLion/mcworldlib/blob/main/data/New%20World/region/r.0.0.mca
# -- a real saved Minecraft 1.18-era world, ~1.3MB, fetched via the GitHub
# blobs API since it's not tracked with Git LFS). Point REGION_FILE at
# whatever .mca you have; a single region file (a handful of chunks) is
# enough for this prototype -- see the default --chunk-x1/--chunk-z1 bound
# below.
#
# Step 4 (LOAD into the engine + render) is tools/mc_import/render_import.sh.
#
# Usage:
#   REGION_FILE=/path/to/r.0.0.mca OUT_DIR=/path/to/output \
#     tools/mc_import/run_import.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGION_FILE="${REGION_FILE:?set REGION_FILE=/path/to/some.mca}"
OUT_DIR="${OUT_DIR:?set OUT_DIR=/path/to/output/dir}"
GAP_MD_OUT="${GAP_MD_OUT:-$OUT_DIR/block_gap_list.md}"
CHUNK_X0="${CHUNK_X0:-0}"; CHUNK_Z0="${CHUNK_Z0:-0}"
CHUNK_X1="${CHUNK_X1:-3}"; CHUNK_Z1="${CHUNK_Z1:-3}"

mkdir -p "$OUT_DIR"
REGION_DIR="$(cd "$(dirname "$REGION_FILE")" && pwd)"
REGION_NAME="$(basename "$REGION_FILE")"

podman run --rm \
  -v "$SCRIPT_DIR":/tools:Z \
  -v "$REGION_DIR":/region_in:ro,Z \
  -v "$OUT_DIR":/output:Z \
  -w /tools \
  docker.io/library/python:3.12-slim \
  bash -c "
    set -euo pipefail
    pip install --quiet -r requirements.txt
    python3 parse_and_map.py \
      --region /region_in/$REGION_NAME \
      --chunk-x0 $CHUNK_X0 --chunk-z0 $CHUNK_Z0 \
      --chunk-x1 $CHUNK_X1 --chunk-z1 $CHUNK_Z1 \
      --out-json /output/converted_blocks.json \
      --out-stats /output/import_stats.json \
      --out-gap-md /output/block_gap_list.md
  "

echo "Wrote: $OUT_DIR/converted_blocks.json, $OUT_DIR/import_stats.json, $OUT_DIR/block_gap_list.md"
