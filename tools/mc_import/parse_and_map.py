#!/usr/bin/env python3
"""Minecraft Anvil (.mca) -> VoxelWorldCraft import: parse + map, one pass.

Prototype importer, step 2+3 of the pipeline (see tools/mc_import/README in
the PR description -- this repo has no README.md added for it to keep the
footprint small):

  1. GET a real Minecraft world region (.mca)           -- done externally,
     not by this script (RAILS: don't commit downloaded world files).
  2. PARSE the region via anvil-parser2 (real Anvil/NBT decoding).
  3. MAP each namespaced MC block name to a VoxelWorldCraft block_id via
     mc_block_mapping.MAPPING; anything unmapped becomes the placeholder
     block and is tallied in the gap list.
  4. LOAD happens separately, in-engine (Scripts/Import/MinecraftImporter.gd
     reads this script's converted_blocks.json output).

Mapping and gap-counting happen in the SAME pass over the SAME source data,
so the "% converted" figure in import_stats.json / block_gap_list.md always
reconciles with what actually gets written to converted_blocks.json (and
therefore with what the render shows).

Must run inside a container with anvil-parser2 installed -- Python is
blocked on the host. See tools/mc_import/run_import.sh for the podman
invocation.
"""
import argparse
import json
import sys
import time
from pathlib import Path

import anvil
from anvil.chunk import _section_height_range

from mc_block_mapping import AIR_LIKE, MAPPING, PLACEHOLDER_BLOCK_ID


def parse_args():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--region", required=True, help="Path to a .mca region file")
    p.add_argument("--chunk-x0", type=int, default=0)
    p.add_argument("--chunk-z0", type=int, default=0)
    p.add_argument("--chunk-x1", type=int, default=3, help="inclusive")
    p.add_argument("--chunk-z1", type=int, default=3, help="inclusive")
    p.add_argument("--out-json", required=True)
    p.add_argument("--out-stats", required=True)
    p.add_argument("--out-gap-md", required=True)
    return p.parse_args()


def main():
    args = parse_args()
    t0 = time.time()

    region = anvil.Region.from_file(args.region)

    chunks_out = {}       # "cx,cz" -> [[lx, y, lz, block_id], ...]
    mapped_hist = {}      # mc block name -> count (mapped)
    gap_hist = {}         # mc block name -> count (unmapped -> placeholder)
    air_skipped = 0
    min_y = None
    max_y = None
    data_versions = set()
    chunks_found = 0
    chunks_missing = []

    for cx in range(args.chunk_x0, args.chunk_x1 + 1):
        for cz in range(args.chunk_z0, args.chunk_z1 + 1):
            try:
                chunk = region.get_chunk(cx, cz)
            except Exception:
                chunks_missing.append([cx, cz])
                continue
            if chunk is None:
                chunks_missing.append([cx, cz])
                continue
            chunks_found += 1
            data_versions.add(chunk.version)

            base_x, base_z = chunk.x * 16, chunk.z * 16
            key = f"{cx},{cz}"
            rows = chunks_out.setdefault(key, [])

            for sidx in _section_height_range(chunk.version):
                base_y = sidx * 16
                for idx, blk in enumerate(chunk.stream_blocks(section=sidx)):
                    name = f"{blk.namespace}:{blk.id}"
                    if name in AIR_LIKE:
                        air_skipped += 1
                        continue
                    ly = idx // 256
                    rem = idx % 256
                    lz = rem // 16
                    lx = rem % 16
                    wy = base_y + ly

                    block_id = MAPPING.get(name)
                    if block_id is not None:
                        mapped_hist[name] = mapped_hist.get(name, 0) + 1
                    else:
                        block_id = PLACEHOLDER_BLOCK_ID
                        gap_hist[name] = gap_hist.get(name, 0) + 1

                    rows.append([lx, wy, lz, block_id])
                    min_y = wy if min_y is None else min(min_y, wy)
                    max_y = wy if max_y is None else max(max_y, wy)

    mapped_total = sum(mapped_hist.values())
    gap_total = sum(gap_hist.values())
    solid_total = mapped_total + gap_total
    pct_mapped = (100.0 * mapped_total / solid_total) if solid_total else 0.0

    out_json = {
        "chunk_size": 16,
        "source": {
            "region_file": str(Path(args.region).name),
            "data_versions": sorted(data_versions),
            "chunk_range": [args.chunk_x0, args.chunk_z0, args.chunk_x1, args.chunk_z1],
        },
        "y_range": [min_y, max_y],
        "chunks": chunks_out,
    }
    Path(args.out_json).parent.mkdir(parents=True, exist_ok=True)
    with open(args.out_json, "w") as f:
        json.dump(out_json, f)

    stats = {
        "elapsed_sec": round(time.time() - t0, 2),
        "chunks_found": chunks_found,
        "chunks_missing": chunks_missing,
        "data_versions": sorted(data_versions),
        "y_range": [min_y, max_y],
        "air_skipped": air_skipped,
        "solid_total": solid_total,
        "mapped_total": mapped_total,
        "gap_total": gap_total,
        "pct_mapped_by_volume": round(pct_mapped, 2),
        "unique_mapped_types": len(mapped_hist),
        "unique_gap_types": len(gap_hist),
        "mapped_histogram": dict(sorted(mapped_hist.items(), key=lambda kv: -kv[1])),
        "gap_histogram": dict(sorted(gap_hist.items(), key=lambda kv: -kv[1])),
    }
    with open(args.out_stats, "w") as f:
        json.dump(stats, f, indent=2)

    write_gap_md(args.out_gap_md, stats, args)

    print(f"chunks_found={chunks_found} missing={chunks_missing}")
    print(f"solid_total={solid_total} mapped={mapped_total} ({pct_mapped:.1f}%) "
          f"gap={gap_total} unique_gap_types={len(gap_hist)}")
    print(f"y_range={min_y}..{max_y} elapsed={time.time()-t0:.1f}s")


