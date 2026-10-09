"""Upscale every map art and discovery overlay 4x and write Maps/<fileDataID>.blp."""
import os, sys, time, numpy as np
from PIL import Image
from up import *
MODEL = 'models/RealESRGAN_x4plus.pth'   # from github.com/xinntao/Real-ESRGAN releases
OUT = '../Maps'
os.makedirs(OUT, exist_ok=True)
S = 4

def pow2(n):
    p = 16
    while p < n: p *= 2
    return p

def emit(big, tiles, w, h, alpha):
    """big: upscaled HxWx4 of the w x h source. One output file per source tile."""
    for r, c, fid in tiles:
        tw = 256 if (c + 1) * 256 <= w else pow2(w - c * 256)
        th = 256 if (r + 1) * 256 <= h else pow2(h - r * 256)
        piece = big[r * 256 * S:(r * 256 + th) * S, c * 256 * S:(c * 256 + tw) * S]
        ph, pw = th * S - piece.shape[0], tw * S - piece.shape[1]
        if ph or pw: piece = np.pad(piece, ((0, ph), (0, pw), (0, 0)), mode='edge')
        write_blp(f'{OUT}/{fid}.blp', np.ascontiguousarray(piece), alpha)

def done(tiles): return all(os.path.exists(f'{OUT}/{f}.blp') for _, _, f in tiles)

only = sys.argv[1:]
t0 = time.time(); n = 0
for art, a in JOBS.items():
    if only and art not in only: continue
    if not done(a['tiles']):
        src = np.asarray(stitch(a['tiles']).convert('RGB'))
        up = upscale_rgb(src, MODEL)
        big = np.dstack([up, np.full(up.shape[:2], 255, np.uint8)])
        emit(big, a['tiles'], src.shape[1], src.shape[0], False)
    for oid, o in a['overlays'].items():
        if done(o['tiles']): continue
        full = np.asarray(stitch(o['tiles']))
        h, w = min(o['h'], full.shape[0]), min(o['w'], full.shape[1])
        src = np.ascontiguousarray(full[:h, :w])
        rgb = upscale_rgb(bleed(src), MODEL)
        al = np.asarray(Image.fromarray(src[..., 3]).resize((w * S, h * S), Image.BICUBIC))
        emit(np.dstack([rgb, al]), o['tiles'], w, h, True)
    n += 1
    print(f'{n}/{len(JOBS)} art {art} {a["maps"][0][1]} {round(time.time() - t0)}s', flush=True)
print('DONE', flush=True)
