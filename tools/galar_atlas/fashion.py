"""Galar's five boutiques and four hair salons, with walkable doors and furnished rooms."""

from PIL import Image, ImageDraw
from galar_atlas.art import ROOT
from galar_atlas.centers import avoid_events
from galar_atlas.venues import (
    actor,
    fixprops,
    gate,
    read,
    room,
    rug,
    save,
    threshold,
    write,
)

# Target the documented part of the settlement. Coordinates use this game's compressed town plan.
SHOPS = {
    "wedgehurst": [("boutique", (7, 11))],
    "motostoke": [("boutique", (30, 24)), ("salon", (25, 24))],
    "hammerlocke": [("boutique", (18, 19)), ("salon", (11, 19))],
    "circhester": [("boutique", (30, 10)), ("salon", (30, 22))],
    "wyndon": [("boutique", (7, 21)), ("salon", (7, 16))],
}
PALETTES = {
    "wedgehurst": ("#527c72", "#92ae84"),
    "motostoke": ("#994e47", "#cb7961"),
    "hammerlocke": ("#566c91", "#8394b1"),
    "circhester": ("#716b8c", "#a39eb5"),
    "wyndon": ("#5d697b", "#a08c93"),
}


def facade(city, kind):
    im = Image.new("RGBA", (48, 53))
    d = ImageDraw.Draw(im)
    dark, light = PALETTES[city]
    # Sloping tile roof, eyebrow cornice, sign, recessed central door and shop windows.
    d.polygon(
        [(1, 14), (7, 2), (38, 2), (46, 14), (46, 19), (1, 19)],
        fill=dark,
        outline="#444955",
    )
    for y in (5, 9, 13):
        d.line((8 - y // 4, y, 38 + y // 4, y), fill=light, width=1)
        for x in range(9 + y % 5, 39, 7):
            d.line((x, y + 1, x - 1, y + 3), fill=dark)
    d.rectangle((3, 18, 44, 50), fill="#ddd1b0", outline="#534d53")
    d.rectangle((3, 19, 44, 22), fill="#b7a48d")
    d.rectangle((4, 48, 43, 51), fill="#827b79")
    d.rectangle((4, 26, 44, 32), fill=light, outline="#5c5961")
    for x in range(5, 44, 6):
        d.rectangle((x, 27, x + 2, 31), fill="#e0c99b")
    for x in [6, 31]:
        d.rectangle((x, 33, x + 10, 45), fill="#756d75")
        d.rectangle((x + 1, 34, x + 9, 42), fill="#88adb2")
        d.line((x + 2, 35, x + 7, 35), fill="#d8e2cc")
        d.line((x + 1, 42, x + 9, 42), fill="#ab9790")
        d.line((x + 5, 34, x + 5, 43), fill="#756d75")
    d.rectangle((18, 31, 29, 50), fill="#574c53")
    d.rectangle((20, 33, 27, 48), fill="#897966")
    d.rectangle((21, 34, 26, 40), fill="#a7c0b8")
    d.point((26, 44), fill="#ffe5a2")
    d.rectangle((17, 50, 30, 52), fill="#bcb5a6")
    d.rectangle((17, 16, 30, 26), fill="#f0dfbe", outline="#5a5859")
    if kind == "salon":
        d.ellipse((19, 18, 22, 21), outline=dark)
        d.ellipse((19, 22, 22, 25), outline=dark)
        d.line((21, 20, 28, 25), fill=dark)
        d.line((21, 23, 28, 18), fill=dark)
        for y in range(34, 46, 4):
            d.line((42, y, 44, y - 2), fill="#ae6764", width=2)
    else:
        d.polygon(
            [
                (19, 21),
                (23, 19),
                (24, 17),
                (25, 18),
                (24, 20),
                (28, 22),
                (28, 23),
                (19, 23),
            ],
            outline=dark,
        )
    key = f"galar_{city}_{kind}_front"
    path = ROOT / "assets/galar/districts" / (key + ".png")
    im.save(path, optimize=True)
    return ["res://" + str(path.relative_to(ROOT)), [24, 53]]


def door_site(town, m, target):
    forbid = {(int(x), int(y)) for x, y in avoid_events().get(town, set())}
    forbid.add(tuple(m["spawn"]))
    for kind in ("objects", "npcs", "warps"):
        for obj in m.get(kind, []):
            x, y = map(int, obj["at"])
            forbid.add((x, y))
            if obj.get("trigger") == "door":
                forbid.add((x, y + 1))
    for path, x, y, *rest in m["hoenn_art"]["p"]:
        p = ROOT / (
            path[6:]
            if path.startswith("res://")
            else "assets/emerald/field/" + path + ".png"
        )
        if not p.is_file():
            continue
        with Image.open(p) as im:
            w, h = im.size
        ax, ay = rest[0] if rest else (w // 2, h)
        for yy in range(((y + 1) * 16 - ay) // 16, y + 1):
            for xx in range(
                (x * 16 + 8 - ax) // 16, (x * 16 + 8 - ax + w - 1) // 16 + 1
            ):
                forbid.add((xx, yy))
    w, h = m["size"]
    options = []
    for y in range(5, h - 3):
        for x in range(3, w - 3):
            footprint = [
                (xx, yy) for yy in range(y - 3, y + 1) for xx in range(x - 1, x + 2)
            ]
            if any(
                cell in forbid or m["tiles"][cell[1]][cell[0]] in [2, 6, 7]
                for cell in footprint
            ):
                continue
            if (x, y + 1) in forbid or m["tiles"][y + 1][x] not in [0, 11]:
                continue
            if any(m["tiles"][yy][xx] == 1 for xx, yy in footprint):
                continue
            options.append((abs(target[0] - x) + abs(target[1] - y), y, x))
    if not options:
        raise ValueError(town + " has no clear storefront")
    _, y, x = min(options)
    return x, y


def fixture(d, grid, kind, x, y, base):
    l, t = x * 16, y * 16
    if kind == "rack":
        d.rectangle((l + 1, t + 2, l + 32, t + 4), fill="#67656c")
        d.line((l + 3, t + 4, l + 3, t + 20), fill="#857b76", width=2)
        d.line((l + 30, t + 4, l + 30, t + 20), fill="#857b76", width=2)
        for i, c in enumerate([base, "#d8b88e", "#82849e", "#a36c77"]):
            x0 = l + 4 + i * 6
            d.line((x0 + 3, t + 4, x0 + 3, t + 7), fill="#5f5555")
            d.polygon(
                [
                    (x0, t + 8),
                    (x0 + 2, t + 7),
                    (x0 + 4, t + 7),
                    (x0 + 7, t + 10),
                    (x0 + 5, t + 12),
                    (x0 + 5, t + 17),
                    (x0 + 1, t + 17),
                    (x0 + 1, t + 12),
                ],
                fill=c,
                outline="#655e69",
            )
        for xx in [x, x + 1]:
            grid[y, xx] = 1
    elif kind == "mirror":
        d.rectangle((l, t - 18, l + 22, t + 2), fill="#9b885f", outline="#696357")
        d.rectangle((l + 2, t - 16, l + 20, t), fill="#99c2c9", outline="#dbdcd1")
        d.line((l + 6, t - 4, l + 14, t - 12), fill="#d5e4db", width=2)
        d.rectangle((l - 2, t + 2, l + 24, t + 6), fill="#ae8c71", outline="#776855")
        d.rounded_rectangle(
            (l + 3, t + 11, l + 19, t + 21), radius=2, fill=base, outline="#645a5d"
        )
        d.line((l + 10, t + 22, l + 10, t + 26), fill="#6a6669", width=3)
        d.line((l + 5, t + 26, l + 16, t + 26), fill="#777778", width=2)
        grid[y, x] = grid[y + 1, x] = 1
    else:
        d.rectangle((l - 3, t - 9, l + 27, t + 22), fill="#544b59", outline="#776b71")
        d.line((l - 5, t - 9, l + 29, t - 9), fill="#d8bd87", width=3)
        for x0 in range(l - 2, l + 17, 4):
            d.rectangle((x0, t - 6, x0 + 3, t + 18), fill=base, outline="#835f70")
        d.line((l - 3, t + 21, l + 26, t + 21), fill="#c9b5a2", width=2)
        grid[y, x] = grid[y, x + 1] = 1


def build():
    ids = []
    for city, stores in SHOPS.items():
        town = "galar_" + city
        m = read(town)
        for kind, target in stores:
            mid = town + "_" + kind + "_room"
            is_salon = kind == "salon"
            prefix = "美发沙龙" if is_salon else "时装店"
            existing = next((w for w in m["warps"] if w["to"]["map"] == mid), None)
            uri, anchor = facade(city, kind)
            if existing:
                x, y = existing["at"]
            else:
                x, y = door_site(town, m, target)
                m["warps"].append(gate(x, y, mid, (9, 10), "door"))
            if not any(p[0] == uri and p[1:3] == [x, y] for p in m["hoenn_art"]["p"]):
                m["hoenn_art"]["p"].append([uri, x, y, anchor])
            for yy in (y - 1, y):
                m["tiles"][yy][x - 1 : x + 2] = [1, 1, 1]
            width = 19 if is_salon else 21
            im, grid, d = room(
                width,
                12,
                "wood" if is_salon else "clinic",
                "#ccc1ae" if is_salon else "#c4b9af",
            )
            color = PALETTES[city][1]
            rug(d, 7, 7, 5, 3, "#928b8a" if is_salon else "#a4847b", "#d6c39c")
            props = []
            fixprops(
                grid,
                props,
                [
                    ("plant_indoor", 1, 5),
                    ("officecounter_compact", width - 4, 4),
                    ("plant_indoor", width - 2, 8),
                ],
            )
            bits = [
                actor(
                    (width - 4, 5),
                    "造型师" if is_salon else "店员",
                    "venue_" + kind + "_" + city,
                    "woman" if is_salon else "clerk",
                )
            ]
            if is_salon:
                for px in (3, 7, 11):
                    fixture(d, grid, "mirror", px, 4, color)
                bits.append(actor((2, 8), "等候的客人", "venue_style_guest", "lady"))
            else:
                for px, py in [(2, 5), (6, 5), (13, 7), (2, 8)]:
                    fixture(d, grid, "rack", px, py, color)
                fixture(d, grid, "curtain", 11, 3, color)
                # A sign on the open jamb is reachable from the room's aisle.
                bits.append(
                    {
                        "at": [12, 4],
                        "name": "试衣间",
                        "role": "venue_fitting",
                        "field_art": "galar_fitting_mark",
                        "lines": ["掀开帘子试衣。"],
                    }
                )
            grid[11, 9] = 0
            threshold(im, 9, 11, False)
            ids.append(
                save(
                    mid,
                    m["name"] + "・" + prefix,
                    im,
                    grid,
                    (9, 10),
                    [gate(9, 11, town, (x, y + 1), "down")],
                    bits,
                    props,
                )
            )
        write(town, m)
    mark = Image.new("RGBA", (9, 14))
    d = ImageDraw.Draw(mark)
    d.rectangle((1, 2, 8, 11), fill="#e1d8be", outline="#817677")
    d.line((1, 12, 8, 12), fill="#655e58")
    d.line([(3, 7), (5, 5), (7, 7), (3, 7)], fill="#736379")
    d.point((5, 4), fill="#736379")
    mark.save(ROOT / "assets/npc/galar_fitting_mark.png", optimize=True)
    return ids