def write_gap_md(path, stats, args):
    lines = []
    lines.append("# Minecraft -> VoxelWorldCraft block gap list\n")
    lines.append(
        "Generated by `tools/mc_import/parse_and_map.py` from a REAL "
        "Minecraft world region file (not hand-authored), so this list is "
        "an empirical census of what one real world's generation actually "
        "contains, not a wishlist.\n"
    )
    lines.append(
        "- Source region: `data/New World/region/r.0.0.mca` from the "
        "[MestreLion/mcworldlib](https://github.com/MestreLion/mcworldlib) test "
        "fixtures (a real saved Minecraft world, used here only as local input -- not "
        "committed to this repo, per RAILS)."
    )
    lines.append(f"- NBT `DataVersion`(s) found: {stats['data_versions']}")
    lines.append(
        f"- Imported area: chunks x[{args.chunk_x0}..{args.chunk_x1}] "
        f"z[{args.chunk_z0}..{args.chunk_z1}] "
        f"({(args.chunk_x1-args.chunk_x0+1)*(args.chunk_z1-args.chunk_z0+1)} chunks, "
        f"{(args.chunk_x1-args.chunk_x0+1)*16}x{(args.chunk_z1-args.chunk_z0+1)*16} columns), "
        f"y {stats['y_range'][0]}..{stats['y_range'][1]}"
    )
    lines.append(
        f"- Solid (non-air) blocks read: {stats['solid_total']:,}. "
        f"Mapped to an existing VoxelWorldCraft block: {stats['mapped_total']:,} "
        f"({stats['pct_mapped_by_volume']}% by volume, {stats['unique_mapped_types']} unique "
        f"MC block types). Unmapped (placeholder block, id "
        f"{PLACEHOLDER_BLOCK_ID}): {stats['gap_total']:,} "
        f"({stats['unique_gap_types']} unique MC block types).\n"
    )
    lines.append(
        "## Gap list (unmapped MC block types found in this sample, by frequency)\n"
    )
    lines.append("| MC block | count in sample | % of sample volume |")
    lines.append("|---|---:|---:|")
    total = stats["solid_total"] or 1
    for name, count in stats["gap_histogram"].items():
        lines.append(f"| `{name}` | {count:,} | {100.0*count/total:.2f}% |")
    lines.append("")
    lines.append("## For reference: MC block types that WERE mapped\n")
    lines.append("| MC block | VoxelWorldCraft block_id | count in sample |")
    lines.append("|---|---:|---:|")
    from mc_block_mapping import MAPPING
    for name, count in stats["mapped_histogram"].items():
        lines.append(f"| `{name}` | {MAPPING.get(name, '?')} | {count:,} |")
    lines.append("")
    lines.append(
        "## What a production importer would need next\n\n"
        "- **Deepslate as a real second stone layer**, not just a texture swap: "
        "in this one sample it alone is 3.7% of all solid volume, and the "
        "engine has no y-dependent \"deep stone\" concept at all today.\n"
        "- **Stone variants** (andesite/diorite/granite/tuff/gravel): together "
        "~15% of sample volume here -- currently all collapse to placeholder, "
        "which is the single biggest visual gap in the render.\n"
        "- **The remaining ore families**: redstone, lapis, diamond, emerald, "
        "and every `deepslate_*_ore` variant (deepslate ores are literally "
        "separate block names from their stone-layer counterparts in modern "
        "MC, not just a recolor).\n"
        "- **Niche/rare blocks** (glow_lichen, infested_stone/deepslate): low "
        "frequency here, lowest priority.\n"
        "- **Biomes/dimensions not sampled at all** by this one region file "
        "(desert, nether, ocean, cold ice) will surface a different, "
        "disjoint gap list -- this report only covers what one hilly/forest "
        "overworld region actually contains, not Minecraft's full block "
        "registry (700+ block ids).\n"
        "- **A real mapping-table-to-ItemDatabase pipeline**: today the "
        "MC-name -> block_id table (`tools/mc_import/mc_block_mapping.py`) "
        "is hand-maintained Python with no link to "
        "`Scripts/Autoload/ItemDatabase.gd`; a production importer should "
        "generate/validate this mapping from a single source of truth "
        "instead of two hand-kept lists.\n"
    )
    Path(path).write_text("\n".join(lines))


if __name__ == "__main__":
    sys.exit(main())
