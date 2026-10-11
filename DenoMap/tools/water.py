"""Where the water is, for the 4K minimap.

The game paints terrain water (sea, lakes, rivers) onto its own minimap; the tile files
have those areas nearly black. With the game's terrain switched off that paint is gone,
so the addon lays its own water layer over the tiles. This tool makes that layer's masks.

The source is the terrain data of the local test server (the .map files its extractor
cut from the same game files): ground height on a 129 x 129 grid per tile, and the water
level with a water / no water flag per chunk. Water depth = level - ground.

    py -3 water.py depth WORLD COLUMN ROW out.png     one tile's depth as a picture (for checks)
    py -3 water.py build                              Minimap/<world>/w/<tile>.blp and Water.lua

What the game does was measured in game on 2026-10-11 (Stormwind harbour and the lake at the
gates, night and midday; Booty Bay, Loch Modan, Auberdine, Ratchet, Theramore by day): in
water the dark of the tile becomes one flat colour, while what stands in the water (piers,
bridges, ships) keeps the tile's own colour, and shallows keep the tile's colour too. The
game does that only in the tile the player stands in: the next tile's sea stays black, with
a straight edge between them. The addon paints every tile alike. So the mask is "clear
water of some depth here" times "the tile is dark here". A tile that is water all over
needs no file.
"""
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image

MAPS = Path(r"C:\Users\Deniz\Desktop\WoW\ForeverRepack\data\maps")

NO_HEIGHT, AS_INT16, AS_INT8 = 0x1, 0x2, 0x4
LIQ_NO_TYPE, LIQ_NO_HEIGHT = 0x1, 0x2
WATER, OCEAN, MAGMA, SLIME, DARK = 0x01, 0x02, 0x04, 0x08, 0x10


def tile(world, column, row):
    """(depth, kind, entry) for one tile, each 129 x 129, picture orientation (north up, west left).

    depth is in yards, 0 where there is no water; kind holds the chunk's liquid flags and
    entry its liquid type (a row of the game's LiquidType table).
    None when the server has no file for the tile."""
    path = MAPS / f"{world:04d}_{row:02d}_{column:02d}.map"
    if not path.exists():
        return None
    data = path.read_bytes()
    (_, _, _, _, _, height_at, _, liquid_at, _, _, _) = struct.unpack_from("<4s10I", data, 0)

    ground = np.zeros((129, 129), np.float32)
    if height_at:
        _, flags, low, high = struct.unpack_from("<4sIff", data, height_at)
        at = height_at + 16
        if flags & NO_HEIGHT:
            ground[:] = low
        elif flags & AS_INT16:
            ground = low + np.frombuffer(data, "<u2", 129 * 129, at).reshape(129, 129) * ((high - low) / 65535)
        elif flags & AS_INT8:
            ground = low + np.frombuffer(data, "u1", 129 * 129, at).reshape(129, 129) * ((high - low) / 255)
        else:
            ground = np.frombuffer(data, "<f4", 129 * 129, at).reshape(129, 129)

    depth = np.zeros((129, 129), np.float32)
    kind = np.zeros((129, 129), np.uint8)
    entry = np.zeros((129, 129), np.uint16)
    if not liquid_at:
        return depth, kind, entry
    _, flags, global_kind, global_entry, off_x, off_y, width, height, level = struct.unpack_from("<4sBBHBBBBf", data, liquid_at)
    at = liquid_at + 16
    if flags & LIQ_NO_TYPE:
        kind[:] = global_kind
        entry[:] = global_entry
    else:
        entries = np.frombuffer(data, "<u2", 16 * 16, at).reshape(16, 16)
        entry[:128, :128] = np.kron(entries, np.ones((8, 8), np.uint16))
        entry[128, :], entry[:, 128] = entry[127, :], entry[:, 127]
        at += 16 * 16 * 2
        chunks = np.frombuffer(data, "u1", 16 * 16, at).reshape(16, 16)
        at += 16 * 16
        kind[:128, :128] = np.kron(chunks, np.ones((8, 8), np.uint8))
        kind[128, :], kind[:, 128] = kind[127, :], kind[:, 127]
    surface = np.full((129, 129), -1e9, np.float32)
    if flags & LIQ_NO_HEIGHT:
        surface[:] = level
    else:
        levels = np.frombuffer(data, "<f4", width * height, at).reshape(height, width)
        surface[off_y:off_y + height, off_x:off_x + width] = levels[:129 - off_y, :129 - off_x]
    depth = np.where(kind != 0, np.maximum(surface - ground, 0), 0).astype(np.float32)
    return depth, kind, entry


