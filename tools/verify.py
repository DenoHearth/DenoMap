"""Check every Maps/*.blp is complete (header offsets match the file size). --fix deletes bad ones."""
import os, struct, sys
D = '../Maps'
bad = 0; n = 0
for fn in os.listdir(D):
    p = D + '/' + fn
    if not fn.endswith('.blp'):
        if '--fix' in sys.argv: os.remove(p)
        continue
    n += 1
    b = open(p, 'rb').read(148)
    ok = len(b) == 148 and b[:4] == b'BLP2'
    if ok:
        offs = struct.unpack('<16I', b[20:84]); sizes = struct.unpack('<16I', b[84:148])
        end = max(o + s for o, s in zip(offs, sizes))
        ok = end == os.path.getsize(p) and sizes[0] > 0
    if not ok:
        bad += 1; print('BAD', fn)
        if '--fix' in sys.argv: os.remove(p)
print('files', n, 'bad', bad)
