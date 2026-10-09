"""After a rebuild: where a regenerated tile looks the same as the published one (the game only
recompressed its source), put the published file back, so only tiles that really changed
are pushed. Compares the full-size pictures; under 1.5 of 255 mean difference counts as the same."""
import os, shutil, struct, numpy as np
NEW = 'C:/Dev/wow-forever-addons/DenoMap/Minimap'
OLD = 'C:/Dev/wow-addons/DenoMap/DenoMap/Minimap'
def top(path):
    """The 512 px level of a DXT1 tile (level 2 of a 2048 tile), decoded with numpy."""
    b = open(path, 'rb').read()
    w, h = struct.unpack('<II', b[12:20])
    lvl = 2 if w >= 2048 else 0
    off = struct.unpack('<16I', b[20:84])[lvl]; w >>= lvl; h >>= lvl
    blk = np.frombuffer(b, np.uint8, (w // 4) * (h // 4) * 8, off).reshape(-1, 8)
    c = blk[:, :4].copy().view('<u2').astype(np.int32)              # two 565 colours per block
    def rgb(v): return np.stack([(v >> 11) * 255 // 31, ((v >> 5) & 63) * 255 // 63, (v & 31) * 255 // 31], -1)
    c0, c1 = rgb(c[:, 0]), rgb(c[:, 1])
    pal = np.stack([c0, c1, (2 * c0 + c1) // 3, (c0 + 2 * c1) // 3], 1)   # opaque tiles: 4-colour mode
    idx = blk[:, 4:].copy().view('<u4')[:, 0]
    sel = (idx[:, None] >> (2 * np.arange(16))[None, :]) & 3
    px = pal[np.arange(len(blk))[:, None], sel]                      # blocks x 16 x 3
    return px.reshape(h // 4, w // 4, 4, 4, 3).transpose(0, 2, 1, 3, 4).reshape(h, w, 3).astype(np.int16)
same = kept = real = new = 0
for dp, _, fn in os.walk(NEW):
    for f in fn:
        if not f.endswith('.blp'): continue
        a = os.path.join(dp, f); b = os.path.join(OLD, os.path.relpath(a, NEW))
        if not os.path.exists(b): new += 1; continue
        if open(a, 'rb').read() == open(b, 'rb').read(): same += 1; continue
        x, y = top(a), top(b)
        if x.shape == y.shape and float(np.abs(x - y).mean()) < 1.5:
            shutil.copy2(b, a); kept += 1
        else:
            real += 1
print('identical', same, '| noise only, published file kept', kept, '| really changed', real, '| new', new)
