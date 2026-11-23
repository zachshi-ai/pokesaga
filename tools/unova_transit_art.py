"""Draw Castelia's curved quays, Skyarrow's turning viaduct and the Marine Tube on rail cells.

These three locations move the DS camera along a spline. A fixed projection displaces
the road from the walk mask. Build the GBA elevations around the original rail footprint.
"""

from functools import lru_cache

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

from unova_art import K, ROOT, encode
from unova_streets import grass_tile

PLACES = {"unova_skyarrow_bridge", "unova_marine_tube", "unova_castelia"}
OUT = ROOT / "assets/unova/transit"
ATLAS = ROOT / "assets/unova/tiles.png"
# Names and indices are stable across full builds, era-specific rebuilds and old saves.
OFFSET = 96
KEYS = (
    "road",
    "road_dash",
    "concrete",
    "seawall",
    "girder",
    "glass",
    "glass_glow",
    "deepsea",
    "shoal",
    "blueglass",
    "cobble",
    "quay",
    "portwater",
    "wharf",
)
INDEX = {k: OFFSET + i for i, k in enumerate(KEYS)}


def material(key):
    colors = {
        "road": ("#626f80", "#687889"),
        "road_dash": ("#626f80", "#687889"),
        "concrete": ("#bbc1bf", "#a9b3b5"),
        "seawall": ("#8d9b9c", "#758387"),
        "girder": ("#646f77", "#949c9d"),
        "glass": ("#93c2c9", "#81acb7"),
        "glass_glow": ("#9cc7ce", "#8ab9c5"),
        "blueglass": ("#5f97ab", "#558b9f"),
        "cobble": ("#9fabb2", "#829298"),
        "quay": ("#bcc1ac", "#9eaa9f"),
        "wharf": ("#bd986b", "#846e58"),
    }
    if key in ("deepsea", "shoal", "portwater"):
        water = Image.fromarray(grass_tile("water")).convert("RGBA")
        a = np.asarray(water).copy()
        light = a[:, :, 1].astype(float)
        # Start from Emerald's waves, then push them into the harbour or deep-sea palette.
        lo, hi = {
            "deepsea": ((23, 61, 91), (39, 92, 120)),
            "shoal": ((34, 77, 96), (69, 111, 123)),
            "portwater": ((49, 101, 140), (87, 151, 170)),
        }[key]
        a[:, :, :3] = np.array(lo) + (np.array(hi) - lo) * np.clip((light - 50) / 150, 0, 1)[:, :, None]
        return Image.fromarray(a)
    bg, shade = colors[key]
    im = Image.new("RGBA", (16, 16), bg)
    p = ImageDraw.Draw(im)
    if key in ("road", "road_dash"):
        for x, y in ((2, 3), (13, 7), (7, 12), (10, 1)):
            p.point((x, y), fill=shade)
        if key == "road_dash":
            p.rectangle((7, 2, 8, 9), fill="#d4d6bb")
            p.point((8, 10), fill=shade)
    elif key == "girder":
        for y in (0, 12):
            p.rectangle((0, y, 15, y + 2), fill=shade)
            p.line((0, y + 3, 15, y + 3), fill="#414f5e")
        p.line((0, 10, 10, 1), fill="#9fa8a8", width=2)
    elif key in ("glass", "glass_glow", "blueglass"):
        p.line((0, 15, 15, 15), fill=shade)
        p.line((15, 0, 15, 15), fill=shade)
        p.line((2, 3, 5, 0), fill="#b8d7d3" if key != "blueglass" else "#88b3c1")
        if key == "glass_glow":
            p.line((3, 6, 8, 1), fill="#c1ddd6", width=2)
    elif key in ("cobble", "quay", "concrete", "seawall", "wharf"):
        for j in (0, 8):
            p.line((0, j, 15, j), fill=shade)
            if key != "wharf":
                p.line((7 if j else 0, j, 7 if j else 0, j + 7), fill=shade)
        if key == "wharf":
            p.line((2, 2, 10, 2), fill="#ceae82")
            p.point((2, 6), fill=shade)
            p.point((14, 14), fill=shade)
    return im


