"""Candidates for the 1x minimap copy of one tile, judged against the game's own file."""
import json, sys, numpy as np
from PIL import Image, ImageFilter
RAW = r"C:\Dev\wow-forever-addons\_work\mini\raw"
PACK = r"C:\Dev\wow-forever-addons\DenoMap\Minimap\0"
J = json.load(open(r"C:\Dev\wow-forever-addons\_work\mini\mjobs.json"))["0"]
key = sys.argv[1] if len(sys.argv) > 1 else "32_48"
orig = Image.open(f"{RAW}/{J[key]}.blp").convert("RGB")
ai4 = Image.open(f"{PACK}/{key}.blp").convert("RGB")
ai1 = ai4.resize((512, 512), Image.LANCZOS)
def arr(im): return np.asarray(im, dtype=np.float32)
def img(a): return Image.fromarray(np.clip(a + 0.5, 0, 255).astype(np.uint8))
def blur(im, s): return arr(im.filter(ImageFilter.GaussianBlur(s)))
def lap(im, box):
    g = np.asarray(im.convert("L").crop(box), dtype=np.float32)
    return float((-4*g[1:-1,1:-1] + g[:-2,1:-1] + g[2:,1:-1] + g[1:-1,:-2] + g[1:-1,2:]).var())
cands = {"game file": orig, "AI 1x (now)": ai1}
for alpha in (0.6, 1.0, 1.5):
    cands[f"game + {alpha} x AI edges"] = img(arr(orig) + alpha * (arr(ai1) - blur(ai1, 1.0)))
cands["AI 1x + game grain"] = img(arr(ai1) + (arr(orig) - blur(orig, 1.0)))
boxes = {"forest": (300, 60, 420, 180), "abbey": (150, 330, 300, 470), "all": (0, 0, 512, 512)}
base = {n: lap(orig, b) for n, b in boxes.items()}
for name, im in cands.items():
    print(f"{name:26}", "  ".join(f"{n} {100*lap(im, b)/base[n]:4.0f}%" for n, b in boxes.items()),
          " mean diff to game file", round(float(np.abs(arr(im) - arr(orig)).mean()), 2))
sheet = Image.new("RGB", (4 * 330, 330), (255, 0, 255))
for i, n in enumerate(["game file", "AI 1x (now)", "game + 1.0 x AI edges", "AI 1x + game grain"]):
    sheet.paste(cands[n].crop((150, 300, 315, 465)).resize((320, 320), Image.NEAREST), (i * 330, 0))
sheet.save(r"C:\Dev\forever-server\feed\crop.png")
