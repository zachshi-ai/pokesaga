"""Paint the expedition paths from their collision silhouettes, using Emerald's 16 px art.

These are the optional atlas trails (the Platinum story uses its own original floors).
Run with the pret/pokeemerald directory as argument. No retail map or ROM is copied into the tree.
"""

from pathlib import Path
import json
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageOps
from scipy import ndimage as ndi

from alola_melemele import CATALOG, cell, pack
from bake_emerald_field import Emerald

ROOT = Path(__file__).resolve().parents[1]
MAPS = ROOT / "content/regions"
ART = ROOT / "assets/expedition_fields"
P = 16

# Tile coordinates are relative to the existing world-atlas landings.
# Each island has a broad landing and narrower traverses between the ledges.
TRAILS = {
    "distortion_threshold": [
        [
            (19, 30),
            (19, 24),
            (14, 21),
            (15, 16),
            (20, 15),
            (26, 13),
            (31, 16),
            (38, 15),
        ],
        [(25, 14), (27, 8), (32, 6), (38, 7)],
    ],
    "distortion_pillars": [
        [(0, 13), (6, 13), (11, 10), (13, 14), (19, 13), (23, 16), (22, 21), (19, 26)]
    ],
    "distortion_cascade": [
        [
            (0, 11),
            (5, 11),
            (8, 14),
            (13, 14),
            (17, 10),
            (22, 10),
            (22, 6),
            (19, 5),
            (19, 0),
        ]
    ],
    "distortion_altar": [
        [(17, 0), (17, 5), (12, 9), (13, 14), (18, 16), (24, 14), (28, 16), (34, 15)]
    ],
    "dream_sky": [
        [
            (0, 13),
            (6, 13),
            (10, 9),
            (15, 8),
            (18, 12),
            (17, 15),
            (13, 17),
            (8, 19),
            (0, 20),
        ],
        [(17, 15), (21, 17), (26, 15), (29, 11)],
    ],
}
PADS = {
    "distortion_threshold": [
        (20, 15, 7, 5),
        (32, 7, 4, 3),
        (31, 16, 4, 3),
        (15, 22, 4, 3),
    ],
    "distortion_pillars": [(8, 12, 4, 3), (18, 13, 6, 4), (21, 21, 3, 3)],
    "distortion_cascade": [(7, 13, 4, 3), (21, 9, 6, 4), (18, 3, 3, 2)],
    "distortion_altar": [(15, 13, 7, 5), (28, 16, 4, 3)],
    "dream_sky": [(16, 13, 7, 5), (7, 19, 4, 2), (11, 8, 4, 3), (28, 12, 3, 3)],
}
ROCKS = {
    "distortion_threshold": [(12, 21), (20, 11), (28, 13), (34, 5)],
    "distortion_pillars": [(7, 11), (17, 10), (20, 16), (22, 19)],
    "distortion_cascade": [(6, 11), (24, 9), (17, 3)],
    "distortion_altar": [(12, 12), (17, 10), (20, 14), (29, 14)],
}
DREAM_PATHS = {
    "dream_village": [
        [
            (0, 13),
            (5, 13),
            (9, 11),
            (11, 11),
            (15, 14),
            (19, 14),
            (20, 18),
            (17, 23),
            (17, 26),
        ],
        [(19, 16), (23, 17), (26, 19), (26, 26)],
        [(9, 11), (9, 9)],
    ],
    "dream_oak": [
        [(34, 13), (27, 13), (23, 15), (19, 14), (17, 16), (13, 17)],
        [(23, 15), (27, 18), (30, 20), (34, 20)],
    ],
    "dream_sea": [
        [(17, 0), (17, 5), (13, 9), (14, 12), (19, 14), (24, 13), (28, 15), (34, 15)]
    ],
}


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n")


def shape(size, paths=(), pads=(), width=3):
    region = Image.new("1", size)
    pen = ImageDraw.Draw(region)
    for points in paths:
        pen.line(points, fill=1, width=width, joint="curve")
    for x, y, rx, ry in pads:
        pen.ellipse((x - rx, y - ry, x + rx, y + ry), fill=1)
    return np.array(region, bool)


def subtile(mask):
    return np.repeat(np.repeat(mask, P, axis=0), P, axis=1)


