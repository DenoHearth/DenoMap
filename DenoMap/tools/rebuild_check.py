"""After a game patch: fetch every source texture again from the new build, and where the
bytes differ replace the raw file and delete the upscaled outputs it feeds, so the normal
pipeline (process.py, extras.py, mprocess.py) redoes exactly those.

    py -3 rebuild_check.py 1.60.1.70291
"""
import json, os, sys, urllib.request, concurrent.futures as cf
NEW = sys.argv[1]
ADDON = '..'
def fetch(fid):
    for attempt in range(4):
        try:
            req = urllib.request.Request(f'https://wago.tools/api/casc/{fid}?download&version={NEW}', headers={'User-Agent': 'Mozilla/5.0'})
            d = urllib.request.urlopen(req, timeout=60).read()
            if d[:4] == b'BLP2': return d
        except Exception:
            pass
    return None
def changed(folder):
    fids = [f[:-4] for f in os.listdir(folder) if f.endswith('.blp')]
    out = []
    def one(fid):
        d = fetch(fid); p = f'{folder}/{fid}.blp'
        if d is None: return ('FAILED', fid)
        if d != open(p, 'rb').read():
            open(p, 'wb').write(d); return ('changed', fid)
        return ('same', fid)
    with cf.ThreadPoolExecutor(8) as ex: res = list(ex.map(one, fids))
    print(folder, {k: sum(1 for r in res if r[0] == k) for k in ('same', 'changed', 'FAILED')}, flush=True)
    return {int(f) for k, f in res if k == 'changed'}
def drop(path):
    if os.path.exists(path): os.remove(path); return 1
    return 0
# world map: tiles, overlays, extras
all_changed = changed('raw')        # one raw folder here: maps and minimap tiles together
ch = all_changed; n = 0
J = json.load(open('jobs.json')); grouped = set()
for a in J.values():
    groups = [a['tiles']] + [o['tiles'] for o in a['overlays'].values()]
    for g in groups:
        ids = {t[2] for t in g}; grouped |= ids
        if ids & ch:
            for f in ids: n += drop(f'{ADDON}/Maps/{f}.blp')
for f in ch - grouped: n += drop(f'{ADDON}/Maps/{f}.blp')       # flight maps, highlights
print('world map outputs to redo:', n, flush=True)
# minimap: the tile and the eight around it (their rim comes from it)
ch = all_changed; n = 0
M = json.load(open('mjobs.json'))
for world, tiles in M.items():
    for key, fid in tiles.items():
        if fid in ch:
            c, r = map(int, key.split('_'))
            for dc in (-1, 0, 1):
                for dr in (-1, 0, 1):
                    n += drop(f'{ADDON}/Minimap/{world}/{c + dc}_{r + dr}.blp')
print('minimap outputs to redo:', n, flush=True)
