"""Upscale every minimap tile 2x (4x model, halved) and write Minimap/<map>/<col>_<row>.blp.
Empty ocean tiles are written small: they carry no detail."""
import json, os, sys, time, numpy as np
from PIL import Image
from up import upscale_rgb, write_blp
MODEL = 'models/RealESRGAN_x4plus.pth'
OUT = '../Minimap'
J = json.load(open('mjobs.json'))
PAD = 32
def load(m, c, r):
    f = J[m].get(f'{c}_{r}')
    return Image.open(f'raw/{f}.blp').convert('RGB') if f else None
only = sys.argv[1:]
t0 = time.time(); n = 0
for m, tiles in J.items():
    os.makedirs(f'{OUT}/{m}', exist_ok=True)
    for key in tiles:
        if only and f'{m}:{key}' not in only: continue
        out = f'{OUT}/{m}/{key}.blp'
        if os.path.exists(out): continue
        c, r = map(int, key.split('_'))
        me = load(m, c, r); a = np.asarray(me)
        if a.astype(np.int16).std() < 6:
            small = np.asarray(me.resize((64, 64), Image.LANCZOS).convert('RGBA'))
            write_blp(out, np.ascontiguousarray(small), False)
        else:
            # the tile with a rim of its neighbours, so the upscale has no seam at the edge
            big = Image.new('RGB', (512 + 2 * PAD, 512 + 2 * PAD))
            big.paste(me.resize((512 + 2 * PAD, 512 + 2 * PAD), Image.BILINEAR))     # fallback rim
            for dc in (-1, 0, 1):
                for dr in (-1, 0, 1):
                    nb = me if (dc, dr) == (0, 0) else load(m, c + dc, r + dr)
                    if nb: big.paste(nb, (PAD + dc * 512, PAD + dr * 512))
            up = upscale_rgb(np.asarray(big), MODEL, tile_px=640, pad=0)
            up = up[PAD * 4:PAD * 4 + 2048, PAD * 4:PAD * 4 + 2048]
            half = np.asarray(Image.fromarray(up).resize((1024, 1024), Image.LANCZOS).convert('RGBA'))
            write_blp(out, np.ascontiguousarray(half), False)
        n += 1
        if n % 50 == 0: print(n, round(time.time() - t0), 's', flush=True)
print('DONE', n, flush=True)
