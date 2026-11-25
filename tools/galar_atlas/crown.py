"""Ballimere Lake, the berry tree on its island and Freezington's two story houses."""

import json

import numpy as np
from PIL import Image, ImageDraw
from galar_atlas.art import ROOT, prop, surface
from switch_fields.rooms import generated_room
from switch_fields.terrain import relief


def tree(art):
    """Layer branches and several crowns of native Emerald leaves at the tree's real scale."""
    im = Image.new("RGBA", (124, 125))
    d = ImageDraw.Draw(im)
    d.ellipse((28, 104, 100, 122), fill=(62, 70, 51, 90))
    d.polygon(
        [
            (38, 119),
            (50, 106),
            (52, 84),
            (38, 73),
            (26, 59),
            (32, 53),
            (52, 68),
            (59, 76),
            (63, 54),
            (70, 54),
            (71, 77),
            (91, 60),
            (95, 65),
            (78, 90),
            (76, 106),
            (91, 120),
            (70, 115),
            (61, 123),
            (56, 114),
        ],
        fill="#62515a",
        outline="#44434b",
    )
    d.line([(61, 113), (64, 96), (63, 80), (52, 73)], fill="#91716a", width=4)
    d.line([(74, 109), (70, 98), (73, 89), (85, 74)], fill="#8b6666", width=3)
    base = Image.open(ROOT / "assets/emerald/field/tree.png").convert("RGBA")
    base = base.crop((0, 0, base.width, base.height - 11))
    pp = np.array(base)
    rgb = pp[:, :, :3]
    pal = sorted(
        {tuple(c) for c in rgb[pp[:, :, 3] > 0]}, key=lambda c: sum(map(int, c))
    )
    colors = [
        "#4f4858",
        "#664d62",
        "#81566d",
        "#a75f79",
        "#c97789",
        "#d9949f",
        "#e5afb0",
    ]
    for i, c in enumerate(pal):
        z = np.all(rgb == c, axis=2)
        rgb[z] = tuple(
            bytes.fromhex(colors[round(i * (len(colors) - 1) / (len(pal) - 1))][1:])
        )
    leaf = Image.fromarray(pp)
    for x, y in [
        (11, 26),
        (28, 11),
        (44, 1),
        (65, 6),
        (84, 20),
        (0, 43),
        (18, 50),
        (34, 34),
        (51, 23),
        (66, 35),
        (89, 38),
        (75, 54),
        (46, 50),
        (29, 59),
    ]:
        im.alpha_composite(leaf, (x, y))
    for x, y in [
        (17, 67),
        (27, 73),
        (44, 57),
        (55, 82),
        (69, 59),
        (81, 75),
        (101, 65),
        (61, 41),
    ]:
        d.line((x, y - 4, x - 1, y), fill="#665d53", width=2)
        d.ellipse((x - 3, y, x + 3, y + 7), fill="#b85166", outline="#794756")
        d.point((x - 1, y + 1), fill="#e6988e")
    im.save(art / "dyna_tree.png", optimize=True)


