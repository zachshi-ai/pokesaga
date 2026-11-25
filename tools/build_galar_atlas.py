"""Build the named Wild Area / DLC districts and connect their surveyed boundaries.

python3 tools/build_galar_atlas.py /path/to/pret/pokeemerald
Existing region/map IDs, warp records and save coordinates are retained.
"""

from collections import defaultdict
import heapq
from random import Random
import sys, zlib, json

import numpy as np
from PIL import Image, ImageDraw
from bake_emerald_field import Emerald, pack
from build_switch_fields import read, write
from switch_fields.terrain import relief
from switch_fields.rooms import generated_room
from galar_atlas.art import ROOT, prop, surface, chip

PLAN = ROOT / "tools/galar_atlas"
MAPS = ROOT / "content/regions"
ART = ROOT / "assets/galar/districts"
V = {"N": (0, -1), "S": (0, 1), "E": (1, 0), "W": (-1, 0)}
BACK = {"N": "S", "S": "N", "E": "W", "W": "E"}
DIR = {"N": "up", "S": "down", "E": "right", "W": "left"}
NW = {
    "galar_axew_eye",
    "armor_workout_sea",
    "armor_stepping_sea",
    "armor_insular_sea",
    "armor_honey_sea",
    "armor_honey_island",
    "crown_frigid",
}
ROOMS = {
    "galar_meetup": ("station", "galar_meetup_station_room"),
    "galar_bridge_field": ("nursery", "galar_bridge_nursery_room"),
}


def rows(file):
    return [s for s in (PLAN / file).read_text().splitlines() if s and s[0] != "#"]


def mapfile(mid):
    return MAPS / mid.split("_")[0] / "maps" / (mid + ".json")


def route(cost, start):
    h, w = cost.shape
    q = [(0, start)]
    dist = {start: 0}
    prev = {}
    while q:
        n, (x, y) = heapq.heappop(q)
        if n != dist[(x, y)]:
            continue
        for dx, dy in V.values():
            xx, yy = x + dx, y + dy
            if not 0 <= xx < w or not 0 <= yy < h:
                continue
            n2 = n + cost[yy, xx]
            if n2 >= dist.get((xx, yy), float("inf")):
                continue
            dist[(xx, yy)] = n2
            prev[(xx, yy)] = (x, y)
            heapq.heappush(q, (n2, (xx, yy)))
    return dist, prev


def trace(prev, dest):
    p = dest
    path = [p]
    while p in prev:
        p = prev[p]
        path.append(p)
    return path[::-1]


def portals(mid, m, directions, origin, terrain=None):
    g = np.array(m["tiles"])
    h, w = g.shape
    old = m.get("galar_atlas_ports", {})
    used = {tuple(p["at"]) for k in ("npcs", "objects", "warps") for p in m[k]}
    spaced = set(used)
    used.add(tuple(m["spawn"]))
    for p in m["hoenn_art"]["p"]:
        key = str(p[0])
        x, y = p[1:3]
        if key.endswith(("_grass.png", "/green.png", "/snow.png")):
            continue
        used.add((x, y))
        if "/architecture/" in key or key.endswith(
            ("max_lair.png", "dojo.png", "tower_water.png", "tower_dark.png")
        ):
            for j in range(y - 2, y + 1):
                for i in range(x - 2, x + 3):
                    used.add((i, j))
    cost = np.where(g == 1, 55, np.where(g == 2, 2 if mid in NW else 95, 1.0))
    for x, y in used:
        if 0 <= x < w and 0 <= y < h:
            cost[y, x] = 500
    dist, prev = route(cost, origin)
    plans = {}
    for other, side in sorted(directions.items()):
        if other in old:
            plans[other] = old[other]
            continue
        dx, dy = V[side]
        choices = []
        for u in range(3, (w if dy else h) - 3):
            x, y = (u, 0 if dy < 0 else h - 1) if dy else (0 if dx < 0 else w - 1, u)
            landing = (x - dx, y - dy)
            if any(abs(x - p[0]) + abs(y - p[1]) < 4 for p in spaced):
                continue
            candidate = trace(prev, landing)[1:]
            if any(p in used for p in candidate):
                continue
            score = dist[landing] + abs(u - (w if dy else h) * 0.5) * 0.17
            choices.append((score, x, y, candidate))
        if not choices:
            raise ValueError((mid, other, "no free edge"))
        _, x, y, approach = min(choices)
        # Only the final spur through solid terrain needs carving on a legacy map.
        if terrain is None:
            anchor = len(approach)
            while anchor > 0 and g[
                approach[anchor - 1][1], approach[anchor - 1][0]
            ] in (1, 2):
                anchor -= 1
            approach = approach[max(0, anchor - 1) :]
        plans[other] = {
            "at": [x, y],
            "land": [x - dx, y - dy],
            "path": [list(p) for p in approach],
            "side": side,
        }
        used.add((x, y))
        spaced.add((x, y))
    return plans


