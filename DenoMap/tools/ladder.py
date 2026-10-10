"""Deno Map 4K - the resolution ladder.

Every texture of the pack is a BLP with its full chain of smaller copies inside (4x, 2x, 1x ...).
The game picks among those by itself only with the TRILINEAR filter, and then it mixes two of
them, which made the minimap and the maps look soft at normal sizes (measured in game on
2026-10-10: a quarter of the fine detail of the game's own picture). With the LINEAR filter the
picture is crisp, but the game then reads the largest copy only, however small it is drawn.

So the addon picks the copy itself, and for that each smaller copy has to be a file of its own:
    Maps/<id>.blp           4x      Maps/h/<id>.blp  2x      Maps/q/<id>.blp  1x
    Minimap/<w>/<tile>.blp  4x      Minimap/<w>/h/   2x      Minimap/<w>/q/   1x
A smaller file is cut out of the big one byte for byte (the same compressed blocks, no second
compression), so the three always show the same picture.

    py -3 ladder.py            make what is missing or older than its source
    py -3 ladder.py --check    count only
"""
import os, struct, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HEAD = 148 + 1024


def cut(src: bytes, level: int) -> bytes:
    """The BLP that starts at copy number `level` of `src`."""
    magic, typ, enc, alpha_depth, alpha_enc, has_mips, w, h = struct.unpack("<4sIBBBBII", src[:20])
    offs = struct.unpack("<16I", src[20:84])
    sizes = struct.unpack("<16I", src[84:148])
    count = sum(1 for s in sizes if s)
    level = min(level, count - 1)
    chunks = [src[offs[i]:offs[i] + sizes[i]] for i in range(level, count)]
    new_offs, new_sizes, pos = [0] * 16, [0] * 16, HEAD
    for i, c in enumerate(chunks):
        new_offs[i], new_sizes[i] = pos, len(c)
        pos += len(c)
    head = struct.pack("<4sIBBBBII", magic, typ, enc, alpha_depth, alpha_enc, has_mips,
                       max(1, w >> level), max(1, h >> level))
    return head + struct.pack("<16I", *new_offs) + struct.pack("<16I", *new_sizes) + src[148:HEAD] + b"".join(chunks)


def main() -> int:
    check = "--check" in sys.argv
    folders = [ROOT / "Maps"] + sorted(p for p in (ROOT / "Minimap").iterdir() if p.is_dir())
    made = current = 0
    for folder in folders:
        for sub in ("h", "q"):
            (folder / sub).mkdir(exist_ok=True)
        for src in sorted(folder.glob("*.blp")):
            data = None
            for sub, level in (("h", 1), ("q", 2)):
                out = folder / sub / src.name
                if out.is_file() and out.stat().st_mtime >= src.stat().st_mtime:
                    current += 1
                    continue
                made += 1
                if check:
                    continue
                if data is None:
                    data = src.read_bytes()
                tmp = out.with_suffix(".tmp")
                tmp.write_bytes(cut(data, level))
                os.replace(tmp, out)
    print(("to make: " if check else "made: ") + str(made) + ", already current: " + str(current))
    return 0


if __name__ == "__main__":
    sys.exit(main())