def build(em, scene, room_directory):
    tree(room_directory)
    reg = ROOT / "content/regions/crown"
    fs = reg / "maps"

    def save(path, obj):
        path.write_text(
            json.dumps(obj, ensure_ascii=False, separators=(",", ":")) + "\n"
        )

    for mid in ("crown_tree", "crown_lake", "crown_freezington"):
        path = fs / (mid + ".json")
        m = json.loads(path.read_bytes())
        w, h = m["size"]
        old = np.array(m["tiles"])
        reserved = {tuple(m["spawn"])} | {
            tuple(v["at"]) for key in ("objects", "npcs", "warps") for v in m[key]
        }
        old = np.zeros((h, w), dtype="uint8")
        old[[0, -1], :] = 1
        old[:, [0, -1]] = 1
        for wv in m["warps"]:
            x, y = wv["at"]
            old[y, x] = 0
        if mid == "crown_tree":
            a = relief(
                "FFGLLGFF/FGLLLGGF/GLLGGLLF/GLLLPLLL/FGGLLLFF/FFGGLFFF".split("/"),
                w,
                h,
                510,
            )
            a[old == 1] = "F"
            props = []
            props.append(
                ["res://assets/galar/districts/dyna_tree.png", 20, 10, [62, 125]]
            )
            for x, y in [
                (6, 8),
                (8, 7),
                (5, 10),
                (32, 12),
                (33, 14),
                (30, 8),
                (12, 23),
                (14, 24),
                (27, 26),
                (31, 25),
            ]:
                if (x, y) not in reserved:
                    prop(props, "tree", x, y)
                    old[y, x] = 1
            # Return the interior of the old double gate to the grassland.
            for v in m["hoenn_art"]["p"]:
                if v[0] in ["tree", "rock"] and v not in props:
                    props.append(v)
                    old[v[2], v[1]] = 1
            scene(mid, m, surface(em, a, 511), old, props)
        elif mid == "crown_lake":
            a = relief(
                "FFLLGFFR/FFGLLLGG/LGGLGLLF/LLLLLLLL/LSWWWWWS/SSWWWWWS/FFSSWWSS".split(
                    "/"
                ),
                w,
                h,
                92,
            )
            # A single southern lake leaves the old west/east crossings along its
            # north shore. Only the recorded start and arrivals need firm ground.
            a[9:12, :] = "L"
            for x, y in reserved:
                if a[y, x] == "W":
                    a[y, x] = "S"
            for y in range(1, h - 1):
                for x in range(1, w - 1):
                    old[y, x] = 2 if a[y, x] == "W" else 11 if a[y, x] == "G" else 0
            props = []
            for x, y in [
                (2, 3),
                (4, 4),
                (6, 3),
                (3, 6),
                (22, 3),
                (24, 4),
                (26, 3),
                (28, 5),
                (6, 17),
                (4, 19),
                (28, 19),
                (27, 18),
            ]:
                if a[y, x] not in "WS" and (x, y) not in reserved:
                    prop(props, "tree", x, y)
                    old[y, x] = 1
            for x, y in [(5, 12), (25, 12), (7, 18), (29, 18)]:
                if a[y, x] != "W" and (x, y) not in reserved:
                    prop(props, "rock", x, y)
                    old[y, x] = 1
            scene(mid, m, surface(em, a, 93), old, props)
        else:
            a = relief(
                "RRNNNNRR/FNNNPNNF/NNNNPNNN/PPPPPPPP/NFNNPNNF/FFNNPNFF".split("/"),
                w,
                h,
                41,
            )
            a[old == 2] = "W"
            a[13, :] = "P"
            a[:, 16:18] = "P"
            # The two front doors land below the facade; the square holds the Calyrex statue.
            m["warps"] = [d for d in m["warps"] if not d.get("tundra_house")]
            props = []
            for k, x, y in [
                ("cottage", 11, 7),
                ("lakeside", 24, 10),
                ("standing", 17, 8),
                ("fir", 6, 17),
                ("fir", 31, 17),
                ("fir", 27, 4),
            ]:
                if k == "standing":
                    prop(props, k, x, y)
                    continue
                prop(props, k, x, y)
                if k == "fir":
                    old[y, x] = 1
                    continue
                suffix = "peony" if k == "cottage" else "mayor"
                room = "crown_freezington_" + suffix
                data, roomim, grid, fixtures = generated_room(
                    em, mid, k, m, [x, y], "crown"
                )
                data["name"] = "冻凝村・" + (
                    "探险基地" if k == "cottage" else "村长的家"
                )
                scene(room, data, roomim, grid, fixtures)
                m["warps"].append(
                    {
                        "at": [x, y],
                        "trigger": "door",
                        "tundra_house": True,
                        "to": {"region": "crown", "map": room, "at": data["spawn"]},
                    }
                )
                old[y, x - 1 : x + 2] = 1
                old[y + 1, x] = 0
                a[y + 1 : 14, x] = "P"
            scene(mid, m, surface(em, a, 42), old, props)
    registry = json.loads((reg / "region.json").read_bytes())
    for rid in ("crown_freezington_peony", "crown_freezington_mayor"):
        if rid not in registry["maps"]:
            registry["maps"].append(rid)
    save(reg / "region.json", registry)
