"""Water for the 4K minimap, painted into the tiles themselves.

The game's minimap tile files hold no water: deep water is nearly black in them. The game
paints terrain water onto its minimap itself, and only in the tile the player stands in (the
next tile's sea stays black, with a straight edge). The addon switches the game's terrain
off, so that paint is gone altogether. Measured in game on 2026-10-11 (Stormwind harbour
and the lake at the gates, night and midday; Booty Bay, Loch Modan, Auberdine, Ratchet,
Theramore by day): the game's water is one flat colour, 27 44 53 of 255 by day; what stands
in the water (piers, bridges, ships) and shallows keep the tile's own colour.

    py -3 water.py bake [WORLD ...]   paint the water into every tile that has some (all three sizes)
    py -3 water.py depth WORLD COLUMN ROW out.png     one tile's depth as a picture (for checks)

Run bake with the Python of _work/upvenv (it has the texture compressor).

History: 1.4.0 and 1.4.1 laid a separate 512 px layer of one flat colour over the tiles. He
found that plain next to the game's own, and asked for the 4K detail to stay. A first try at
painting into the tiles had a look of my own making (teal shore colour, ripple, darker open
sea); his rule for this addon is "keep the original art when it comess to anything and just
upscaling to 4k", so 1.5.0 paints the water the way the game does, measured, and nothing else.

The one place it goes beyond the game: the game paints water only in the tile the player
stands in, and not at all far out at sea or off some coasts (Dustwallow, Desolace, Darkshore:
black in the stock game). The same rule is applied to all clear water, so there is no black.
The water colour differs a little from zone to zone in the game (Wetlands and Westfall come
out darker than Stormwind); only the default and the Stranglethorn colour are known and used.

Where the water is comes from the terrain data of the local test server (the .map files its
extractor cut from the same game files): ground height on a 129 x 129 grid per tile, the
water level, and the liquid type per chunk. Depth = level - ground.

The tiles as the upscaler made them are kept in _work/mini/nowater (copied there the first
time a tile is painted); the paint always starts from those, so this can be run again.
"""
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

MAPS = Path(r"C:\Users\Deniz\Desktop\WoW\ForeverRepack\data\maps")

NO_HEIGHT, AS_INT16, AS_INT8 = 0x1, 0x2, 0x4
LIQ_NO_TYPE, LIQ_NO_HEIGHT = 0x1, 0x2


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
PLAIN = ADDON.parent / "_work" / "mini" / "nowater"   # the tiles before any water was painted
DAY = 0.878                # the addon draws a tile at this share of the file by day (Minimap.lua)
FOG_YARDS = 8.0            # the water colour covers 1 - exp(-depth / FOG_YARDS) of the sea bed (measured)
WATER_DAY = np.array([29, 42, 50], np.float32)    # the game's water colour by day, default light (harbour, Ratchet)
WATER_STV = np.array([0, 42, 51], np.float32)     # under the Stranglethorn lights, which carry a water colour of their own
# Light.db2, build 70291: the lights with that colour on Eastern Kingdoms (x, y, falloff start, falloff end)
STV_LIGHTS = ((-13333.3, 0.0, 1771.0, 2005.0), (-14353.0, 488.0, 152.0, 229.0))
BED_AT = [1, 3, 6, 12, 20, 30]            # yards of water ...
BED_LIMIT = [900, 300, 265, 195, 125, 85]   # ... and the brightest a sea bed gets in the art there
SHARP = 2.0                # fine brightness movement (of 255, pixel against its neighbours) from which something counts as sharp
# Alterac Valley and Warsong Gulch: the black around the battleground is not sea, though the
# terrain data has a water level under it. Nothing is painted there.
NO_WATER = {30, 489}
NONE = 0.02                # a tile whose paint never gets above this has no water worth painting
SLOPE = 2.0                # yards the water may get deeper from one grid point (4 yards) to the next
EDGE = 8                   # pixels at a tile border that are judged by their neighbour further in
# The liquid types that are clear water (LiquidType table, build 70291): sea, lakes, rivers,
# canals, springs. Swamps, puddles, hot springs, tar, fel, slime and lava keep the tile's own look.
CLEAR = {1, 2, 5, 6, 9, 10, 13, 14, 17, 1235, 1237, 1240, 1250, 1251, 1279, 1287, 1288, 1290, 1296,
         1307, 1319, 1320, 1324, 1325, 1337, 1343, 1344, 1350}


