"""The measured tint of the game minimap, per zone light.

The game lights its minimap: it shows a tile at  file x tint,  and the tint is the zone own. The
rule of 1.6.0 (a fixed part + a share of the direct light colour - a share of the ambient light
colour, TINT below) holds to a few percent in most zones and is far off in some (Dun Morogh 19
percent too bright in red, Tanaris 16 percent too blue). Measured in game on 2026-10-12 at 64
places at midday, ours against the game own picture of the same view: inside one zone the error
is the same everywhere, and no column of the light table explains it. So each zone light gets a
measured correction on top of the rule.

tintspots.json holds the measurements: place, world, position, and the tint the game really uses
there at midday (red, green, blue). solve() turns them into one correction per light: a place
under several lights is their mix, weighted as the game blends them.

Used by lights.py (writes the corrections into Lights.lua) and water.py (the water colour is
divided by the tint a tile gets).
"""
import csv, json, math
from pathlib import Path
import numpy as np

BUILD = "1.60.1.70291"
DB = Path(r"C:\Users\Deniz\.claude\skills\foreverman\tools\db2cache") / BUILD
SPOTS = Path(__file__).resolve().parent / "tintspots.json"
TINT = ((0.724, 0.254, 0.0), (0.679, 0.255, 0.035), (0.94, 0.219, 0.338))     # red, green, blue: fixed, direct, ambient (Minimap.lua)
RIDGE = 0.1                # pull towards "no correction" for lights that few measurements touch
NOON = 1440                # half minutes
ZONES = True               # False: without the zone lights (how the tint was worked out before they were added)

_cache = {}


def tables():
    """{world: {"base": params or None, "spots": [(light id, x, y, start, end, params)]}}, {params: six numbers at noon}"""
    if _cache:
        return _cache["worlds"], _cache["noon"]
    keys = {}
    for row in csv.DictReader(open(DB / "LightData.csv", encoding="utf-8")):
        keys.setdefault(int(row["LightParamID"]), []).append(
            (int(row["Time"]), int(row["DirectColor"]) & 0xFFFFFF, int(row["AmbientColor"]) & 0xFFFFFF))
    noon = {}
    for params, rows in keys.items():
        rows.sort()
        last = rows[-1]
        for key in rows:
            if key[0] <= NOON:
                last = key
        nxt = rows[(rows.index(last) + 1) % len(rows)]
        a, b = last[0], nxt[0]
        if b <= a:
            b += 2880
        at = NOON if NOON >= a else NOON + 2880
        part = (at - a) / (b - a) if b > a else 0
        six = []
        for field in (1, 2):
            for shift in (16, 8, 0):
                lo, hi = (last[field] >> shift) & 255, (nxt[field] >> shift) & 255
                six.append(lo + (hi - lo) * part)
        noon[params] = np.array(six, np.float32)
    worlds = {}
    for light in csv.DictReader(open(DB / "Light.csv", encoding="utf-8")):
        params = int(light["LightParamsID_0"])
        if params not in noon:
            continue
        x, y, z = (float(light[f"GameCoords_{i}"]) for i in range(3))
        world = worlds.setdefault(int(light["ContinentID"]), {"base": None, "base_id": None, "spots": []})
        if x == 0 and y == 0 and z == 0:
            world["base"], world["base_id"] = params, int(light["ID"])
        else:
            world["spots"].append((int(light["ID"]), x, y, float(light["GameFalloffStart"]), float(light["GameFalloffEnd"]), params))
    # Zone lights: an outline on the map with a light of its own, which stands in for the
    # light of the whole world inside it (ZoneLight and ZoneLightPoint; Burning Steppes, Mulgore,
    # Elwynn and a dozen more). Their key here is "zone" + the row number.
    by_light = {int(light["ID"]): int(light["LightParamsID_0"]) for light in csv.DictReader(open(DB / "Light.csv", encoding="utf-8"))}
    points = {}
    for point in csv.DictReader(open(DB / "ZoneLightPoint.csv", encoding="utf-8")):
        points.setdefault(int(point["ZoneLightID"]), []).append((int(point["PointOrder"]), float(point["Pos_0"]), float(point["Pos_1"])))
    for zone in csv.DictReader(open(DB / "ZoneLight.csv", encoding="utf-8")):
        params = by_light.get(int(zone["LightID"]))
        outline = [(x, y) for _, x, y in sorted(points.get(int(zone["ID"]), []))]
        if ZONES and params in noon and len(outline) >= 3 and int(zone["MapID"]) in worlds:
            worlds[int(zone["MapID"])].setdefault("zones", []).append(("zone%d" % int(zone["ID"]), params, outline, zone["Name"].strip()))
    _cache["worlds"], _cache["noon"] = worlds, noon
    return worlds, noon


