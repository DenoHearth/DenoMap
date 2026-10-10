"""One typed command, then the addon steps through every minimap zoom level with our tiles and
with the game's own and signals each picture; this captures on the signal and compares."""
import importlib.util, sys, time, numpy as np
from PIL import Image
spec = importlib.util.spec_from_file_location("eyes", r"C:\Dev\forever-server\eyes.py"); e = importlib.util.module_from_spec(spec)
ARGS = sys.argv[1:]; sys.argv = ["eyes.py"]; spec.loader.exec_module(e)
proc = e.find_client(); why = e.gate(proc)
if why: sys.exit("no look: " + why)
hwnd = e.game_window(proc.pid)
BOX = (1380, 60, 1600, 270)
CMD = ARGS[0] if ARGS else "sweep"
TAG = CMD.replace(" ", "")
e.say(hwnd, "/denomap " + CMD)
shots, seen, deadline = {}, None, time.time() + 150
while time.time() < deadline:
    pic = e.grab(hwnd); msg = e.read_strip(pic) if pic else None
    if msg and msg[0] != seen:
        seen = msg[0]; kind, _, text = msg[1].partition("|")
        if kind == "shot":
            if text == "done": break
            box = tuple(int(v) for v in text.split(" box ")[1].split(",")) if " box " in text else BOX
            shots[text.split(" (")[0]] = (np.asarray(pic.crop(box).convert("RGB"), dtype=np.float32), text)
    time.sleep(0.15)
def lap(a):
    g = a.mean(-1); return float((-4*g[1:-1,1:-1] + g[:-2,1:-1] + g[2:,1:-1] + g[1:-1,:-2] + g[1:-1,2:]).var())
for z in range(8):
    if f"zoom{z} ours" not in shots or f"zoom{z} game" not in shots: continue
    (ours, t1), (game, t2) = shots[f"zoom{z} ours"], shots[f"zoom{z} game"]
    Image.fromarray(ours.astype(np.uint8)).save(rf"C:\Dev\forever-server\feed\{TAG}{z}_ours.png"); Image.fromarray(game.astype(np.uint8)).save(rf"C:\Dev\forever-server\feed\{TAG}{z}_game.png")
    d, t, P = [], [], 16
    for y in range(0, ours.shape[0] - P, P):
        for x in range(0, ours.shape[1] - P, P):
            a, b = ours[y:y+P, x:x+P], game[y:y+P, x:x+P]
            if b.mean() < 25 or lap(b) < 4: continue
            d.append(lap(a) / lap(b)); t.append(a[..., :2].mean() / b[..., :2].mean())
    ok = ("on, drawing" in t1 and "off" in t2) or " box " in t1
    note = t1[t1.find("(") : t1.find(")") + 1] if " box " in t1 else ""
    print(f"zoom {z}: fine detail ours/game median {100*np.median(d):4.0f}% (quartiles {100*np.percentile(d,25):.0f}-{100*np.percentile(d,75):.0f}%), brightness {np.median(t):.2f} {note}{'' if ok else '   STATE WRONG: ' + t1 + ' / ' + t2}")
print(len(shots), "pictures")
