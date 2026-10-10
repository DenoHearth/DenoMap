"""Our minimap against the game's own at every zoom level (local test server, through the watcher)."""
import json, subprocess, sys, numpy as np
from pathlib import Path
from PIL import Image
EYES = r"C:\Dev\forever-server\eyes.py"; FEED = Path(r"C:\Dev\forever-server\feed"); CROP = "1380,60,1600,270"
def eyes(steps, timeout=40):
    out = subprocess.run([sys.executable, EYES, "--timeout", str(timeout), "--do", steps], capture_output=True, text=True).stdout
    found = []
    for line in out.splitlines():
        try: e = json.loads(line)
        except ValueError: continue
        found.append(e)
    return found
def state():
    for _ in range(3):
        st = [e["text"] for e in eyes("cmd:denomap; feed:state", 20) if e.get("kind") == "state"]
        if st: return st[-1]
    return ""
def want(on):
    for _ in range(3):
        if ("minimap on, drawing" in state()) == on: return True
        eyes("cmd:denomap minimap; feed:state", 20)
    return False
def shot(name):
    eyes("sleep:1.5; crop:" + CROP)
    im = Image.open(FEED / "crop.png").convert("RGB"); im.save(FEED / name); return np.asarray(im, dtype=np.float32)
def lap(a):
    g = a.mean(-1); return float((-4*g[1:-1,1:-1] + g[:-2,1:-1] + g[2:,1:-1] + g[1:-1,:-2] + g[1:-1,2:]).var())
for zoom in range(6):
    eyes(f"cmd:denomap zoom {zoom}; feed:state", 20)
    if not want(True): print(zoom, "could not switch on"); continue
    slot = [e["text"] for e in eyes("cmd:denomap; sleep:7", 20) if e.get("kind") == "minimap" and e["text"].startswith("slot 5")]
    ours = shot(f"zoom{zoom}_ours.png")
    if not want(False): print(zoom, "could not switch off"); continue
    game = shot(f"zoom{zoom}_game.png")
    d, t = [], []
    P = 16
    for y in range(0, ours.shape[0] - P, P):
        for x in range(0, ours.shape[1] - P, P):
            a, b = ours[y:y+P, x:x+P], game[y:y+P, x:x+P]
            if b.mean() < 25 or lap(b) < 4: continue
            d.append(lap(a) / lap(b)); t.append(a[..., :2].mean() / b[..., :2].mean())
    info = slot[-1][slot[-1].find("copy="):] if slot else ""
    print(f"zoom {zoom}: fine detail ours/game median {100*np.median(d):4.0f}% (quartiles {100*np.percentile(d,25):.0f}-{100*np.percentile(d,75):.0f}%), brightness {np.median(t):.2f}   {info}", flush=True)
want(True)
