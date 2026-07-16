#!/usr/bin/env python3
"""Extract frames across the whole clip and measure frame-to-frame pixel diff
to objectively confirm real motion (vs a frozen/static output)."""
import subprocess, sys, os, glob, shutil
import numpy as np
from PIL import Image

video = sys.argv[1]
outdir = sys.argv[2]
sample_fps = float(sys.argv[3]) if len(sys.argv) > 3 else 2.0

if os.path.exists(outdir):
    shutil.rmtree(outdir)
os.makedirs(outdir)

# Extract frames sampled evenly across the whole clip (not just the start).
subprocess.run([
    "ffmpeg", "-y", "-i", video,
    "-vf", f"fps={sample_fps}",
    os.path.join(outdir, "f_%04d.png")
], check=True, capture_output=True)

frames = sorted(glob.glob(os.path.join(outdir, "f_*.png")))
print(f"Extracted {len(frames)} sampled frames at {sample_fps} fps")

diffs = []
prev = None
for f in frames:
    img = np.asarray(Image.open(f).convert("RGB"), dtype=np.int16)
    if prev is not None:
        d = np.abs(img - prev).mean()
        diffs.append(d)
    prev = img

print(f"n_pairs={len(diffs)}")
for i, d in enumerate(diffs):
    t0 = i / sample_fps
    t1 = (i + 1) / sample_fps
    print(f"  t={t0:5.1f}s->{t1:5.1f}s  mean_abs_pixel_diff={d:6.3f}")

if diffs:
    arr = np.array(diffs)
    print(f"OVERALL: mean={arr.mean():.3f} max={arr.max():.3f} min={arr.min():.3f} "
          f"n_significant(>1.0)={int((arr>1.0).sum())}/{len(arr)}")