def clear_depth(world, column, row):
    """Depth of clear water for one tile, 129 x 129, with drop-offs eased.

    Where the terrain simply ends (the open sea off the Darkspear Islands) the depth jumps from
    a few yards to two hundred along a straight line, and the colour with it. So the depth may
    grow by no more than SLOPE yards from one grid point of water to the next. The eight tiles
    around are taken into it, so both sides of a tile border come out the same."""
    wide = np.zeros((3 * 128 + 1, 3 * 128 + 1), np.float32)
    for dr in (-1, 0, 1):
        for dc in (-1, 0, 1):
            got = tile(world, column + dc, row + dr)
            if got is None:
                continue
            depth, kind, entry = got
            part = np.where(np.isin(entry, list(CLEAR)), np.minimum(depth, 60), 0).astype(np.float32)
            y, x = (dr + 1) * 128, (dc + 1) * 128
            wide[y:y + 129, x:x + 129] = np.maximum(wide[y:y + 129, x:x + 129], part)
    if wide[128:257, 128:257].max() <= 0:
        return None
    eased = np.where(wide > 0, wide, np.float32(1e9))    # land does not pull the water beside it up
    for _ in range(2):
        for i in range(1, eased.shape[0]):
            eased[i] = np.minimum(eased[i], eased[i - 1] + SLOPE)
            eased[:, i] = np.minimum(eased[:, i], eased[:, i - 1] + SLOPE)
        for i in range(eased.shape[0] - 2, -1, -1):
            eased[i] = np.minimum(eased[i], eased[i + 1] + SLOPE)
            eased[:, i] = np.minimum(eased[:, i], eased[:, i + 1] + SLOPE)
    return np.where(wide > 0, np.minimum(eased, wide), 0)[128:257, 128:257]


def spread(grid, side):
    """A 129 x 129 grid (samples on the cell corners) as side x side pixels, bilinear."""
    at = (np.arange(side, dtype=np.float32) + 0.5) / side * 128
    low = np.minimum(at.astype(np.int32), 127)
    part = at - low
    rows = grid[low] * (1 - part)[:, None] + grid[low + 1] * part[:, None]
    return rows[:, low] * (1 - part)[None, :] + rows[:, low + 1] * part[None, :]