def scene(mid, m, im, g, props):
    w, h = im.width // 16, im.height // 16
    ART.mkdir(parents=True, exist_ok=True)
    f = ART / (mid + ".png")
    im.save(f, optimize=True)
    m["tiles"] = g.tolist()
    m["size"] = [w, h]
    m["hoenn_art"] = {
        "s": [w, h],
        "t": pack(np.zeros((h, w), dtype="<u2")),
        "p": props,
        "scene": ["res://" + f.relative_to(ROOT).as_posix(), 0, 0],
    }
    write(mapfile(mid), m)


def new_data(mid, name, layout):
    sea = mid in NW
    rows = layout.split("/")
    w = 23 if "temple" in mid else 37 if "tunnel" in mid or "cave" in mid else 47
    h = 19 if "temple" in mid else 31 if w == 37 else 35
    a = relief(rows, w, h, zlib.crc32(mid.encode()) % 2039)
    ok = ~np.isin(a, list("WR"))
    candidates = np.argwhere(ok)
    y, x = min(
        candidates, key=lambda p: abs(int(p[0]) - h // 2) + abs(int(p[1]) - w // 2)
    )
    g = np.where(a == "R", 1, np.where(a == "W", 2, np.where(a == "G", 11, 0))).astype(
        "uint8"
    )
    g[[0, -1], :] = 1
    g[:, [0, -1]] = 1
    m = {
        "name": name,
        "spawn": [int(x), int(y)],
        "style": "interior" if "temple" in mid else "route",
        "biome": (
            "cave"
            if np.count_nonzero(a == "C") > w * h * 0.1
            else "water" if sea else "snow" if np.any(a == "N") else "grass"
        ),
        "size": [w, h],
        "tiles": g.tolist(),
        "warps": [],
        "npcs": [],
        "objects": [],
        "hoenn_art": {"p": []},
        "galar_district": True,
        "encounter_rate": 0 if "temple" in mid else 0.045,
    }
    if sea:
        m["galar_water_approach"] = True
    return m, a


def paint_new(em, mid, m, a, plans, marks):
    seed = zlib.crc32(mid.encode())
    rng = Random(seed)
    h, w = a.shape
    sea = mid in NW
    safe = {tuple(m["spawn"])}
    paths = set()
    for entry in plans.values():
        for x, y in entry["path"] + [entry["at"]]:
            safe.add((x, y))
            paths.add((x, y))
            if a[y, x] == "R" or a[y, x] == "W" and not sea:
                a[y, x] = (
                    "N"
                    if m["biome"] == "snow"
                    else "C" if m["biome"] == "cave" else "S" if a[y, x] == "W" else "L"
                )
        for x, y in [entry["land"], entry["at"]]:
            if a[y, x] in "RW":
                a[y, x] = "S" if sea else "N" if m["biome"] == "snow" else "T"
    p = []
    fronts = {}
    # Landmarks use their authored locations; the walkable silhouette and props share a grid.
    for token in marks.split(","):
        key, ref = token.split("@")
        cx, cy = [int(n) for n in ref]
        aim = (round((w - 1) * cx / 10), round((h - 1) * cy / 10))
        cells = [
            (x, y)
            for y in range(3, h - 2)
            for x in range(3, w - 3)
            if (x, y) not in safe and a[y, x] not in "RW" and (x, y + 1) not in safe
        ]
        if not cells:
            continue
        x, y = min(cells, key=lambda p: abs(p[0] - aim[0]) + abs(p[1] - aim[1]))
        prop(p, key, x, y)
        fronts[key] = [x, y]
        safe.update([(x, y), (x, y + 1)])
    im = surface(em, a, seed)
    # Compact foot tracks fork away from a junction without turning an entire
    # natural district into a paved plaza. Water-bike routes retain open water.
    if not sea and "temple" not in mid:
        from PIL import ImageFilter, ImageChops

        track = Image.new("L", im.size, 0)
        pen = ImageDraw.Draw(track)
        for way in plans.values():
            centerline = [
                ((x + 0.5) * 16, (y + 0.5) * 16)
                for x, y in [m["spawn"]] + way["path"] + [way["at"]]
            ]
            if len(centerline) > 1:
                pen.line(
                    centerline,
                    fill=255,
                    width=12 if m["biome"] == "cave" else 15,
                    joint="curve",
                )
        track = track.filter(ImageFilter.GaussianBlur(3)).point(
            lambda n: 255 if n >= 120 else 0
        )
        surf = "N" if m["biome"] == "snow" else "C" if m["biome"] == "cave" else "T"
        from switch_fields.galar_streets import repeat

        track = ImageChops.multiply(
            track,
            Image.fromarray((~np.isin(a, list("WIR"))).astype("uint8") * 255).resize(
                im.size, Image.Resampling.NEAREST
            ),
        )
        im.paste(repeat(chip(em, surf), im.size), (0, 0), track)
    blades = Image.open(ROOT / "assets/galar/habitats/green.png").convert("RGBA")
    for y, x in np.argwhere(a == "G"):
        if (int(x), int(y)) not in paths and (x + y) % 4:
            im.paste(blades, (int(x) * 16, int(y) * 16), blades)
    grid = np.where(
        a == "R", 1, np.where(a == "W", 2, np.where(a == "G", 11, 0))
    ).astype("uint8")
    # Raised redoubt or monument floors, berry groves and shoreline niches mark the field edges.
    occupied = set()
    for _, x, y, _anchor in p:
        grid[y, x] = 1
        occupied.add((x, y))
    for y in range(2, h - 1):
        for x in range(1, w - 1):
            if (x, y) in safe or (x, y + 1) in safe or (x, y) in occupied:
                continue
            mat = a[y, x]
            if (
                mat in "FH"
                and y % 2 == 0
                and x % 2 == (y // 2) % 2
                and rng.random() < 0.76
            ):
                key = "tree" if mat == "F" else "mushwood"
            elif mat == "N" and rng.random() < 0.017:
                key = "fir"
            elif mat == "C" and rng.random() < 0.015:
                key = "rock"
            elif mat == "D" and rng.random() < 0.012:
                key = "cairn"
            else:
                continue
            # Never create one-tile invisible barriers in the signed crossing corridors.
            prop(p, key, x, y)
            grid[y, x] = 1
    grid[[0, -1], :] = 1
    grid[:, [0, -1]] = 1
    for entry in plans.values():
        for x, y in [entry["at"], entry["land"]]:
            grid[y, x] = 0
    for x, y in paths:
        if (x, y) not in occupied and grid[y, x] == 1:
            grid[y, x] = 0
    if "temple" in mid:
        grid[6:11, 10:14] = 0
        grid[5, 11] = 0
    for k, cell in fronts.items():
        if mid in ROOMS and ROOMS[mid][0] == k:
            room = ROOMS[mid][1]
            data, roomim, roomgrid, props = generated_room(em, mid, k, m, cell, "galar")
            scene(room, data, roomim, roomgrid, props)
            m["warps"].append(
                {
                    "at": cell,
                    "trigger": "door",
                    "to": {"region": "galar", "map": room, "at": data["spawn"]},
                }
            )
            # The native facade uses a two-to-three-tile-wide plinth, a central facing door.
            x, y = cell
            for i in range(x - 1, x + 2):
                grid[y, i] = 1
            grid[y + 1, x] = 0
    scene(mid, m, im, grid, p)


def open_legacy(em, mid, m, plans):
    grid = np.array(m["tiles"])
    art = ROOT / m["hoenn_art"]["scene"][0][6:]
    from galar_atlas.legacy import metadata, REV

    old = Image.open(art)
    tagged = old.info.get("GalarMapGround") == REV
    im = old.convert("RGB")
    d = ImageDraw.Draw(im)
    for spec in plans.values():
        path = spec["path"] + [spec["at"]]
        dx, dy = V[spec["side"]]
        for x, y in path:
            if grid[y, x] in [1, 2] or [x, y] == spec["at"]:
                mat = (
                    "N"
                    if mid.startswith("crown_")
                    else "C" if "cave" in mid or "mine" in mid else "T"
                )
                im.paste(chip(em, mat), (16 * x, 16 * y))
                grid[y, x] = 0
        x, y = spec["at"]
        cx, cy = x * 16 + 8, y * 16 + 8
        # A small pair of guide stones frames the threshold, with a clear walking gap.
        for side in [-1, 1]:
            px, py = cx + dy * side * 9, cy + dx * side * 9
            d.rounded_rectangle(
                (px - 2, py - 2, px + 2, py + 2), 1, fill="#b5aa8c", outline="#786f62"
            )
    m["tiles"] = grid.tolist()
    im.save(art, optimize=True, pnginfo=metadata() if tagged else None)
    write(mapfile(mid), m)


def build(em):
    names = {}
    new = {}
    maps = {}
    terrains = {}
    edges = defaultdict(dict)
    ports = {}
    for s in rows("sites.txt"):
        english, mid, *design = s.split("|")
        names[mid] = english
        if design:
            name, layout, marks = design
            new[mid] = marks
            maps[mid], terrains[mid] = new_data(mid, name, layout)
        else:
            maps[mid] = read(mapfile(mid))
        maps[mid]["warps"] = [w for w in maps[mid]["warps"] if not w.get("galar_atlas")]
    for s in rows("links.txt"):
        a, side, b = s.split()
        if any(w["to"]["map"] == b for w in maps[a]["warps"]) and any(
            w["to"]["map"] == a for w in maps[b]["warps"]
        ):
            continue
        edges[a][b] = side
        edges[b][a] = BACK[side]
    for mid, links in edges.items():
        ports[mid] = portals(
            mid, maps[mid], links, tuple(maps[mid]["spawn"]), terrains.get(mid)
        )
    for mid, plans in ports.items():
        m = maps[mid]
        for other, way in plans.items():
            m["warps"].append(
                {
                    "at": way["at"],
                    "trigger": DIR[way["side"]],
                    "galar_atlas": True,
                    "to": {
                        "region": other.split("_")[0],
                        "map": other,
                        "at": ports[other][mid]["land"],
                    },
                }
            )
        if mid in new:
            paint_new(em, mid, m, terrains[mid], plans, new[mid])
        else:
            m["galar_atlas_ports"] = plans
            open_legacy(em, mid, m, plans)
    for region in ["galar", "armor", "crown"]:
        f = MAPS / region / "region.json"
        r = read(f)
        for mid in sorted(list(new) + [v[1] for v in ROOMS.values()]):
            if mid.startswith(region + "_") and mid not in r["maps"]:
                r["maps"].append(mid)
        write(f, r)
    # Reuse the existing chapter milestones for every new physical entrance.
    early = read(ROOT / "content/galar_campaign.json")
    later = read(ROOT / "content/galar_later_campaign.json")
    south = {
        "galar_meetup",
        "galar_dappled",
        "galar_watchtower",
        "galar_axewell_west",
        "galar_miloch_south",
        "galar_miloch_north",
        "galar_meetup_station_room",
    }
    for mid in list(new) + [v[1] for v in ROOMS.values()]:
        if not mid.startswith("galar_"):
            continue
        if mid == "galar_axew_eye":
            rule = {
                "require": "g_water_bike",
                "message": "牙牙湖之眼在湖中，先取得能在水上行驶的洛托姆自行车。",
            }
        elif mid == "galar_outskirts":
            rule = later["gates"]["galar_mine2"]
        elif mid in south:
            rule = early["gates"]["galar_wild_south"]
        else:
            rule = later["gates"]["galar_wild_north"]
        later["gates"][mid] = rule
    (ROOT / "content/galar_later_campaign.json").write_text(
        json.dumps(later, ensure_ascii=False, indent=1) + "\n"
    )
    # Keep the established flags and rewards; move each investigation to its own original venue.
    events = read(ROOT / "content/galar_expansion.json")
    locations = {
        "dlc_steel": ("crown_iron_temple", [11, 5]),
        "dlc_rock": ("crown_rock_temple", [11, 5]),
        "dlc_ice": ("crown_ice_temple", [11, 5]),
        "dlc_plot_shadow": ("crown_cemetery", [23, 16]),
        "dlc_clues": ("crown_freezington_peony", [5, 3]),
        "dlc_report": ("crown_freezington_peony", [5, 3]),
        "dlc_reins": ("crown_freezington_mayor", [5, 3]),
    }
    for event in events:
        if event["id"] in locations:
            event["map"], event["at"] = locations[event["id"]]
    (ROOT / "content/galar_expansion.json").write_text(
        json.dumps(events, ensure_ascii=False, indent=1) + "\n"
    )
    from galar_atlas.legacy import apply

    apply(em)
    from galar_atlas.crown import build as build_crown_sites

    build_crown_sites(em, scene, ART)
    from galar_atlas.centers import build as build_centers

    build_centers(em)
    from galar_atlas.venues import build as build_venues

    build_venues(em)
    print(
        f"{len(new)} named districts, {len(ROOMS)} entered buildings, {sum(len(z) for z in ports.values())} directional exits"
    )


if __name__ == "__main__":
    build(Emerald(sys.argv[1]))