ADDON = Path(__file__).resolve().parent.parent
SIDE = 512                 # the mask's side: the size of the game's own tile
DARK, LIGHT = 78, 110      # red + green + blue of the tile file: all water below, none above
ALL, NONE = 0.985, 0.02    # a mask this full is "water all over", this empty is no water
SHALLOW, DEEP = 1.0, 5.0   # yards of water: none of the colour above the first, all of it below the second
# The liquid types that are clear water (LiquidType table, build 70291): sea, lakes, rivers,
# canals, springs. Swamps, puddles, hot springs, tar, fel, slime and lava keep the tile's own look.
CLEAR = {1, 2, 5, 6, 9, 10, 13, 14, 17, 1235, 1237, 1240, 1250, 1251, 1279, 1287, 1288, 1290, 1296,
         1307, 1319, 1320, 1324, 1325, 1337, 1343, 1344, 1350}


def mask(world, column, row):
    """The water mask of one tile, SIDE x SIDE, 0..1. None when there is no water."""
    got = tile(world, column, row)
    if got is None:
        return None
    depth, kind, entry = got
    wet = np.where(np.isin(entry, list(CLEAR)), np.clip((depth - SHALLOW) / (DEEP - SHALLOW), 0, 1), 0)
    if wet.max() <= 0:
        return None
    wet = np.asarray(Image.fromarray((wet * 255).astype(np.uint8)).resize((SIDE + 4, SIDE + 4), Image.BILINEAR)
                     .crop((2, 2, SIDE + 2, SIDE + 2)), np.float32) / 255
    art = Image.open(ADDON / "Minimap" / str(world) / "q" / f"{column}_{row}.blp").convert("RGB")
    total = np.asarray(art.resize((SIDE, SIDE), Image.BILINEAR), np.float32).sum(2)
    dark = np.clip((LIGHT - total) / (LIGHT - DARK), 0, 1)
    return wet * dark * dark * (3 - 2 * dark)


def build():
    from up import write_blp
    worlds = sorted(int(f.name) for f in (ADDON / "Minimap").iterdir() if f.name.isdigit())
    lines = ["-- Generated by tools/water.py: where the minimap tiles have water.",
             "-- 1 = a mask in Minimap/<world>/w/<tile>.blp, 2 = water all over (no file).",
             "local ADDON, ns = ...", "", "ns.minimapWater = {"]
    for world in worlds:
        folder = ADDON / "Minimap" / str(world)
        out = folder / "w"
        out.mkdir(exist_ok=True)
        for old in out.glob("*.blp"):
            old.unlink()
        entries, files, full = [], 0, 0
        for src in sorted((folder / "q").glob("*.blp")):
            column, row = (int(n) for n in src.stem.split("_"))
            m = mask(world, column, row)
            if m is None or m.max() < NONE:
                continue
            if m.min() > ALL:
                entries.append(f'["{src.stem}"] = 2')
                full += 1
                continue
            rgba = np.full((SIDE, SIDE, 4), 255, np.uint8)
            rgba[..., 3] = np.rint(m * 255)
            write_blp(str(out / f"{src.stem}.blp"), rgba, True)
            entries.append(f'["{src.stem}"] = 1')
            files += 1
        lines.append(f"    [{world}] = {{")
        for i in range(0, len(entries), 8):
            lines.append("        " + ", ".join(entries[i:i + 8]) + ",")
        lines.append("    },")
        print(f"world {world}: {files} masks, {full} tiles of water all over")
    lines.append("}")
    (ADDON / "Water.lua").write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    if sys.argv[1] == "build":
        build()
        sys.exit(0)
    if sys.argv[1] == "depth":
        world, column, row = int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
        got = tile(world, column, row)
        if got is None:
            sys.exit("no map file for that tile")
        depth, kind, entry = got
        print("water share %.2f, depth max %.1f yd, liquid kinds %s" % ((depth > 0).mean(), depth.max(), sorted(set(kind.flatten()))))
        Image.fromarray(np.clip(depth * 8, 0, 255).astype(np.uint8)).resize((512, 512), Image.BILINEAR).save(sys.argv[5])
