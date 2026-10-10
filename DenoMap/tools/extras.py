"""The map textures that are not tiles: the flight maps and the zone highlights shown when
the mouse is over a zone on a continent map. Same 4x upscale, written to Maps/<file id>.blp."""
import csv, json, os, sys, time, urllib.request, numpy as np
from PIL import Image
from up import upscale_rgb, bleed, write_blp, with_grain
FORCE = '--force' in sys.argv
BUILD = '1.60.1.70291'
MODEL = '../models/RealESRGAN_x4plus.pth'
OUT = 'C:/Dev/wow-forever-addons/DenoMap/Maps'
DB2 = 'C:/Users/Deniz/.claude/skills/foreverman/tools/db2cache/' + BUILD + '/'
def T(n): return list(csv.DictReader(open(DB2 + n + '.csv', encoding='utf-8-sig')))
live = set(json.load(open('jobs.json')))
art = T('UiMapArt'); style = {a['ID']: a['UiMapArtStyleID'] for a in art}
uimap = {r['ID'] for r in T('UiMap')}
taxi_arts = {r['UiMapArtID'] for r in T('UiMapXMapArt') if r['UiMapID'] in uimap and style.get(r['UiMapArtID']) == '4'}
fids = {int(a['HighlightFileDataID']) for a in art if a['ID'] in live and a['HighlightFileDataID'] != '0'}
fids |= {int(t['FileDataID']) for t in T('UiMapArtTile') if t['UiMapArtID'] in taxi_arts}
print('files', len(fids))
os.makedirs('raw', exist_ok=True)
for f in sorted(fids):
    p = f'raw/{f}.blp'
    if not os.path.exists(p):
        req = urllib.request.Request(f'https://wago.tools/api/casc/{f}?download&version={BUILD}', headers={'User-Agent': 'Mozilla/5.0'})
        open(p, 'wb').write(urllib.request.urlopen(req, timeout=60).read())
    im = Image.open(p).convert('RGBA'); a = np.asarray(im)
    alpha = a[..., 3].min() < 250
    out = f'{OUT}/{f}.blp'
    if os.path.exists(out) and not FORCE: continue
    if alpha:
        filled = bleed(a)
        rgb = with_grain(upscale_rgb(filled, MODEL), filled)
        al = np.asarray(Image.fromarray(a[..., 3]).resize((im.width * 4, im.height * 4), Image.BICUBIC))
        big = np.dstack([rgb, al])
    else:
        rgb = with_grain(upscale_rgb(np.ascontiguousarray(a[..., :3]), MODEL), a)
        big = np.dstack([rgb, np.full(rgb.shape[:2], 255, np.uint8)])
    write_blp(out, np.ascontiguousarray(big), alpha)
    print(f, im.size, 'alpha' if alpha else 'opaque', flush=True)
print('DONE')
