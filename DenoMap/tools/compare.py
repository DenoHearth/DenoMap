"""Ours against the game's own picture of the same view (two crops of the same size).
usage: compare.py ours.png game.png [label]
Splits the pictures into patches; prints the median of ours/game for fine detail and for tone."""
import sys, numpy as np
from PIL import Image
ours = np.asarray(Image.open(sys.argv[1]).convert("RGB"), dtype=np.float32)
game = np.asarray(Image.open(sys.argv[2]).convert("RGB"), dtype=np.float32)
label = sys.argv[3] if len(sys.argv) > 3 else ""
def lap(a):
    g = a.mean(-1)
    return float((-4*g[1:-1,1:-1] + g[:-2,1:-1] + g[2:,1:-1] + g[1:-1,:-2] + g[1:-1,2:]).var())
P = 16
detail, tone = [], []
h, w, _ = ours.shape
for y in range(0, h - P, P):
    for x in range(0, w - P, P):
        a, b = ours[y:y+P, x:x+P], game[y:y+P, x:x+P]
        if b.mean() < 25 or lap(b) < 4:        # outside the map, or nothing to compare
            continue
        detail.append(lap(a) / lap(b)); tone.append(a[..., :2].mean() / b[..., :2].mean())
d = np.array(detail)
print(f"{label:34} patches {len(d):3}  fine detail ours/game: median {100*np.median(d):4.0f}%  (quartiles {100*np.percentile(d,25):.0f}-{100*np.percentile(d,75):.0f}%)  brightness ours/game {np.median(tone):.2f}")
