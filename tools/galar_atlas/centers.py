"""Sword/Shield's ten service towns, including the branches in larger cities."""

import json

import numpy as np
from PIL import Image
from galar_atlas.art import ROOT
from switch_fields.rooms import donor
from bake_emerald_field import pack

# Relative to the district landmark or appropriate original exit, west to east.
LOTS = {
    "wedgehurst": [("lab", 0.67, 0.38)],
    "motostoke": [("west", 0.17, 0.39), ("south", 0.38, 0.67)],
    "turffield": [("main", 0.73, 0.70)],
    "hulbury": [("main", 0.26, 0.60)],
    "hammerlocke": [
        ("west", 0.22, 0.40),
        ("central", 0.48, 0.58),
        ("east", 0.82, 0.46),
    ],
    "stow": [("main", 0.74, 0.60)],
    "ballonlea": [("main", 0.46, 0.71)],
    "circhester": [("main", 0.27, 0.68)],
    "spikemuth": [("main", 0.15, 0.53)],
    "wyndon": [("south", 0.20, 0.63), ("stadium", 0.62, 0.29)],
}
TITLE = {
    "west": "西区",
    "central": "中央",
    "east": "东区",
    "south": "南区",
    "stadium": "竞技场前",
}


def save(p, m):
    p.write_text(json.dumps(m, ensure_ascii=False, separators=(",", ":")) + "\n")


def avoid_events():
    result = {}

    def scan(node):
        if isinstance(node, dict):
            if "map" in node and "at" in node:
                result.setdefault(str(node["map"]), set()).add(tuple(node["at"]))
            for v in node.values():
                scan(v)
        elif isinstance(node, list):
            for v in node:
                scan(v)

    for k in ["galar_campaign", "galar_later_campaign", "galar_expansion"]:
        scan(json.loads((ROOT / "content" / (k + ".json")).read_bytes()))
    return result


def build(em):
    folder = ROOT / "content/regions/galar"
    out = ROOT / "assets/galar/districts"
    events = avoid_events()
    native = "OldaleTown_PokemonCenter_1F"
    base, g, _ = donor(em, native)
    im = base.copy()
    grid = g.copy()
    # Replace Emerald's link-room staircase with a retail counter and supplies.
    panel = im.crop((2 * 16, 4 * 16, 3 * 16, 5 * 16))
    for y in range(2, 8):
        for x in range(0, 3):
            im.paste(panel, (16 * x, 16 * y))
            grid[y, x] = 0
    shop = Image.open(ROOT / "assets/emerald/field/officecounter_compact.png").convert(
        "RGBA"
    )
    im.paste(shop, (16, 6 * 16 - shop.height), shop)
    grid[5, 1:3] = 1
    grid[4, 2] = 0
    art = out / "galar_pokemon_center.png"
    im.save(art, optimize=True)
    regions = json.loads((folder / "region.json").read_bytes())
    for town, lots in LOTS.items():
        mid = "galar_" + town
        f = folder / "maps" / (mid + ".json")
        m = json.loads(f.read_bytes())
        w, h = m["size"]
        occ = np.array(m["tiles"])
        for label, fx, fy in lots:
            room = mid + "_center_" + label
            existing = next((v for v in m["warps"] if v["to"]["map"] == room), None)
            if existing:
                x, y = existing["at"]
            else:
                avoid = set(events.get(mid, set())) | {tuple(m["spawn"])}
                for k in ["npcs", "objects", "warps"]:
                    avoid.update(tuple(v["at"]) for v in m[k])
                for v in m["warps"]:
                    if v.get("trigger") == "door":
                        avoid.add((v["at"][0], v["at"][1] + 1))
                footprints = np.zeros((h, w), bool)
                for uri, px, py, *rest in m["hoenn_art"]["p"]:
                    if not isinstance(uri, str):
                        continue
                    asset = ROOT / (
                        uri[6:]
                        if uri.startswith("res://")
                        else "assets/emerald/field/" + uri + ".png"
                    )
                    if not asset.exists():
                        continue
                    width, height = Image.open(asset).size
                    ax, ay = rest[0] if rest else (width // 2, height)
                    l, r = (px * 16 + 8 - ax) // 16, (
                        px * 16 + 8 - ax + width - 1
                    ) // 16
                    t, b = ((py + 1) * 16 - ay) // 16, py
                    footprints[max(0, t) : min(h, b + 1), max(0, l) : min(w, r + 1)] = (
                        True
                    )
                options = []
                for y0 in range(5, h - 3):
                    for x0 in range(2, w - 4):
                        # Facade is four cells wide, with a left-of-centre Emerald door.
                        if footprints[y0 - 3 : y0 + 1, x0 - 1 : x0 + 3].any():
                            continue
                        if town == "wyndon" and label == "south" and x0 >= 13:
                            continue
                        if np.any(occ[y0 - 3 : y0 + 2, x0 - 2 : x0 + 4] == 2):
                            continue
                        if any(
                            (xx, yy) in avoid
                            for yy in range(y0 - 2, y0 + 2)
                            for xx in range(x0 - 1, x0 + 3)
                        ):
                            continue
                        if np.any(
                            np.isin(occ[y0 - 2 : y0 + 2, x0 - 1 : x0 + 3], [1, 2, 6, 7])
                        ):
                            continue
                        options.append((abs(x0 - w * fx) + abs(y0 - h * fy), x0, y0))
                if not options:
                    raise RuntimeError(("no dry lot", mid, label))
                _, x, y = min(options)
                m["warps"].append(
                    {
                        "at": [x, y],
                        "trigger": "door",
                        "galar_center": True,
                        "to": {"region": "galar", "map": room, "at": [7, 7]},
                    }
                )
            data = {
                "name": m["name"] + "・" + TITLE.get(label, "") + "宝可梦中心",
                "size": [14, 9],
                "tiles": grid.tolist(),
                "spawn": [7, 7],
                "style": "interior",
                "biome": "interior",
                "npcs": [
                    {"at": [7, 2], "name": "护士", "gfx": "nurse", "heal": True},
                    {"at": [2, 4], "name": "商店店员", "gfx": "clerk", "shop": True},
                ],
                "objects": [],
                "warps": [
                    {
                        "at": [u, 8],
                        "trigger": "down",
                        "to": {"region": "galar", "map": mid, "at": [x, y + 1]},
                    }
                    for u in [6, 7]
                ],
                "hoenn_art": {
                    "s": [14, 9],
                    "t": pack(np.zeros((9, 14), dtype="<u2")),
                    "p": [],
                    "scene": ["res://assets/galar/districts/" + art.name, 0, 0],
                },
            }
            save(folder / "maps" / (room + ".json"), data)
            if not any(
                p[0] == "center" and p[1:3] == [x, y] for p in m["hoenn_art"]["p"]
            ):
                m["hoenn_art"]["p"].append(["center", x, y, [24, 64]])
            occ[y - 1 : y + 1, x - 1 : x + 3] = 1
            if room not in regions["maps"]:
                regions["maps"].append(room)
        m["tiles"] = occ.tolist()
        save(f, m)
    save(folder / "region.json", regions)