def paint(world, column, row, art):
    """The tile with its water painted in, the way the game paints it. art: side x side x 3,
    the tile as the upscaler made it. None when the tile has no water worth painting.

    The rule, measured against the game's own minimap at 13 places at midday (2026-10-11,
    _work/mini/watermeasure): seen = art x (1 - cover) + water colour x cover, with
    cover = 1 - exp(-depth / 8 yards). It explains the game's picture to within 2 to 6 of
    255 per place. What stands in the water (piers, bridges, ships) keeps the art."""
    if world in NO_WATER or tile(world, column, row) is None:
        return None
    depth = clear_depth(world, column, row)
    if depth is None:
        return None
    side = art.shape[0]
    depth = spread(depth, side)
    rgb = art.astype(np.float32)
    # The outermost pixels of an upscaled tile can be off (a thin warm or dark line): what they
    # are (sea bed or something standing in the water) is read from the pixels just inside.
    seen = rgb
    if side > 8 * EDGE:
        seen = rgb.copy()
        seen[:EDGE], seen[-EDGE:] = seen[EDGE], seen[-EDGE - 1]
        seen[:, :EDGE], seen[:, -EDGE:] = seen[:, EDGE:EDGE + 1], seen[:, -EDGE - 1:-EDGE]
    red, green, blue = seen[..., 0], seen[..., 1], seen[..., 2]
    total = red + green + blue
    # Things standing in the water: wood (clearly more red than green) and pale stone or sails
    # (bright, with little colour). Everything else under water is sea bed: green, teal, olive,
    # sand, mud, or the black the tile has where it shows nothing.
    wood = np.clip((red - green * 1.2) / (green * 0.2 + 4), 0, 1) * np.clip((total - 60) / 40, 0, 1)
    top, low = np.maximum(np.maximum(red, green), blue), np.minimum(np.minimum(red, green), blue)
    stone = np.clip((total - 300) / 80, 0, 1) * np.clip((0.25 - (top - low) / np.maximum(top, 1)) / 0.08, 0, 1)
    bed = 1 - np.maximum(wood, stone)
    # The game draws its water from above with the real models in the way, so quays, piers and
    # ships hide it. The art gives them away: the deeper the water, the darker the sea bed is in
    # the tile, and what is brighter than a sea bed can be at that depth stands above the water.
    # Measured (red + green + blue of the tile file): nothing of the bed above about 85 under 30
    # yards of water, 125 under 20, 195 under 12, 265 under 6.
    limit = np.interp(depth, BED_AT, BED_LIMIT).astype(np.float32)
    bed = np.minimum(bed, np.clip((limit + 35 - total) / 35, 0, 1))
    # Dark things standing in the water (the grey piers of Menethil) pass both tests above. They
    # show by their make: planks and stones are sharp in the art, a sea bed under yards of water
    # is soft. Sharpness = how much the brightness moves within a few pixels.
    small = max(1, side // 512)
    grey = np.clip(total / 3, 0, 255)
    soft = np.asarray(Image.fromarray(grey.astype(np.uint8)).filter(ImageFilter.BoxBlur(small)), np.float32)
    fine = Image.fromarray(np.clip(np.abs(grey - soft) * 8, 0, 255).astype(np.uint8))
    fine = np.asarray(fine.filter(ImageFilter.BoxBlur(3 * small)), np.float32) / 8
    sharp = np.clip((fine - SHARP) / SHARP, 0, 1) * np.clip((depth - 3) / 3, 0, 1) * np.clip((total - 60) / 40, 0, 1)
    bed = np.minimum(bed, 1 - sharp)
    # Green to teal is sea bed whatever its brightness or make (ridges, weed, the bright
    # shallows): quays, piers and ships are brown, grey or white.
    weed = np.clip((green - red * 1.04) / (red * 0.12 + 4), 0, 1) * np.clip((green - blue * 0.95) / (blue * 0.1 + 3), 0, 1)
    bed = np.maximum(bed, weed * (1 - np.maximum(wood, stone)))
    # The dark gaps between the planks of a pier belong to the pier: holes in what stands above
    # the water are closed (grown, then shrunk back, so its outline stays where it is).
    reach = 2 * max(1, side // 340) + 1
    above = Image.fromarray(np.rint((1 - bed) * 255).astype(np.uint8))
    above = above.filter(ImageFilter.MaxFilter(reach)).filter(ImageFilter.MinFilter(reach))
    bed = np.minimum(bed, 1 - np.asarray(above, np.float32) / 255)
    cover = (1 - np.exp(-depth / FOG_YARDS)) * bed
    if cover.max() < NONE:
        return None
    colour = WATER_DAY
    if world == 0:
        span = (np.arange(side, dtype=np.float32) + 0.5) / side
        wx = (32 - (row + span)) * 533.33333
        wy = (32 - (column + span)) * 533.33333
        near = np.zeros((side, side), np.float32)
        for lx, ly, start, end in STV_LIGHTS:
            dist = np.hypot(wx[:, None] - lx, wy[None, :] - ly)
            near = np.maximum(near, np.clip((end - dist) / (end - start), 0, 1))
        if near.max() > 0:
            colour = WATER_DAY + (WATER_STV - WATER_DAY) * near[..., None]
    # the addon darkens the whole tile (DAY); the colour above is what should be seen
    mixed = rgb * (1 - cover[..., None]) + colour / DAY * cover[..., None]
    return np.clip(np.rint(mixed), 0, 255).astype(np.uint8)


def bake_one(job):
    import shutil
    from ladder import cut
    from up import write_blp
    world, name = job
    folder = ADDON / "Minimap" / str(world)
    target = folder / name
    plain = PLAIN / str(world) / name
    column, row = (int(n) for n in target.stem.split("_"))
    if tile(world, column, row) is None:
        return 0
    if not plain.is_file():
        plain.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(target, plain)
    art = np.asarray(Image.open(plain).convert("RGB"))
    done = paint(world, column, row, art)
    if done is None:
        if target.read_bytes() != plain.read_bytes():      # painted by an earlier run, no water now
            shutil.copy2(plain, target)
            data = target.read_bytes()
            (folder / "h" / name).write_bytes(cut(data, 1))
            (folder / "q" / name).write_bytes(cut(data, 2))
        return 0
    rgba = np.dstack([done, np.full(done.shape[:2], 255, np.uint8)])
    write_blp(str(target), rgba, False)
    data = target.read_bytes()
    (folder / "h" / name).write_bytes(cut(data, 1))
    (folder / "q" / name).write_bytes(cut(data, 2))
    return 1


def bake():
    from multiprocessing import Pool
    jobs = []
    only = set(sys.argv[2:])
    for folder in sorted((ADDON / "Minimap").iterdir()):
        if folder.name.isdigit() and (not only or folder.name in only):
            jobs += [(int(folder.name), src.name) for src in sorted(folder.glob("*.blp"))]
    with Pool(10) as pool:
        painted = sum(pool.imap_unordered(bake_one, jobs, chunksize=8))
    print(f"{painted} of {len(jobs)} tiles have water painted in")


if __name__ == "__main__":
    if sys.argv[1] == "bake":
        bake()
        sys.exit(0)
    if sys.argv[1] == "depth":
        world, column, row = int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
        got = tile(world, column, row)
        if got is None:
            sys.exit("no map file for that tile")
        depth, kind, entry = got
        print("water share %.2f, depth max %.1f yd, liquid types %s" % ((depth > 0).mean(), depth.max(), sorted(set(entry.flatten().tolist()))))
        Image.fromarray(np.clip(depth * 8, 0, 255).astype(np.uint8)).resize((512, 512), Image.BILINEAR).save(sys.argv[5])
