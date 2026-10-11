"""Find straight edges in the minimap water: places where two neighbouring tiles disagree.

For every pair of tiles that touch, the picture the addon draws (tile x day tint, water colour
through the mask) is worked out for the two pixel columns (or rows) that meet, and compared.
A pair counts when a run of at least 24 pixels differs by more than 14 of 255 on average.

    py -3 seams.py            list the worst pairs per world and the totals
"""
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ADDON = Path(__file__).resolve().parent.parent
DAY = 0.878
WATER = np.array([27, 44, 53], np.float32)
RUN, OFF = 24, 14


def kinds():
    out = {}
    world = None
    for line in (ADDON / "Water.lua").read_text(encoding="utf-8").splitlines():
        m = re.match(r"\s*\[(\d+)\] = \{", line)
        if m:
            world = int(m.group(1))
            out[world] = {}
        for key, kind in re.findall(r'\["(\d+_\d+)"\] = (\d)', line):
            out[world][key] = int(kind)
    return out


def edges(world, key, kind):
    """The four border strips of what the addon draws for one tile: left, right, top, bottom."""
    folder = ADDON / "Minimap" / str(world)
    art = np.asarray(Image.open(folder / "q" / f"{key}.blp").convert("RGB").resize((512, 512), Image.BILINEAR), np.float32)
    if kind == 1:
        mask = np.asarray(Image.open(folder / "w" / f"{key}.blp").convert("RGBA"), np.float32)[..., 3:] / 255
    else:
        mask = np.full(art.shape[:2] + (1,), 1.0 if kind == 2 else 0.0, np.float32)
    shown = art * DAY * (1 - mask) + WATER * mask
    return shown[:, 0], shown[:, -1], shown[0], shown[-1], mask[:, 0, 0], mask[:, -1, 0], mask[0, :, 0], mask[-1, :, 0]


def worst_run(a, b, wet):
    off = (np.abs(a - b).mean(1) > OFF) & wet
    best = run = 0
    for flag in off:
        run = run + 1 if flag else 0
        best = max(best, run)
    return best


def main():
    table = kinds()
    total = 0
    for world, tiles in sorted(table.items()):
        have = {p.stem for p in (ADDON / "Minimap" / str(world) / "q").glob("*.blp")}
        cache, found = {}, []

        def strips(key):
            if key not in cache:
                cache[key] = edges(world, key, tiles.get(key, 0))
            return cache[key]

        near = {k for key in tiles for k in [key] + [f"{int(key.split('_')[0]) + dc}_{int(key.split('_')[1]) + dr}"
                                                      for dc, dr in ((-1, 0), (0, -1))]}
        for key in sorted(near & have):
            c, r = (int(n) for n in key.split("_"))
            for other, mine, theirs, wm, wt in ((f"{c + 1}_{r}", 1, 0, 5, 4), (f"{c}_{r + 1}", 3, 2, 7, 6)):
                if other not in have or (key not in tiles and other not in tiles):
                    continue
                a, b = strips(key), strips(other)
                wet = (a[wm] > 0.05) | (b[wt] > 0.05)
                run = worst_run(a[mine], b[theirs], wet)
                if run >= RUN:
                    found.append((run, key, other))
        found.sort(reverse=True)
        total += len(found)
        print(f"world {world}: {len(found)} tile borders with a water edge of {RUN}+ pixels"
              + (": " + ", ".join(f"{a}|{b} ({n})" for n, a, b in found[:8]) if found else ""))
    print("total", total)


if __name__ == "__main__":
    sys.exit(main())
