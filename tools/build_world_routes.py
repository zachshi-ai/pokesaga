"""Build the explorable nine-region atlas from named itineraries and terrain layouts.

Run after the legacy Kanto, Johto, Sevii, Hoenn and Frontier map stages. Only
atlas-owned exits and guides are refreshed on those existing maps. Coordinates
are in walkable tiles; regional chart coordinates use a 0–100 scale.
"""

import argparse
import json
import math
import re
from collections import defaultdict, deque
from pathlib import Path

from asset_paths import project_path
from world_layouts import SIDE, Layout, distance, stable
from world_returns import restore_returns

ROOT = Path(project_path())
SOURCE = Path(__file__).parent / "world/regions.txt"
OLD = {
    "kanto": (
        "kanto_main",
        "真新镇",
        [72, 277],
        [72, 276],
        [71, 279],
        [71, 278],
        "south_walk",
    ),
    "johto": (
        "johto_new_bark_town",
        "若叶镇",
        [7, 5],
        [7, 4],
        [3, 7],
        [4, 7],
        "east_walk",
    ),
    "hoenn": ("littleroot_town", "未白镇", [10, 17], [11, 17], None, None, None),
    "sevii": (
        "one_island_harbor",
        "一之岛港",
        [8, 3],
        [8, 4],
        [1, 3],
        [2, 3],
        "island_walk",
    ),
    "frontier": (
        "harbor",
        "对战开拓区码头",
        [14, 15],
        [15, 15],
        [6, 8],
        [7, 8],
        "isle_walk",
    ),
}
SEVII_PORTS = (
    ("one", "一", (23, 24)),
    ("two", "二", (42, 20)),
    ("three", "三", (67, 23)),
    ("four", "四", (38, 42)),
    ("five", "五", (72, 52)),
    ("six", "六", (76, 76)),
    ("seven", "七", (39, 81)),
)
SEVII_BANKS = (
    "火照海堤",
    "歧波礁桥",
    "索桥湾海堤",
    "冻瀑外湾步道",
    "回忆之塔海堤",
    "溪谷海堤",
)
JOHTO_ROADS = dict(
    zip(
        range(26, 47),
        (
            (94, 61),
            (94, 75),
            (93, 47),
            (76, 74),
            (69, 60),
            (67, 45),
            (64, 60),
            (55, 80),
            (42, 67),
            (40, 42),
            (51, 40),
            (46, 34),
            (32, 27),
            (24, 37),
            (15, 51),
            (9, 58),
            (55, 28),
            (67, 20),
            (77, 28),
            (86, 45),
            (81, 57),
        ),
    )
)
# Each interregional link has an actual middle map. Its two separated entrances
# face the termini, so walking the link requires crossing real terrain.
LINKS = [
    ("kanto/south_walk", "johto/east_walk", "石英沿岸步道", "coast"),
    ("frontier/isle_walk", "hoenn/dewford", "武斗岛外海栈道", "coast"),
    ("kanto/south_walk", "frontier/isle_walk", "开拓群岛防波堤", "coast"),
    ("johto/east_walk", "hoenn/fallarbor", "丰城海峡连廊", "coast"),
    ("johto/east_walk", "sinnoh/twinleaf", "心齐湖峡谷联络道", "forest"),
    ("kanto/south_walk", "sinnoh/canalave", "水脉海底人行隧道", "cave"),
    ("galar/hammerlocke", "kalos/cyllage", "伽勒尔海峡隧道", "cave"),
    ("kalos/couriway", "paldea/n3", "连理山口", "highland"),
    ("paldea/marinada", "unova/undella", "涟漪海堤", "coast"),
    ("unova/virbank", "alola/hauoli", "美乐美乐群岛长桥", "coast"),
    ("unova/icirrus", "galar/wedgehurst", "北海石脊古道", "highland"),
    ("kanto/south_walk", "unova/aspertia", "桧扇群山古道", "highland"),
    ("alola/seafolk", "hoenn/pacifidlog", "南洋浮桥群", "coast"),
    ("kanto/south_walk", "sevii/island_walk", "七岛海滨栈桥", "coast"),
    ("kanto/south_walk", "orange/valencia", "橘子群岛礁盘长堤", "coast"),
    ("galar/wedgehurst", "armor/fields", "铠岛防波堤", "coast"),
    ("galar/wedgehurst", "crown/freezington", "王冠雪线隧道", "snow"),
    ("paldea/mesagoza", "kitakami/road", "北上山岭古道", "highland"),
    ("unova/undella", "blueberry/academy", "蓝莓海底观景廊", "interior"),
    ("alola/hano", "aether/dock", "以太浮台连廊", "coast"),
    ("sinnoh/celestic", "hisui/jubilife", "时空遗迹步廊", "ruins"),
    ("sinnoh/spring", "distortion/threshold", "送泉裂隙步径", "space"),
    ("alola/altar", "ultra/megalopolis", "究极之洞光桥", "space"),
    ("unova/dreamyard", "dream/village", "梦烟小径", "forest"),
]
# Main field pools use actual species IDs and the existing encounter schema.
FAUNA = {
    "hoenn": [261, 263, 265, 278],
    "sinnoh": [396, 399, 403, 406],
    "unova": [504, 506, 519, 540],
    "kalos": [659, 661, 664, 672],
    "alola": [731, 734, 736, 742],
    "galar": [819, 821, 824, 827],
    "paldea": [915, 917, 921, 928],
    "hisui": [399, 396, 403, 418],
    "armor": [403, 427, 661, 619],
    "crown": [361, 582, 615, 459],
    "kitakami": [261, 273, 193, 840],
    "blueberry": [203, 328, 459, 456],
    "orange": [54, 60, 90, 116],
    "dream": [517, 96, 280, 425],
    "aether": [734, 742, 764, 753],
}
HUB = {
    "sinnoh": "twinleaf",
    "unova": "nuvema",
    "kalos": "vaniville",
    "alola": "hauoli",
    "galar": "postwick",
    "paldea": "mesagoza",
    "orange": "valencia",
    "armor": "fields",
    "crown": "freezington",
    "kitakami": "mossui",
    "blueberry": "central",
    "aether": "dock",
    "hisui": "jubilife",
    "distortion": "threshold",
    "ultra": "megalopolis",
    "dream": "village",
}
REGIONAL_ROADS = {
    "hoenn": {
        "coast": "105 106 107 108 109 122 124 125 126 127 128 129 130 131 132 133 134",
        "forest": "104 119 120",
        "volcano": "112 113",
        "desert": "111",
        "highland": "114 115",
    },
    "sinnoh": {
        "coast": "218 219 220 221 222 223 226 230",
        "snow": "216 217",
        "forest": "205 210",
        "highland": "207 208 211 227 228",
        "marsh": "212 213",
    },
    "unova": {
        "coast": "17 18 21",
        "highland": "7 9 10 11 23",
        "forest": "12 15 16 20",
        "desert": "4",
        "marsh": "8",
    },
    "kalos": {
        "coast": "8 12 13",
        "forest": "2 14 15 20",
        "highland": "9 10 18 19 21",
        "snow": "17",
    },
    "alola": {
        "coast": "7 9 14 15 16",
        "forest": "2 4 5 8 11 17",
        "volcano": "12",
        "desert": "13",
        "highland": "3 10",
    },
    "galar": {"highland": "3 6", "forest": "4 5", "coast": "9", "snow": "8 10"},
}
TOWN_CN = {
    "CINNABAR_ISLAND": "红莲镇",
    "INDIGO_PLATEAU_EXTERIOR": "石英高原",
    "FUCHSIA_CITY": "浅红市",
    "SAFFRON_CITY": "金黄市",
    "CELADON_CITY": "玉虹市",
    "LAVENDER_TOWN": "紫苑镇",
    "VERMILION_CITY": "枯叶市",
}
JOHTO_TOWNS = {
    "new_bark_town": (85, 73),
    "cherrygrove_city": (68, 73),
    "violet_city": (65, 43),
    "azalea_town": (46, 80),
    "goldenrod_city": (40, 57),
    "ecruteak_city": (41, 28),
    "olivine_city": (22, 50),
    "cianwood_city": (7, 69),
    "mahogany_town": (66, 27),
    "blackthorn_city": (88, 28),
}