def mask_image(mask):
    return Image.fromarray(mask.astype("uint8") * 255)


def texture(tile, w, h):
    tile = tile.convert("RGB")
    return Image.fromarray(
        np.tile(
            np.asarray(tile), (h * P // tile.height + 1, w * P // tile.width + 1, 1)
        )[: h * P, : w * P]
    )


def tinted(tile, colors):
    return ImageOps.colorize(
        ImageOps.grayscale(tile), *colors, blackpoint=36, whitepoint=230
    )


def offset(mask, dx, dy):
    out = np.zeros_like(mask)
    h, w = mask.shape
    out[max(0, dy) : min(h, h + dy), max(0, dx) : min(w, w + dx)] = mask[
        max(0, -dy) : min(h, h - dy), max(0, -dx) : min(w, w - dx)
    ]
    return out


def sky_background(size, rng, daylight):
    w, h = size
    palette = (
        ["#79a8cf", "#8bbad7", "#9dc9df", "#bcdde3"]
        if daylight
        else ["#22263e", "#282c47", "#30324e", "#383852"]
    )
    # Dither between close sky hues. A flat stripe across an entrance reads as a wall.
    stops = np.asarray([tuple(bytes.fromhex(c[1:])) for c in palette])
    rows = np.arange(h) * (len(stops) - 1) / max(h - 1, 1)
    lo = rows.astype(int)
    pos = (rows - lo)[:, None]
    shades = stops[lo] * (1 - pos) + stops[np.minimum(lo + 1, len(stops) - 1)] * pos
    pattern = np.asarray([[0, 2], [3, 1]])
    dither = np.tile(pattern, ((h + 1) // 2, (w + 1) // 2))[:h, :w, None]
    rgb = np.clip(np.floor((shades[:, None, :] + dither) / 4) * 4, 0, 255).astype(
        "uint8"
    )
    pic = Image.fromarray(rgb)
    d = ImageDraw.Draw(pic)
    if daylight:
        # Far banks sit below the flight path. A second, light rim makes their
        # distance distinct from the opaque cloud that carries the player.
        for yy in (h // 5, h // 2 + 24, h - 46):
            x = -48 + rng.randrange(32)
            while x < w:
                length = rng.randint(50, 100)
                for step in range(0, length, 10):
                    lift = rng.randrange(6, 16)
                    d.ellipse(
                        (x + step, yy - lift, x + step + 30, yy + 12), fill="#acd0dd"
                    )
                    d.arc(
                        (x + step, yy - lift, x + step + 30, yy + 12),
                        180,
                        280,
                        fill="#d0e3e7",
                        width=2,
                    )
                x += length + rng.randint(32, 85)
    for _ in range(w * h // 2600):
        x, y = rng.randrange(-20, w), rng.randrange(h)
        if daylight:
            wind = rng.randint(9, 32)
            d.line((x, y, x + wind, y), fill="#bedee6", width=2)
            d.line((x + 4, y - 2, x + wind // 2, y - 2), fill="#cce5e8")
        else:
            c = rng.choice(["#5a5473", "#6b607d", "#4d4865"])
            d.line((x, y, x + rng.randrange(1, 4), y), fill=c)
    return pic


def deck(doc, mid):
    w, h = doc["size"]
    sky = mid == "dream_sky"
    rng = random.Random(mid)
    surface = shape((w, h), TRAILS[mid], PADS[mid], 3)
    # Retain the exact object interactions, arrivals beside edge exits and region start.
    points = [doc["spawn"]] + [
        a["at"] for a in doc["npcs"] + doc["objects"] + doc["warps"]
    ]
    for x, y in points:
        if surface[max(0, y - 1) : y + 2, max(0, x - 1) : x + 2].all():
            continue
        _, indices = ndi.distance_transform_edt(~surface, return_indices=True)
        a, b = indices[:, y, x]
        surface |= shape((w, h), [[(x, y), (int(b), int(a))]], [(x, y, 1, 1)], 3)
    pic = sky_background((w * P, h * P), rng, sky)
    top = subtile(surface)
    colors = ("#9bbcce", "#eef7ef") if sky else ("#4e4c67", "#aea0b7")
    top_tile = cell("grass") if sky else patch("meteor_floor")
    top_pic = texture(tinted(top_tile, colors), w, h)
    if sky:
        # A scalloped rim around the cloud bank; its center remains on the walkable cell.
        rounded = ndi.gaussian_filter(top.astype("float32"), 4) > 0.49
        top = rounded
    else:
        # Cut the stepped corners without changing the playable tile centers.
        top = ndi.gaussian_filter(top.astype("float32"), 2) > 0.5
    for dy, color in (
        [(14, "#25273b"), (11, "#49435e"), (8, "#655c77"), (4, "#80728b")]
        if not sky
        else [(9, "#6997b6"), (6, "#8fb4c7"), (3, "#bbd5dd")]
    ):
        pic.paste(color, (0, 0, pic.width, pic.height), mask_image(offset(top, 0, dy)))
    pic.paste(top_pic, (0, 0), mask_image(top))
    rim = top & ~offset(top, 0, 2)
    pic.paste(
        "#d9e9e8" if sky else "#b3a2b7", (0, 0, pic.width, pic.height), mask_image(rim)
    )
    if mid == "distortion_cascade":
        # The cascade hangs from the east lip, over void. The walking bridge is on the west.
        x, y = 22 * P, 14 * P - 2
        d = ImageDraw.Draw(pic)
        for i in range(18):
            col = ("#707ea9", "#8da5bd", "#b0d0ce", "#647799")[i % 4]
            d.line((x + i, y, x + i, y + 34 - (i % 5) * 3), fill=col)
    # Rim highlights pick out the active landing from the floating ledges behind it.
    if not sky:
        d = ImageDraw.Draw(pic)
        for i in range(8):
            x = rng.randrange(pic.width)
            y = rng.randrange(pic.height - 30)
            if top[y : y + 28, max(0, x - 21) : min(pic.width, x + 22)].any():
                continue
            d.polygon(
                [
                    (x - 13, y + 3),
                    (x - 4, y),
                    (x + 12, y + 1),
                    (x + 17, y + 4),
                    (x + 7, y + 8),
                    (x - 12, y + 7),
                ],
                fill="#55516a",
            )
            d.polygon(
                [(x - 12, y + 7), (x + 7, y + 8), (x + 1, y + 17), (x - 3, y + 20)],
                fill="#454358",
            )
    props = []
    if sky:
        for x, y in [(9, 7), (23, 16), (27, 10)]:
            props.append(["flowers", x, y, list(CATALOG["flowers"])])
    else:
        for i, (x, y) in enumerate(ROCKS[mid]):
            key = "amethyst" if i % 3 == 0 else "boulder"
            asset = (
                key
                if key == "boulder"
                else "res://assets/island_landmarks/amethyst.png"
            )
            anchor = CATALOG[key] if key == "boulder" else [16, 32]
            props.append([asset, x, y, list(anchor)])
            surface[y, x] = False
    return np.where(surface, 0, 1), pic, props


def draw_wood(w, h):
    plank = patch("manor_planks")
    return texture(tinted(plank, ("#66514d", "#bb9673")), w, h)


def manor(doc):
    w, h = doc["size"]
    floor = Image.new("1", (w, h))
    p = ImageDraw.Draw(floor)
    # Entrance hall, parallel galleries and a north landing. The walls have physical thickness.
    p.rectangle((10, 3, 21, 27), fill=1)
    p.rectangle((4, 7, 26, 12), fill=1)
    p.rectangle((6, 17, 25, 21), fill=1)
    p.rectangle((14, 0, 16, 3), fill=1)
    p.rectangle((14, 27, 16, 30), fill=1)
    walk = np.asarray(floor, bool).copy()
    wood = draw_wood(w, h)
    mf = subtile(walk)
    pic = Image.new("RGB", wood.size, "#24252e")
    pic.paste(wood, (0, 0), mask_image(mf))
    wall = patch("manor_wall")
    d = ImageDraw.Draw(pic)
    for y, x in zip(*np.where(walk & ~offset(walk, 0, 1))):
        if y >= 1:
            # High windows and a skirting board on the northern face.
            u, v = int(x) * P, int(y) * P
            pic.paste(wall.crop((0, 0, 16, 16)), (u, v - P))
            d.line((u, v - 1, u + 15, v - 1), fill="#63504c")
    d.rectangle((14 * P + 2, 2 * P, 17 * P - 3, 28 * P), fill="#563b41")
    d.rectangle((14 * P + 5, 2 * P, 17 * P - 6, 28 * P), fill="#965854")
    for x in (14 * P + 6, 17 * P - 8):
        d.line((x, 2 * P + 2, x, 28 * P - 2), fill="#cdab79")
    props = []
    for key, x, y in [
        ("bookshelf", 6, 8),
        ("bookshelf", 8, 8),
        ("clock", 24, 8),
        ("plant_indoor", 12, 5),
        ("plant_indoor", 19, 5),
        ("bookshelf", 8, 18),
        ("desk", 22, 18),
        ("plant_indoor", 11, 25),
        ("plant_indoor", 20, 25),
    ]:
        props.append([key, x, y, list(CATALOG[key])])
        walk[y, x] = False
    return np.where(walk, 0, 1), pic, props


def garden(doc, mid):
    tiles = np.array(doc["tiles"])
    w, h = doc["size"]
    rng = random.Random(mid)
    if mid == "dream_village":
        tiles[15:17, 23:26] = 0
    if mid == "dream_oak":
        for x, y in [(17, 13), (19, 12), (21, 13)]:
            tiles[y, x] = 1
    grass = texture(cell("grass"), w, h)
    if mid == "dream_sea":
        base = tinted(cell("sand"), ("#b39775", "#edd9ae"))
        grass = texture(base, w, h)
    pic = grass.copy()
    walk = ~np.isin(tiles, [1, 2, 6, 7])
    water = tiles == 2
    route = shape((w, h), DREAM_PATHS[mid], width=3) & walk
    tiles[(tiles == 11) & route] = 0
    lanes = ndi.gaussian_filter(subtile(route).astype("float32"), 4) > 0.5
    # Pebbles cluster along the walking lane, with green at the curved verge.
    sand = texture(tinted(cell("ground"), ("#b99771", "#dfc897")), w, h)
    pic.paste(sand, (0, 0), mask_image(lanes))
    blocked = ~walk & ~water
    dark = tinted(cell("grass"), ("#598a65", "#87b587"))
    if mid == "dream_sea":
        dark = tinted(cell("sand"), ("#a08a6f", "#ccb793"))
    pic.paste(texture(dark, w, h), (0, 0), mask_image(subtile(blocked)))
    if water.any():
        wet = ndi.gaussian_filter(subtile(water).astype("float32"), 2.5) > 0.5
        sea = texture(tinted(cell("water"), ("#3683a4", "#8fd0d0")), w, h)
        pic.paste(sea, (0, 0), mask_image(wet))
        edge = wet & ~ndi.binary_erosion(wet, iterations=2, border_value=1)
        pic.paste("#d5e5cd", (0, 0, pic.width, pic.height), mask_image(edge))
    for y, x in zip(*np.where(tiles == 11)):
        pic.paste(cell("darkgrass"), (x * P, y * P))
    props = doc["hoenn_art"]["p"]
    d = ImageDraw.Draw(pic)
    if mid == "dream_village":
        # Two furrowed berry beds beside the cottage. The approach finishes at its door.
        for x0, y0 in [(14, 8), (20, 6)]:
            for j in range(2):
                x, y = x0 * P, (y0 + j) * P
                d.rounded_rectangle(
                    (x, y + 2, x + 46, y + 12), 3, fill="#a88962", outline="#c5a976"
                )
                for k in range(3):
                    u = x + k * 15 + 6
                    d.line((u, y + 7, u - 2, y + 4), fill="#51805a", width=2)
                    d.line((u, y + 7, u + 3, y + 3), fill="#72a774", width=2)
        props = [a for a in props if not (a[0] == "home_green" and a[1:3] == [24, 16])]
    elif mid == "dream_oak":
        # A shaded clearing surrounds the destination tree, not a second paved square.
        for xx, yy in [(17, 13), (19, 12), (21, 13)]:
            if not any(p[0] == "tree" and p[1:3] == [xx, yy] for p in props):
                props.append(["tree", xx, yy, list(CATALOG["tree"])])
            tiles[yy, xx] = 1
    for _ in range(w * h // 3):
        x, y = rng.randrange(w), rng.randrange(h)
        if not walk[y, x] or route[y, x] or tiles[y, x] == 11:
            continue
        u, v = x * P + rng.randint(3, 12), y * P + rng.randint(4, 13)
        color = "#bfa981" if mid == "dream_sea" else "#83c5a0"
        d.line((u, v, u + 2, v - 1), fill=color)
    return tiles, pic, props


def sketch(mid, doc):
    if mid in TRAILS:
        tiles, pic, props = deck(doc, mid)
    elif mid == "dream_manor":
        tiles, pic, props = manor(doc)
    else:
        tiles, pic, props = garden(doc, mid)
    doc["tiles"] = tiles.astype("uint8").tolist()
    doc["hoenn_art"]["p"] = props
    pic.save(ART / (mid + ".png"), optimize=True)


def patch(name):
    return Image.open(ROOT / "assets/island_landmarks" / (name + ".png")).convert("RGB")


def export_donors(emerald):
    for name, location, bounds in [
        ("meteor_floor", "MeteorFalls_1F_1R", (1, 3, 3, 2)),
        ("manor_planks", "LittlerootTown_BrendansHouse_1F", (6, 4, 2, 1)),
        ("manor_wall", "LittlerootTown_BrendansHouse_1F", (1, 0, 2, 1)),
    ]:
        emerald.patch(location, *bounds).convert("RGB").save(
            ROOT / "assets/island_landmarks" / (name + ".png"), optimize=True
        )
    room = emerald.patch("House3", 0, 0, 10, 8).convert("RGB")
    # Continue the tatami across the walkable threshold. The outside edging
    # in the original projected room reads as another floor in this camera.
    foot = room.crop((0, 5 * P, 10 * P, 6 * P))
    mat = room.crop((3 * P, 7 * P, 5 * P, 8 * P))
    room.paste(foot, (0, 6 * P))
    room.paste(foot, (0, 7 * P))
    room.paste(mat, (3 * P, 7 * P))
    room.save(ART / "dream_cottage.png", optimize=True)


def cottage():
    source = json.loads(
        (ROOT / "content/hoenn_native/maps/em_dewford_town_house1.json").read_bytes()
    )
    w, h = source["size"]
    room = {
        "name": "梦境小屋·起居室",
        "size": [w, h],
        "spawn": [3, 6],
        "biome": "interior",
        "style": "room",
        "tiles": source["physics"]["collision"],
        "objects": [],
        "npcs": [],
        "warps": [
            {
                "at": [x, 7],
                "trigger": "down",
                "to": {
                    "region": "dream",
                    "map": "dream_village",
                    "at": [9, 10],
                    "facing": "down",
                },
            }
            for x in (3, 4)
        ],
        "hoenn_art": {
            "s": [w, h],
            "t": pack(np.zeros((h, w), dtype="<u2")),
            "p": [],
            "scene": ["res://assets/expedition_fields/dream_cottage.png", 0, 0],
        },
    }
    write(MAPS / "dream/maps/dream_cottage.json", room)
    reg = MAPS / "dream/region.json"
    data = json.loads(reg.read_bytes())
    if "dream_cottage" not in data["maps"]:
        data["maps"].append("dream_cottage")
    write(reg, data)


def redraw(mid, doc):
    sketch(mid, doc)
    if mid == "dream_village":
        # The house's anchor (9,9) is the door's bottom row in the 16 px tileset.
        point = [9, 9]
        doc["warps"] = [
            w for w in doc["warps"] if w.get("to", {}).get("map") != "dream_cottage"
        ]
        doc["warps"].append(
            {
                "at": point,
                "trigger": "door",
                "to": {
                    "region": "dream",
                    "map": "dream_cottage",
                    "at": [3, 6],
                    "facing": "up",
                },
            }
        )
        doc["tiles"][10][9] = 0
        cottage()


if __name__ == "__main__":
    export_donors(Emerald(Path(sys.argv[1])))
    for mid in list(TRAILS) + ["dream_manor"] + list(DREAM_PATHS):
        f = MAPS / mid.split("_")[0] / "maps" / (mid + ".json")
        doc = json.loads(f.read_bytes())
        redraw(mid, doc)
        write(f, doc)