def atlas():
    with Image.open(ATLAS) as source:
        old = source.convert("RGBA")
    height = max(old.height, ((OFFSET + len(KEYS) + 15) // 16) * 16)
    im = Image.new("RGBA", (old.width, height))
    im.paste(old)
    for key, i in INDEX.items():
        im.paste(material(key), (i % 16 * 16, i // 16 * 16))
    if im.size != old.size or old.tobytes() != im.tobytes():
        im.save(ATLAS, optimize=True)


def sprite(name, im):
    OUT.mkdir(parents=True, exist_ok=True)
    file = OUT / (name + ".png")
    if not file.is_file() or Image.open(file).convert("RGBA").tobytes() != im.tobytes():
        im.save(file, optimize=True)
    return "res://" + str(file.relative_to(ROOT))


@lru_cache(None)
def arch(marine=False):
    # Skyarrow's suspension towers have a double cross beam and open roadway beneath;
    # the Marine Tube's glass ribs curve over it and are anchored in the viewing walkway.
    w, h = (212, 75) if marine else (104, 88)
    im = Image.new("RGBA", (w, h))
    p = ImageDraw.Draw(im)
    if marine:
        for n, c in [(0, "#346982"), (2, "#5595a4"), (4, "#9dd3ce"), (6, "#679eae")]:
            p.arc((4 + n, 2 + n, w - 5 - n, 130 + n), 180, 360, fill=c, width=2)
        for x in (4, w - 11):
            p.rectangle((x, 60, x + 6, 74), fill="#5b8590")
            p.line((x + 1, 59, x + 1, 73), fill="#d0dfc3")
    else:
        for x in (4, w - 14):
            p.polygon(
                [(x, h - 1), (x + 1, 19), (x + 4, 8), (x + 7, 8), (x + 10, 19), (x + 10, h - 1)],
                fill="#687681",
            )
            p.rectangle((x + 2, 19, x + 5, h - 2), fill="#c9cebd")
            p.line((x + 6, 20, x + 6, h - 3), fill="#a4b1aa")
            p.rectangle((x + 1, h - 5, x + 11, h - 1), fill="#485867")
            for y in range(28, 78, 12):
                p.line((x + 2, y, x + 9, y), fill="#7f8d92")
        for y in (19, 31):
            p.rectangle((6, y, w - 7, y + 4), fill="#617480")
            p.line((7, y, w - 8, y), fill="#d3d5bf")
        for x in range(13, w - 19, 14):
            p.line((x, 23, x + 8, 30), fill="#afb8ae", width=2)
            p.line((x + 8, 30, x + 14, 23), fill="#7e9298", width=2)
    return sprite("tube_glass_rib" if marine else "skyarrow_gantry", im), [w // 2, h]


@lru_cache(None)
def edge(orientation, marine):
    im = Image.new("RGBA", (16, 18))
    p = ImageDraw.Draw(im)
    rim = "#75b2c0" if marine else "#d4d6c0"
    steel = "#466b81" if marine else "#657987"
    if orientation in ("w", "e"):
        for x in [4, 5, 7] if orientation == "w" else [8, 10, 11]:
            p.line((x, 0, x, 17), fill=rim if x in (5, 10) else steel)
        p.rectangle((5 if orientation == "w" else 9, 1, 7 if orientation == "w" else 11, 4), fill="#aabfc0")
    else:
        p.rectangle((0, 7, 15, 11), fill=steel)
        p.line((0, 7, 15, 7), fill=rim)
        p.rectangle((2, 6, 4, 15), fill=steel)
    return sprite(("glass_" if marine else "rail_") + orientation, im), [8, 16]


@lru_cache(None)
def tower(style):
    w, h = {"low": (60, 77), "mid": (65, 125), "tall": (80, 173), "corner": (71, 143)}[style]
    im = Image.new("RGBA", (w, h))
    p = ImageDraw.Draw(im)
    body = {"low": "#ae8b70", "mid": "#8499a6", "tall": "#7e8596", "corner": "#91a99b"}[style]
    shadow = {"low": "#856f63", "mid": "#5b7788", "tall": "#596074", "corner": "#627f80"}[style]
    p.polygon([(1, 13), (w - 12, 3), (w - 2, 10), (w - 2, h - 1), (2, h - 1)], fill=shadow)
    p.rectangle((3, 14, w - 13, h - 2), fill=body)
    for y in range(22, h - 19, 14):
        for x in range(8, w - 19, 12):
            p.rectangle((x, y, x + 6, y + 7), fill="#526777")
            p.rectangle((x + 1, y + 1, x + 4, y + 4), fill="#a7c6c6")
            p.line((x, y + 8, x + 7, y + 8), fill="#c4c6b6")
        p.line((4, y + 10, w - 14, y + 10), fill=shadow)
    p.polygon([(1, 13), (w - 13, 13), (w - 2, 6), (w // 2, 1)], fill="#bec7bd")
    p.rectangle((4, h - 19, w - 14, h - 3), fill="#6a7880")
    p.rectangle((w // 2 - 9, h - 19, w // 2 + 5, h - 1), fill="#394755")
    p.line((w // 2 - 1, h - 17, w // 2 - 1, h - 1), fill="#97b0b0")
    p.rectangle((3, h - 3, w - 13, h - 1), fill="#899591")
    return sprite("castelia_" + style, im), [w // 2 - 2, h]


@lru_cache(None)
def undersea(kind):
    im = Image.new("RGBA", (40, 24))
    p = ImageDraw.Draw(im)
    if kind == "school":
        for x, y in ((3, 11), (18, 3), (25, 15)):
            p.polygon(
                [
                    (x, y + 2),
                    (x + 3, y),
                    (x + 8, y + 1),
                    (x + 11, y + 3),
                    (x + 7, y + 5),
                    (x + 3, y + 5),
                    (x, y + 4),
                    (x - 2, y + 6),
                    (x - 2, y),
                ],
                fill="#53839a",
            )
            p.line((x + 3, y + 1, x + 7, y + 1), fill="#7fabb8")
            p.point((x + 9, y + 2), fill="#c0cbbe")
    else:
        for x, y, h in ((7, 22, 14), (12, 22, 20), (18, 23, 12), (30, 21, 16)):
            p.line((x, y, x - 1, y - h), fill="#487b84", width=2)
            p.line((x - 1, y - h + 7, x - 6, y - h + 3), fill="#629790", width=2)
            p.line((x, y - h + 10, x + 4, y - h + 4), fill="#65948e", width=2)
        p.ellipse((4, 20, 35, 23), fill="#517889")
    return sprite("tube_" + kind, im), [20, 23]


@lru_cache(None)
def cable(left, section):
    im = Image.new("RGBA", (12, 16))
    p = ImageDraw.Draw(im)
    # The sag of each suspension cable changes over the span between two towers.
    for y in range(16):
        i = (section * 16 + y) / 128
        out = round(7 * (2 * i - 1) ** 2)
        x = 2 + out if left else 9 - out
        p.line((x, y, x + 1, y), fill="#546777")
        p.point((x, y), fill="#b4bbad")
    if section in (2, 5):
        p.line((x, 0, x, 14), fill="#8b9c98")
    return sprite("skyarrow_cable_" + str(int(left)) + "_" + str(section), im), [6, 16]


def can_place(mask, x, y):
    return 0 <= y < mask.shape[0] and 0 <= x < mask.shape[1] and mask[y, x]


def paint(doc):
    mid = doc["id"]
    marine = mid == "unova_marine_tube"
    city = mid == "unova_castelia"
    wet = INDEX["deepsea" if marine else "portwater"]
    walk = np.array(doc["physics"]["collision"]) == 0
    ygrid, xgrid = np.indices(walk.shape)
    tiles = np.full(walk.shape, wet, dtype=np.uint16)
    props = []

    def place(asset, x, y):
        uri, anchor = asset
        props.append([uri, int(x), int(y), anchor])

    # The curved quay follows the five piers and street mouths in the source warp bank.
    if city:
        shore = ndimage.binary_dilation(walk, iterations=2)
        apron = ndimage.binary_dilation(walk, iterations=5)
        tiles[apron] = INDEX["seawall"]
        tiles[shore] = INDEX["quay"]
        tiles[walk] = INDEX["cobble"]
        # The inside of the arc is the city centre. The outer bank opens onto the sea.
        for x in range(4, walk.shape[1]):
            rows = np.where(walk[:, x])[0]
            if not len(rows):
                continue
            top = int(rows.min())
            if x >= 24:
                tiles[max(0, top - 11) : max(0, top - 2), x] = INDEX["concrete"]
        avoided = set()
        for w in doc["warps"]:
            x, y = w["at"]
            dest = w["to"]["map"]
            if dest == mid or any(abs(x - xx) + abs(y - yy) < 6 for xx, yy in avoided):
                continue
            if y > 64 and dest.endswith(("_37", "_38", "_39")) or dest == "unova_virbank":
                # The docks have bollards, quay steps and timber planks.
                for j in range(max(0, y - 1), min(y + 4, len(walk))):
                    for i in range(max(0, x - 1), min(x + 2, walk.shape[1])):
                        if walk[j, i]:
                            tiles[j, i] = INDEX["wharf"]
                place(("sign", [8, 15]), x, min(y + 1, len(walk) - 1))
                avoided.add((x, y))
                continue
            if y > 3 and not can_place(walk, x, y - 1):
                place(tower(("mid", "corner", "low", "tall")[(x + 2 * y) % 4]), x, y - 1)
                avoided.add((x, y))
        for x in range(23, 76, 5):
            rows = np.where(walk[:, x])[0]
            if not len(rows):
                continue
            y = int(rows.min()) - 4
            if y < 2 or any(abs(x - xx) < 4 and abs(y - yy) < 6 for xx, yy in avoided):
                continue
            if not walk[y, max(0, x - 1) : x + 2].any():
                place(tower(("tall", "corner", "mid")[(x // 5) % 3]), x, y)
        for y, x in np.argwhere(shore & ~walk):
            if (x * 3 + y) % 17 == 0 and not can_place(walk, x, int(y) + 2):
                props.append(["streetlamp", int(x), int(y)])
    else:
        if marine:
            tiles[((xgrid // 4 + 2 * ygrid // 7) % 9 == 0)] = INDEX["shoal"]
        else:
            # The southern ramp returns to Pinwheel Forest; the rest spans the bay.
            south = (ygrid > 269) & (xgrid < 111)
            tiles[south] = K["grass"]
            tiles[south & ((xgrid + 2 * ygrid) % 37 == 0)] = K["flowers"]
        boundary = ndimage.binary_dilation(walk)
        tiles[boundary] = INDEX["blueglass" if marine else "girder"]
        tiles[walk] = INDEX["glass" if marine else "concrete"]
        center = ndimage.binary_erosion(walk)
        tiles[center] = INDEX["glass_glow" if marine else "road"]
        if not marine:
            tiles[center & (xgrid == 114) & ((ygrid // 2) % 3 == 0)] = INDEX["road_dash"]
        for y in range(1, len(walk) - 1):
            xs = np.where(walk[y])[0]
            if not len(xs):
                continue
            for x in (xs.min() - 1, xs.max() + 1):
                if 0 <= x < walk.shape[1]:
                    place(edge("w" if x < xs.min() else "e", marine), x, y)
            if marine and y % 11 == 3:
                x = int(xs.min()) - 4 if y % 22 == 3 else int(xs.max()) + 4
                if 0 <= x < walk.shape[1]:
                    place(undersea("school" if y % 33 == 3 else "kelp"), x, y)
            if not marine and 22 < y < 263 and len(xs) < 10:
                for x, left in ((int(xs.min()) - 2, True), (int(xs.max()) + 2, False)):
                    place(cable(left, (y - 21) % 8), x, y)
            if marine and y % 19 == 6:
                place(arch(True), (xs.min() + xs.max()) // 2, y)
            if not marine and y in (20, 70, 135, 199, 261):
                place(arch(), (xs.min() + xs.max()) // 2, y)
        if not marine:
            for y in range(271, 303, 3):
                for x in range(72, 108, 3):
                    if not boundary[y - 1 : y + 2, x - 1 : x + 2].any() and (x + y) % 5 != 1:
                        props.append(["tree", x, y])
    doc["hoenn_art"].pop("scene", None)
    doc["hoenn_art"]["t"] = encode(tiles)
    doc["hoenn_art"]["p"] = sorted(props, key=lambda p: (p[2], p[1], p[0]))
