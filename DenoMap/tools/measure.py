"""Compare a minimap crop with the game's own picture of the same spot (feed/mm_off.png).
usage: measure.py crop.png [label]"""
import sys, numpy as np
from PIL import Image, ImageStat
FEED = r"C:\Dev\forever-server\feed"
game = Image.open(FEED + r"\mm_off.png").convert("RGB")
ours = Image.open(sys.argv[1]).convert("RGB")
label = sys.argv[2] if len(sys.argv) > 2 else sys.argv[1]
regions = {"forest top": (70,20,120,45), "forest right": (140,90,175,125), "forest bottom": (95,130,135,165), "rocks left": (10,60,35,110)}
def lap(im):
    g = np.asarray(im.convert("L"), dtype=np.float32)
    return float((-4*g[1:-1,1:-1] + g[:-2,1:-1] + g[2:,1:-1] + g[1:-1,:-2] + g[1:-1,2:]).var())
print(label)
for name, box in regions.items():
    a, b = ours.crop(box), game.crop(box)
    ma, mb = np.array(ImageStat.Stat(a).mean), np.array(ImageStat.Stat(b).mean)
    print(f"  {name:14} tone game/ours {(mb[:2]/ma[:2]).round(2)}  sharpness ours {lap(a):7.1f}  game {lap(b):7.1f}  ({100*lap(a)/lap(b):3.0f}%)")
