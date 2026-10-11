"""Find straight edges in the minimap water: places where two neighbouring tiles disagree.

For every pair of tiles that touch and have water at their shared border (tools/water.py),
the two pixel columns (or rows) that meet are compared in the 1x files. A pair counts when a
run of at least 24 pixels differs by more than 14 of 255 on average.

    py -3 seams.py            list the worst pairs per world and the totals
"""
import sys

import numpy as np
from PIL import Image

import water

ADDON = water.ADDON
RUN, OFF = 24, 14


def strips(world, key):
    """Left, right, top and bottom pixel strips of a tile (1x file, as 512 px) and where its
    border has water."""
    art = np.asarray(Image.open(ADDON / "Minimap" / str(world) / "q" / f"{key}.blp").convert("RGB")
                     .resize((512, 512), Image.BILINEAR), np.float32)
    column, row = (int(n) for n in key.split("_"))
    depth = water.clear_depth(world, column, row) if water.tile(world, column, row) is not None else None
    wet = np.zeros((512, 512), bool) if depth is None else water.spread(depth, 512) > 0.3
    return (art[:, 0], art[:, -1], art[0], art[-1]), (wet[:, 0], wet[:, -1], wet[0], wet[-1])


def worst_run(a, b, wet):
    off = (np.abs(a - b).mean(1) > OFF) & wet
    best = run = 0
    for flag in off:
        run = run + 1 if flag else 0
        best = max(best, run)
    return best


def main():
    total = 0
    for folder in sorted((ADDON / "Minimap").iterdir()):
        if not folder.name.isdigit():
            continue
        world = int(folder.name)
        have = {p.stem for p in (folder / "q").glob("*.blp")}
        cache, found = {}, []

        def get(key):
            if key not in cache:
                cache[key] = strips(world, key)
            return cache[key]

        for key in sorted(have):
            c, r = (int(n) for n in key.split("_"))
            for other, mine, theirs in ((f"{c + 1}_{r}", 1, 0), (f"{c}_{r + 1}", 3, 2)):
                if other not in have:
                    continue
                (a, wa), (b, wb) = get(key), get(other)
                wet = wa[mine] | wb[theirs]
                if not wet.any():
                    continue
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