def read(path):
    return json.loads(path.read_text())


def save(path, data, compact=False):
    raw = json.dumps(
        data,
        ensure_ascii=False,
        **({"separators": (",", ":")} if compact else {"indent": 1}),
    )
    if path.exists() and path.read_text() == raw:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(raw)


def map_path(region, mid):
    return ROOT / "content/regions" / region / "maps" / (mid + ".json")


def make_node(region, token, name, biome, kind, blurb="", pos=None):
    return {
        "key": region + "/" + token,
        "region": region,
        "token": token,
        "map": region + "_" + token,
        "name": name,
        "biome": biome,
        "kind": kind,
        "blurb": blurb,
        "pos": pos,
    }


def parse():
    nodes = {}
    edges = []
    region = ""
    for line in SOURCE.read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        if line.startswith("["):
            region = line.strip("[]")
            continue
        if line.startswith("="):
            tokens = line[1:].split()
            for token in tokens:
                if token.isdigit() and region + "/" + token not in nodes:
                    biome = next(
                        (
                            b
                            for b, road_ids in REGIONAL_ROADS.get(region, {}).items()
                            if token in road_ids.split()
                        ),
                        "grass",
                    )
                    nodes[region + "/" + token] = make_node(
                        region, token, token + "号道路", biome, "route"
                    )
            edges.extend(
                (region + "/" + a, region + "/" + b)
                for a, b in zip(tokens, tokens[1:])  # noqa: RUF007 (Python 3.9)
            )
            continue
        parts = line.split("|")
        token, name, biome, kind = parts[:4]
        pt = list(map(int, parts[5].split(","))) if len(parts) > 5 else None
        node = make_node(
            region, token, name, biome, kind, parts[4] if len(parts) > 4 else "", pt
        )
        if node["key"] in nodes:
            raise ValueError("Duplicate location " + node["key"])
        nodes[node["key"]] = node
    for region, (mid, name, _, _, _, _, token) in OLD.items():
        node = make_node(region, "original", name, "grass", "town", pos=[45, 55])
        node.update(map=mid, original=True)
        nodes[node["key"]] = node
        if token:
            edges.append((node["key"], region + "/" + token))
    for i, (token, label, xy) in enumerate(SEVII_PORTS):
        port = "sevii/original" if i == 0 else "sevii/" + token + "_port"
        if i:
            n = make_node(
                "sevii",
                token + "_port",
                label + "之岛港",
                "coast",
                "town",
                pos=list(xy),
            )
            n.update(map=token + "_island_harbor", original=True)
            nodes[port] = n
        if i < len(SEVII_BANKS):
            trail = make_node(
                "sevii", "causeway_" + token, SEVII_BANKS[i], "coast", "route"
            )
            nodes[trail["key"]] = trail
            edges.extend(
                [
                    (port, trail["key"]),
                    (trail["key"], "sevii/" + SEVII_PORTS[i + 1][0] + "_port"),
                ]
            )
    node = make_node("hoenn", "101", "101号道路", "grass", "route", pos=[17, 83])
    node.update(map="route101", original=True)
    nodes[node["key"]] = node
    edges.extend([("hoenn/original", "hoenn/101"), ("hoenn/101", "hoenn/oldale")])
    for a, b, label, biome in LINKS:
        region = a.split("/")[0]
        token = "pass_" + b.replace("/", "_")
        node = make_node(region, token, label, biome, "crossing")
        nodes[node["key"]] = node
        edges.extend([(a, node["key"]), (node["key"], b)])
    lookup = defaultdict(list)
    for a, b in edges:
        if a not in nodes or b not in nodes:
            raise ValueError(f"unknown itinerary point {a} / {b}")
        if a == b:
            raise ValueError("self loop " + a)
        if b not in lookup[a]:
            lookup[a].append(b)
            lookup[b].append(a)
    for key in nodes:
        if not lookup[key]:
            raise ValueError("Unconnected " + key)
    return nodes, lookup


