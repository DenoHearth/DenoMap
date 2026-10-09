"""Run from this folder:  python jobs.py --fetch

Build jobs.json (every map art Forever shows, its tiles and discovery overlays) and
download the source textures from wago.tools into raw/<fileDataID>.blp."""
import csv, json, os, sys, time, urllib.request, concurrent.futures as cf
BUILD = '1.60.1.70291'
def T(n):
    """One game table as rows; fetched once from wago.tools into db2/."""
    p = f'db2/{n}.csv'
    if not os.path.exists(p):
        os.makedirs('db2', exist_ok=True)
        req = urllib.request.Request(f'https://wago.tools/db2/{n}/csv?build={BUILD}', headers={'User-Agent': 'Mozilla/5.0'})
        open(p, 'wb').write(urllib.request.urlopen(req, timeout=120).read())
    return list(csv.DictReader(open(p, encoding='utf-8-sig')))
uimap = {r['ID']: r for r in T('UiMap')}
style = {a['ID']: a['UiMapArtStyleID'] for a in T('UiMapArt')}
layer = {l['UiMapArtStyleID']: l for l in T('UiMapArtStyleLayer') if l['LayerIndex'] == '0'}
arts = {}
for r in T('UiMapXMapArt'):
    if r['UiMapID'] in uimap and style.get(r['UiMapArtID']) == '1':
        a = arts.setdefault(r['UiMapArtID'], {'maps': [], 'tiles': [], 'overlays': {}})
        a['maps'].append([int(r['UiMapID']), uimap[r['UiMapID']]['Name_lang']])
for t in T('UiMapArtTile'):
    if t['UiMapArtID'] in arts and t['LayerIndex'] == '0':
        arts[t['UiMapArtID']]['tiles'].append([int(t['RowIndex']), int(t['ColIndex']), int(t['FileDataID'])])
ov = {}
for o in T('WorldMapOverlay'):
    if o['UiMapArtID'] in arts and int(o['TextureWidth']) > 0:
        ov[o['ID']] = arts[o['UiMapArtID']]['overlays'].setdefault(o['ID'], {
            'w': int(o['TextureWidth']), 'h': int(o['TextureHeight']), 'x': int(o['OffsetX']), 'y': int(o['OffsetY']), 'tiles': []})
for t in T('WorldMapOverlayTile'):
    if t['WorldMapOverlayID'] in ov and t['LayerIndex'] == '0':
        ov[t['WorldMapOverlayID']]['tiles'].append([int(t['RowIndex']), int(t['ColIndex']), int(t['FileDataID'])])
for a in arts.values():
    a['layer'] = [int(layer['1']['LayerWidth']), int(layer['1']['LayerHeight'])]
json.dump(arts, open('jobs.json', 'w'), indent=1)
fids = sorted({t[2] for a in arts.values() for t in a['tiles']} |
              {t[2] for a in arts.values() for o in a['overlays'].values() for t in o['tiles']})
print('arts', len(arts), 'base tiles', sum(len(a['tiles']) for a in arts.values()),
      'overlays', sum(len(a['overlays']) for a in arts.values()), 'files', len(fids))
os.makedirs('raw', exist_ok=True)
def get(fid):
    p = f'raw/{fid}.blp'
    if os.path.exists(p) and os.path.getsize(p) > 100: return 0
    for attempt in range(4):
        try:
            req = urllib.request.Request(f'https://wago.tools/api/casc/{fid}?download&version={BUILD}',
                                         headers={'User-Agent': 'Mozilla/5.0'})
            d = urllib.request.urlopen(req, timeout=60).read()
            if d[:4] == b'BLP2':
                open(p, 'wb').write(d); return 1
        except Exception as e:
            err = e
        time.sleep(2 + attempt * 3)
    return -1
if '--fetch' in sys.argv:
    with cf.ThreadPoolExecutor(4) as ex:
        res = list(ex.map(get, fids))
    print('downloaded', res.count(1), 'had', res.count(0), 'failed', res.count(-1))