def within(outline, x, y):
    """Is the point inside the outline (even-odd rule)."""
    inside = False
    for i in range(len(outline)):
        x1, y1 = outline[i]
        x2, y2 = outline[(i + 1) % len(outline)]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
            inside = not inside
    return inside


def base_of(got, x, y):
    """(key, params) of the light that fills in where the local lights leave room: the zone light the point is in, else the world light."""
    for key, params, outline, _ in got.get("zones", []):
        if within(outline, x, y):
            return key, params
    return got["base_id"], got["base"]


def shares(world, x, y):
    """[(light id, share)] at a place, the base light of the world last (id None when the world has none)."""
    worlds, _ = tables()
    got = worlds.get(world)
    if not got:
        return []
    out, weight = [], 0.0
    for light, lx, ly, start, end, params in got["spots"]:
        far = math.hypot(x - lx, y - ly)
        if far < end:
            share = 1.0 if far <= start else (end - far) / max(end - start, 1e-6)
            out.append((light, share)); weight += share
    if weight >= 1:
        return [(light, share / weight) for light, share in out]
    key, params = base_of(got, x, y)
    if params is not None:
        return out + [(key, 1 - weight)]
    return [(light, share / weight) for light, share in out] if weight > 0 else []


def rule(world, x, y):
    """The tint of the plain rule at a place at midday, red green blue; None where the world has no lights."""
    worlds, noon = tables()
    got = worlds.get(world)
    mix = shares(world, x, y)
    if not got or not mix:
        return None
    by_id = {light: params for light, _, _, _, _, params in got["spots"]}
    by_id[got["base_id"]] = got["base"]
    for key, params, _, _ in got.get("zones", []):
        by_id[key] = params
    six = sum(noon[by_id[light]] * share for light, share in mix)
    return np.array([min(1.0, TINT[n][0] + TINT[n][1] * six[n] / 255 - TINT[n][2] * six[n + 3] / 255) for n in range(3)], np.float32)


def solve():
    """{light id: (red, green, blue correction)} from tintspots.json. Lights no measurement touches are left out (correction 1)."""
    if "fix" in _cache:
        return _cache["fix"]
    spots = json.load(open(SPOTS, encoding="utf-8"))
    ids, rows, want = {}, [], []
    for spot in spots:
        base = rule(spot["world"], spot["x"], spot["y"])
        if base is None:
            continue
        mix = shares(spot["world"], spot["x"], spot["y"])
        for light, _ in mix:
            ids.setdefault(light, len(ids))
        rows.append(mix); want.append(np.array(spot["tint"], np.float32) / base)
    a = np.zeros((len(rows), len(ids)), np.float32)
    for i, mix in enumerate(rows):
        for light, share in mix:
            a[i, ids[light]] += share
    want = np.array(want)
    # least squares, pulled towards 1: (A'A + k I) c = A'w + k
    left = a.T @ a + RIDGE * np.eye(len(ids), dtype=np.float32)
    fix = np.linalg.solve(left, a.T @ want + RIDGE)
    _cache["fix"] = {light: tuple(float(v) for v in fix[i]) for light, i in ids.items()}
    _cache["left"] = float(np.abs(a @ fix / want - 1).mean())
    return _cache["fix"]


def tint(world, x, y):
    """The tint a tile gets at a place at midday, with the measured corrections: red green blue."""
    base = rule(world, x, y)
    if base is None:
        return None
    fix = solve()
    mix = shares(world, x, y)
    factor = sum(np.array(fix.get(light, (1.0, 1.0, 1.0)), np.float32) * share for light, share in mix)
    return np.minimum(1.0, base * factor)


if __name__ == "__main__":
    fix = solve()
    print(len(json.load(open(SPOTS, encoding="utf-8"))), "places,", len(fix), "lights corrected, mean error left at the places %.3f" % _cache["left"])
    worst = sorted(fix.items(), key=lambda kv: -max(abs(v - 1) for v in kv[1]))[:8]
    for light, c in worst:
        print("  light", light, "x", [round(v, 2) for v in c])
