"""Read each world map's WDT (MAID chunk) for its minimap tile file ids; download the tiles."""
import json, os, struct, sys, time, urllib.request, concurrent.futures as cf
BUILD = '1.60.1.70291'
# map id -> WDT file id (Map.db2): Eastern Kingdoms, Kalimdor, Zephras Isle, Alterac Valley,
# Warsong Gulch, Arathi Basin, Darkspear Islands
MAPS = {0: 775971, 1: 782779, 2991: 7198644, 30: 790112, 489: 790291, 529: 790377, 2997: 7251908}
def get(fid, path, magic=None):
    if os.path.exists(path) and os.path.getsize(path) > 16: return 0
    for attempt in range(4):
        try:
            req = urllib.request.Request(f'https://wago.tools/api/casc/{fid}?download&version={BUILD}', headers={'User-Agent': 'Mozilla/5.0'})
            d = urllib.request.urlopen(req, timeout=60).read()
            if magic is None or d[:4] == magic:
                open(path, 'wb').write(d); return 1
        except Exception as e:
            pass
        time.sleep(2 + attempt * 3)
    return -1
os.makedirs('raw', exist_ok=True)
jobs = {}
for m, wdt in MAPS.items():
    p = f'raw/wdt_{m}.wdt'; get(wdt, p)
    d = open(p, 'rb').read(); pos = 0; tiles = {}
    while pos < len(d):
        tag, size = d[pos:pos + 4][::-1], struct.unpack('<I', d[pos + 4:pos + 8])[0]
        if tag == b'MAID':
            for i in range(64 * 64):
                ids = struct.unpack('<8I', d[pos + 8 + i * 32:pos + 8 + i * 32 + 32])
                if ids[7]: tiles[f'{i % 64}_{i // 64}'] = ids[7]      # key: column_row
        pos += 8 + size
    jobs[m] = tiles
    xs = [int(k.split('_')[0]) for k in tiles]; ys = [int(k.split('_')[1]) for k in tiles]
    print(m, 'tiles', len(tiles), 'cols', min(xs), max(xs), 'rows', min(ys), max(ys))
json.dump(jobs, open('mjobs.json', 'w'))
if '--fetch' in sys.argv:
    todo = [(f, f'raw/{f}.blp') for t in jobs.values() for f in t.values()]
    with cf.ThreadPoolExecutor(6) as ex: res = list(ex.map(lambda a: get(a[0], a[1], b'BLP2'), todo))
    print('downloaded', res.count(1), 'had', res.count(0), 'failed', res.count(-1))