def position_nodes(nodes, links):
    for region in sorted({n["region"] for n in nodes.values()}):
        subset = [k for k, n in nodes.items() if n["region"] == region]
        fixed = {k for k in subset if nodes[k]["pos"]}
        if len(fixed) < 2:
            for i, k in enumerate(subset[:: max(1, len(subset) // 4)][:4]):
                if k not in fixed:
                    nodes[k]["pos"] = [(20, 65, 78, 32)[i], (30, 24, 69, 77)[i]]
                    fixed.add(k)
        for key in subset:
            if key not in fixed:
                nodes[key]["pos"] = [
                    15 + stable(key + "x") % 72,
                    15 + stable(key + "y") % 72,
                ]
        # Local repulsion separates labels; each declared trail still attracts its endpoints.
        for frame in range(110):
            for key in subset:
                if key in fixed:
                    continue
                x, y = nodes[key]["pos"]
                rx = ry = 0
                for other in subset:
                    if other == key:
                        continue
                    ox, oy = nodes[other]["pos"]
                    dx, dy = x - ox, y - oy
                    if dx == dy == 0:
                        dx = 1
                    sq = max(dx * dx + dy * dy, 4)
                    rx += dx / sq * 4.2
                    ry += dy / sq * 4.2
                for other in links[key]:
                    if nodes[other]["region"] != region:
                        continue
                    ox, oy = nodes[other]["pos"]
                    rx += (ox - x) * 0.09
                    ry += (oy - y) * 0.09
                nodes[key]["pos"] = [
                    max(4, min(96, x + max(-1, min(rx, 1)))),
                    max(4, min(96, y + max(-1, min(ry, 1)))),
                ]
        for k in subset:
            nodes[k]["pos"] = [round(v) for v in nodes[k]["pos"]]


def place_angle(name, other):
    if name["region"] != other["region"]:
        return stable(other["key"]) % 360 * math.pi / 180
    return math.atan2(
        other["pos"][1] - name["pos"][1], other["pos"][0] - name["pos"][0]
    )


def load_existing(nodes, layouts):
    for key, n in nodes.items():
        if not n.get("original"):
            continue
        data = read(map_path(n["region"], n["map"]))
        data["npcs"] = [p for p in data.get("npcs", []) if p.get("atlas") != "world"]
        data["warps"] = [p for p in data.get("warps", []) if p.get("atlas") != "world"]
        layouts[key] = data


def legacy_stand(data, target):
    meta = (
        read(ROOT / "content/emerald_maps" / (data["emerald"] + ".json"))
        if data.get("emerald")
        else {}
    )
    g = meta.get("collision", data.get("tiles", []))
    taken = {tuple(w["at"]) for w in data.get("warps", []) + data.get("npcs", [])}
    taken.update(
        tuple(o["at"])
        for o in data.get("objects", [])
        if o["kind"] in {"sign", "cut", "rock", "boulder", "berry_tree"}
    )

    def dry(x, y):
        if not (0 <= y < len(g) and 0 <= x < len(g[y])) or (x, y) in taken:
            return False
        if g[y][x] != 0 if meta else g[y][x] in (1, 2, 6, 7):
            return False
        return all(
            not meta.get(layer) or not meta[layer][y][x]
            for layer in ("water", "ledge", "deep", "dirblock", "hole", "climb")
        )

    xx, yy = target
    for ring in range(max(len(g), len(g[0]))):
        for dy in range(-ring, ring + 1):
            dx = ring - abs(dy)
            for x in dict.fromkeys((xx + dx, xx - dx)):
                y = yy + dy
                if dry(x, y) and any(dry(x + a, y + b) for a, b in SIDE):
                    return [x, y]
    raise ValueError("No walkable landing in " + data["name"])


def legacy_chart(region, locs, connections):
    """Include existing towns and roads, using their real map rectangles/warp adjacencies."""
    if region == "kanto":
        m = read(map_path("kanto", "kanto_main"))
        meta = read(ROOT / "content/emerald_maps/kanto_main.json")
        w, h = m["size"]
        # A rectangular zone's centre may be a rock, house or water tile.
        blocked = {
            tuple(a["at"])
            for a in m["npcs"] + m["warps"] + m.get("objects", [])
            if "at" in a
        }
        rects = []
        for idx, a in enumerate(m["areas"]):
            raw = a["name"]
            cn = TOWN_CN.get(raw, raw)
            if cn == "SAFFRON_CITY_CONNECTION":
                continue
            if raw.startswith("ROUTE"):
                num = re.search(r"\d+", raw)[0]
                cn = (
                    num
                    + "号道路"
                    + (
                        "北段"
                        if raw.endswith("NORTH")
                        else "南段"
                        if raw.endswith("SOUTH")
                        else ""
                    )
                )
            if raw == "真新镇":
                rects.append((locs[0]["id"], a))
                continue
            if "_" in cn:
                continue
            x0, y0, x1, y1 = [a[s] for s in ["x0", "y0", "x1", "y1"]]
            cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
            candidates = [
                (x, y)
                for y in range(max(0, y0), min(h, y1))
                for x in range(max(0, x0), min(w, x1))
                if not meta["collision"][y][x]
                and not meta["water"][y][x]
                and not meta["ledge"][y][x]
                and (x, y) not in blocked
            ]
            if not candidates:
                continue
            xy = min(candidates, key=lambda p: distance(p, (cx, cy)))
            mid = "kanto_area_" + str(idx)
            rects.append((mid, a))
            locs.append(
                {
                    "id": mid,
                    "name": cn,
                    "kind": "route" if "道路" in cn else "city",
                    "map": "kanto_main",
                    "at": list(xy),
                    "pos": [round(xy[0] * 100 / w), round(xy[1] * 100 / h)],
                }
            )
        for i, (ida, a) in enumerate(rects):
            for idb, b in rects[i + 1 :]:
                touch_x = (a["x1"] == b["x0"] or b["x1"] == a["x0"]) and min(
                    a["y1"], b["y1"]
                ) > max(a["y0"], b["y0"])
                touch_y = (a["y1"] == b["y0"] or b["y1"] == a["y0"]) and min(
                    a["x1"], b["x1"]
                ) > max(a["x0"], b["x0"])
                if touch_x or touch_y:
                    connections.append([ida, idb])
    elif region in ("johto", "sevii"):
        paths = {p.stem: p for p in map_path(region, "_").parent.glob("*.json")}
        if region == "johto":
            wanted = {
                k
                for k in paths
                if k.removeprefix("johto_") in JOHTO_TOWNS
                or re.fullmatch(r"johto_route_(?:2[6-9]|[34]\d)", k)
            }
        else:
            wanted = {
                k
                for k in paths
                if re.fullmatch(
                    r"(?:one|two|three|four|five|six|seven)_island(?:_harbor)?", k
                )
            }
        known = {r["map"]: r["id"] for r in locs}
        ports = {token: (label, xy) for token, label, xy in SEVII_PORTS}
        for mid in sorted(wanted):
            d = read(paths[mid])
            if mid not in known:
                xy = legacy_stand(d, d["spawn"])
                if region == "johto":
                    token = mid.removeprefix("johto_")
                    pxy = (
                        JOHTO_ROADS[int(token[6:])]
                        if token.startswith("route_")
                        else JOHTO_TOWNS[token]
                    )
                    label = d["name"]
                else:
                    title, anchor = ports[mid.split("_")[0]]
                    pxy = (anchor[0] + 2, anchor[1] - 7)
                    label = title + "之岛"
                locs.append(
                    {
                        "id": mid,
                        "name": label,
                        "map": mid,
                        "at": xy,
                        "kind": "route" if "route_" in mid else "town",
                        "pos": list(pxy),
                    }
                )
                known[mid] = mid
        # An original tunnel, gatehouse or port may lie between two labelled places.
        # Collapse its unlabelled steps to the first labelled destinations only.
        original = {
            k: read(p)
            for k, p in paths.items()
            if not k.startswith(region + "_pass_")
            and not k.startswith(region + "_causeway_")
        }
        for mid in sorted(wanted):
            queued = deque([mid])
            seen = {mid}
            while queued:
                here = queued.popleft()
                for door in original[here].get("warps", []):
                    to = door["to"]
                    dest = to["map"]
                    if "recall_passage" in to or "remember_passage" in to:
                        continue
                    if to["region"] != region or dest in seen or dest not in original:
                        continue
                    seen.add(dest)
                    if dest in wanted:
                        if mid != dest:
                            connections.append([known[mid], known[dest]])
                    elif dest not in known:
                        queued.append(dest)
    elif region == "hoenn":
        d = read(map_path(region, "demo_town"))
        locs.append(
            {
                "id": "demo_town",
                "name": d["name"],
                "map": "demo_town",
                "at": legacy_stand(d, d["spawn"]),
                "kind": "town",
                "pos": [8, 86],
            }
        )
        connections.append(["littleroot_town", "demo_town"])
    elif region == "frontier":
        d = read(map_path(region, "tower_lobby"))
        locs.append(
            {
                "id": "tower_lobby",
                "name": "对战塔大厅",
                "map": "tower_lobby",
                "at": legacy_stand(d, d["spawn"]),
                "kind": "facility",
                "pos": [56, 26],
            }
        )
        connections.append(["harbor", "tower_lobby"])


def build():
    restore_returns(ROOT / "content/regions", save, legacy_stand)
    graph = read(ROOT / "content/world_graph.json")
    names = {k: v["name"] for k, v in graph["regions"].items()}
    names.update({r["id"]: r["name"] for r in graph["specials"]})
    nodes, edges = parse()
    position_nodes(nodes, edges)
    layouts = {}
    gates = {}
    regions = {}
    for r, name in names.items():
        path = ROOT / "content/regions" / r / "region.json"
        if path.exists():
            regions[r] = read(path)
        else:
            pool = FAUNA.get(r, [])
            n = len(pool)
            regions[r] = {
                "id": r,
                "name": name,
                "tileset": "world",
                "music": "route",
                "maps": [],
                "encounters": [
                    {"species": s, "min": 5, "max": 12, "weight": [40, 30, 20, 10][i]}
                    for i, s in enumerate(pool)
                ],
                "encounter_rate": 0.08 if n else 0,
            }
    load_existing(nodes, layouts)
    for k, n in nodes.items():
        if n.get("original"):
            continue
        others = [
            (
                o,
                nodes[o]["name"],
                place_angle(n, nodes[o]),
                nodes[o]["kind"],
                nodes[o]["biome"],
            )
            for o in edges[k]
        ]
        layout = Layout(n, others)
        layouts[k] = layout.output(regions[n["region"]])
        gates[k] = layout.gates
    for r, (mid, name, spawn, npc, at, landing, token) in OLD.items():
        if token:
            gates[r + "/original"] = {r + "/" + token: (at, landing)}
    # Walkways leave from the free east and west ends of each original harbour pier.
    for i, (token, _, _) in enumerate(SEVII_PORTS):
        key = "sevii/original" if i == 0 else "sevii/" + token + "_port"
        exits = gates.setdefault(key, {})
        if i:
            exits["sevii/causeway_" + SEVII_PORTS[i - 1][0]] = ([0, 3], [1, 3])
        if i < len(SEVII_BANKS):
            exits["sevii/causeway_" + token] = ([15, 3], [14, 3])
    gates["hoenn/101"] = {"hoenn/oldale": ([9, 0], [9, 1])}
    for key, others in edges.items():
        room = layouts[key]
        for dest in others:
            if {key, dest} == {"hoenn/101", "hoenn/original"}:
                continue
            target = nodes[dest]
            warp, arrival = gates[key][dest][0], gates[dest][key][1]
            if any(w["at"] == warp for w in room["warps"]):
                raise ValueError(f"Overlapping gate {key} {warp}")
            room["warps"].append(
                {
                    "at": warp,
                    "to": {
                        "region": target["region"],
                        "map": target["map"],
                        "at": arrival,
                    },
                    "atlas": "world",
                }
            )
    out = {"version": 1, "regions": {}, "passages": []}
    for r, name in names.items():
        hub_key = r + "/original" if r in OLD else r + "/" + HUB[r]
        hub_node = nodes[hub_key]
        hub_room = layouts[hub_key]
        if r in OLD:
            landing, npc_at = OLD[r][2:4]
        else:
            landing = hub_room["spawn"]
            npc_at = [landing[0] + 1, landing[1]]
        if any(p["at"] == npc_at for p in hub_room["npcs"]):
            raise ValueError("NPC occupied: " + r)
        hub_room["npcs"].append(
            {
                "name": "领航员",
                "gfx": "navigator",
                "transit": True,
                "at": npc_at,
                "atlas": "world",
            }
        )
        hub = {"region": r, "map": hub_node["map"], "at": landing, "npc_at": npc_at}
        rr = regions[r]
        if r not in OLD:
            rr["start"] = {"map": hub["map"], "at": landing}
        locs = []
        connections = []
        for key in [hub_key] + sorted(
            k for k in nodes if k != hub_key and nodes[k]["region"] == r
        ):
            n = nodes[key]
            d = layouts[key]
            mid = n["map"]
            if mid not in rr["maps"]:
                rr["maps"].append(mid)
            old = map_path(r, mid)
            compact = (not n.get("original")) or (
                old.exists() and old.read_text().startswith('{"')
            )
            save(old, d, compact)
            pos = n["pos"]
            if key == "kanto/original":
                pos = [18, 68]
            if key == "johto/original":
                pos = list(JOHTO_TOWNS["new_bark_town"])
            if key == "hoenn/original":
                pos = [20, 92]
            if key == "sevii/original":
                pos = list(SEVII_PORTS[0][2])
            spot = (
                landing
                if key == hub_key
                else legacy_stand(d, d["spawn"])
                if n.get("original")
                else d["spawn"]
            )
            locs.append(
                {
                    "id": mid,
                    "name": n["name"],
                    "kind": n["kind"],
                    "map": mid,
                    "at": spot,
                    "pos": pos,
                }
            )
            for other in edges[key]:
                if nodes[other]["region"] == r and key < other:
                    connections.append([mid, nodes[other]["map"]])
        legacy_chart(r, locs, connections)
        # Keep each point individually selectable even where routes reach a map corner.
        occupied = set()
        for loc in locs:
            xy = tuple(loc["pos"])
            if xy in occupied:
                options = [
                    (x, y)
                    for x in range(3, 98)
                    for y in range(3, 98)
                    if (x, y) not in occupied
                ]
                xy = min(
                    options, key=lambda p: (distance(p, xy), distance(p, (50, 50)))
                )
                loc["pos"] = list(xy)
            occupied.add(xy)
        # Legacy generators registered only a subset. Preserve their order for
        # old bookmarks, then include every actual map exactly once.
        folder = map_path(r, "_").parent
        actual = {p.stem for p in folder.glob("*.json")}
        rr["maps"] = list(dict.fromkeys(m for m in rr["maps"] if m in actual))
        rr["maps"].extend(sorted(actual - set(rr["maps"])))
        save(ROOT / "content/regions" / r / "region.json", rr)
        connections = [
            list(pair) for pair in sorted({tuple(sorted(c)) for c in connections})
        ]
        out["regions"][r] = {
            "name": name,
            "hub": hub,
            "locations": locs,
            "connections": connections,
        }
    for a, b, label, _ in LINKS:
        reg = a.split("/")[0]
        crossing = nodes[reg + "/pass_" + b.replace("/", "_")]
        out["passages"].append(
            {
                "a": a.split("/")[0],
                "b": b.split("/")[0],
                "name": label,
                "via": {"region": reg, "map": crossing["map"]},
                "from": {"region": reg, "map": nodes[a]["map"]},
                "to": {"region": nodes[b]["region"], "map": nodes[b]["map"]},
            }
        )
    # The chart and its preview use these same physical passages, including islands
    # and other layers which do not have a main-region plate coordinate.
    pairs = {frozenset((p["a"], p["b"])): p for p in out["passages"]}
    for r in graph["regions"].values():
        r["status"] = "已开放"
    for special in graph["specials"]:
        p = pairs[frozenset((special["parent"], special["id"]))]
        special.update(
            status="已开放", access="walk", walkway=p["via"], walk_label=p["name"]
        )
    graph["access_types"]["walk"] = "连续步行通道"
    graph["layers"]["L1"] = "地理附属区。可经各自的海堤、栈道、山道或隧道往返主地区。"
    graph["layers"]["L2"] = "异层地区。可从现世的裂隙、遗迹或梦境入口步行往返。"
    terrain_by_label = {label: biome for _, _, label, biome in LINKS}
    for link in graph["links"]:
        p = pairs.get(frozenset((link["a"], link["b"])))
        if p:
            terrain = terrain_by_label[p["name"]]
            kind = (
                "sea"
                if terrain == "coast"
                else "tunnel"
                if terrain in ("cave", "interior")
                else "land"
            )
            link.update(
                status="已开放",
                walkway=p["via"],
                label=p["name"],
                walk_label=p["name"],
                kind=kind,
            )
        elif link.get("via") == "frontier":
            link.update(
                status="已开放", label="经开拓群岛防波堤与武斗岛外海栈道", kind="sea"
            )
    graph["regions"]["hoenn"]["scope"] = "未白镇至彩幽市，101至134号道路及主要地标"
    graph["note"] = (
        "九个主地区、八个附属地区与四个异层地区均可步行探索。地区地点与步行通道见 world_destinations.json。"
    )
    graph["axes"][0]["note"] = "经海滨、峡谷和联络步道往返东亚各地区。"
    graph["axes"][1]["note"] = "经海峡隧道与山口步行连接。"
    graph["axes"][2]["note"] = "跨区栈桥和长堤连接陆地、海岸与群岛。"
    save(ROOT / "content/world_graph.json", graph)
    save(ROOT / "content/world_destinations.json", out, True)
    print(
        f"{len(regions)} regions, {len(nodes)} named map nodes, {len(out['passages'])} walkable interregional passages"
    )


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--project", type=Path, default=ROOT)
    args = p.parse_args()
    ROOT = args.project.resolve()
    build()
