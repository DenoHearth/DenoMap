"""How bright the game draws its minimap terrain at each hour of the game clock.

Local test server only. For every hour asked for: the server is told to show that hour (a file
it reads at login), the character logs out and in again through the watcher, the minimap is
captured with our tiles (drawn at a known tint) and with the game's own, and the two are compared.
    py -3 tonecurve.py 0 3 6 9 12 15 18 21
"""
import json, subprocess, sys, time, numpy as np
from pathlib import Path
from PIL import Image
EYES = r"C:\Dev\forever-server\eyes.py"
FEED = Path(r"C:\Dev\forever-server\feed")
OFFSET = Path(r"C:\Dev\forever-server\server\gametime_offset.txt")
TINT = 0.77                      # what Minimap.lua tints our tiles with while this runs
CROP = "1380,60,1600,270"

def eyes(steps, timeout=60):
    out = subprocess.run([sys.executable, EYES, "--timeout", str(timeout), "--do", steps],
                         capture_output=True, text=True).stdout
    states = []
    for line in out.splitlines():
        try:
            e = json.loads(line)
        except ValueError:
            continue
        if e.get("kind") == "state":
            states.append(e["text"])
    return states, out

def shot(name):
    eyes("sleep:1.5; crop:" + CROP)
    im = Image.open(FEED / "crop.png").convert("RGB")
    im.save(FEED / name)
    return np.asarray(im, dtype=np.float32)

def minimap_on(want):
    for _ in range(3):
        states, _ = eyes("cmd:denomap; feed:state", 20)
        if not states:
            continue
        on = "minimap on, drawing" in states[-1]
        if on == want:
            return True
        eyes("cmd:denomap minimap; feed:state", 20)
    return False

def ratio(ours, game):
    vals = []
    P = 16
    for y in range(0, ours.shape[0] - P, P):
        for x in range(0, ours.shape[1] - P, P):
            a, b = ours[y:y+P, x:x+P, :2].mean(), game[y:y+P, x:x+P, :2].mean()
            if a > 25 and b > 20:
                vals.append(b / a)
    return float(np.median(vals)), len(vals)

rows = []
for hour in [int(a) for a in sys.argv[1:]]:
    now = time.localtime()
    OFFSET.write_text(str((hour - now.tm_hour) % 24))
    _, out = eyes("key:escape; cmd:logout; sleep:23; wait:character select; sleep:4; key:return; wait:world; sleep:9; click:703,733; sleep:1", 70)
    if "gave up" in out:
        print(hour, "relog failed:", out.strip().splitlines()[-1][:120], flush=True)
        continue
    if not minimap_on(True):
        print(hour, "could not switch our minimap on", flush=True); continue
    ours = shot(f"tone_{hour:02d}_ours.png")
    if not minimap_on(False):
        print(hour, "could not switch our minimap off", flush=True); continue
    game = shot(f"tone_{hour:02d}_game.png")
    r, n = ratio(ours, game)
    rows.append((hour, now.tm_min, round(TINT * r, 3), n))
    print(f"game clock {hour:02d}:{now.tm_min:02d}  game terrain = {TINT * r:.3f} of the file  ({n} patches)", flush=True)
OFFSET.write_text("0")
minimap_on(True)
print(json.dumps(rows))
