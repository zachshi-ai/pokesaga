"""Extract unchanged 16px GBA artwork with native palette banks and calibrated door anchors."""

from functools import lru_cache
import numpy as np
from PIL import Image, ImageDraw
from bake_emerald_field import Atlas
from firered_fields import FireRedFields


class FireRed:
    def __init__(self, src, project):
        self.src = FireRedFields(src, project, Atlas())

    @lru_cache(None)
    def tile(self, layout, n):
        fs = self.src
        l = fs.layouts[fs.maps[layout.lower().replace("_", "")]]
        i, _, _ = fs.metatile(l["primary_tileset"], l["secondary_tileset"], int(n))
        return fs.atlas.images[i]

    @lru_cache(None)
    def grid(self, m):
        fs = self.src
        l = fs.layouts[fs.maps[m.lower().replace("_", "")]]
        return (np.fromfile(fs.source / l["blockdata_filepath"], "<u2") & 1023).reshape(l["height"], l["width"])

    def patch(self, m, x, y, w, h):
        grid = self.grid(m)
        result = Image.new("RGBA", (16 * w, 16 * h))
        for iy in range(h):
            for ix in range(w):
                result.alpha_composite(self.tile(m, grid[y + iy, x + ix]), (ix * 16, iy * 16))
        return result


def polygon_crop(img, outline):
    mask = Image.new("L", img.size)
    p = [(round(x * img.width), round(y * img.height)) for x, y in outline]
    ImageDraw.Draw(mask).polygon(p, fill=255)
    ret = img.copy()
    ret.putalpha(mask)
    return ret


def trim_lawn(img, palette):
    # Discard only connected exterior lawn/sidewalk pixels. Building windows use some
    # of these same colors and must retain them when completely enclosed by their frame.
    px = np.array(img)
    c = px[:, :, :3].astype(np.uint32)
    keys = c[:, :, 0] * 65536 + c[:, :, 1] * 256 + c[:, :, 2]
    m = np.isin(keys, np.array(list(palette), dtype=np.uint32)) | (px[:, :, 3] == 0)
    h, w = m.shape
    # Edge-connected transparency via a padded binary image avoids a dependency on scipy.
    work = Image.new("L", (w + 2, h + 2), 255)
    work.paste(Image.fromarray(m.astype(np.uint8) * 255), (1, 1))
    ImageDraw.floodfill(work, (0, 0), 128)
    px[:, :, 3][np.array(work)[1:-1, 1:-1] == 128] = 0
    return Image.fromarray(px)


def colors(img):
    return {(r << 16) | (g << 8) | b for r, g, b, a in img.getdata() if a}


def generate(out, fr, hns):
    out.mkdir(parents=True, exist_ok=True)
    catalog = {}
    p = "PalletTown"
    lawn = set().union(
        *(
            colors(fr.tile(p, i))
            for i in [
                1,
                8,
                9,
                16,
                17,
                640,
                646,
                652,
                654,
                655,
                661,
                662,
                663,
                670,
                671,
                678,
                686,
                694,
                703,
                711,
            ]
        )
    )

    def store(name, img, anchor):
        img.save(out / (name + ".png"), optimize=True)
        catalog[name] = {
            "anchor": anchor,
            "size": img.size,
            "path": "res://assets/johto_gba/fields/" + name + ".png",
        }

    def crop(name, m, rect, door, outline=None):
        x, y, w, h = rect
        img = fr.patch(m, x, y, w, h)
        if outline:
            img = polygon_crop(img, outline)
        store(name, trim_lawn(img, lawn), [(door[0] - x) * 16 + 8, (door[1] - y + 1) * 16])

    crop("fr_home_red", p, (5, 3, 5, 5), (6, 7))
    crop("fr_lab", p, (13, 9, 7, 5), (16, 13))
    crop("fr_home_green", "ViridianCity", (24, 8, 5, 4), (25, 11), [(0, 0.15), (1, 0.15), (1, 0.99), (0, 0.99)])
    crop("fr_school", "ViridianCity", (24, 15, 5, 4), (25, 18))
    crop("fr_mart", "ViridianCity", (34, 16, 4, 4), (36, 19))
    crop(
        "fr_center",
        "ViridianCity",
        (24, 22, 5, 5),
        (26, 26),
        [(0, 0.22), (0.065, 0.13), (0.94, 0.13), (1, 0.22), (1, 0.94), (0.91, 1), (0.08, 1), (0, 0.94)],
    )
    crop("fr_gym", "ViridianCity", (33, 6, 6, 5), (36, 10))
    crop("fr_home_slate", "PewterCity", (32, 8, 5, 4), (33, 11))
    crop("cave_mouth", "Route4", (18, 4, 3, 2), (19, 5))
    for base in ["fr_home_red", "fr_home_green", "fr_home_slate"]:
        item = catalog[base]
        img = Image.open(out / (base + ".png")).convert("RGBA")
        ax, ay = item["anchor"]
        left = ax - 8
        # Nonenterable architecture has a window instead of a misleading front door.
        img.paste(img.crop((left + 16, ay - 16, left + 32, ay)), (left, ay - 16))
        store(base + "_sealed", img, item["anchor"])
    # The primary FireRed forest canopy has two 16px halves and three vertically stacked tiles.
    tree = Image.new("RGBA", (32, 48))
    for r, ids in enumerate([(14, 15), (22, 23), (38, 39)]):
        for x, n in enumerate(ids):
            tree.alpha_composite(fr.tile(p, n), (x * 16, r * 16))
    store("fr_tree", trim_lawn(tree, lawn), [16, 48])
    store("fr_sign", trim_lawn(fr.tile(p, 3), lawn), [8, 16])
    door_rect = [(0, 0.22), (0.08, 0.07), (0.92, 0.07), (1, 0.22), (1, 0.91), (0.89, 1), (0.11, 1), (0, 0.91)]

    # Named, individual landmarks lack a direct equivalent in FireRed or Emerald. HnS's
    # Emerald-engine contributor artwork supplies only these structures, never the geography.
    def special(name, m, rect, door, shape):
        x, y, w, h = rect
        img = hns.patch(m, x, y, w, h)
        store(name, polygon_crop(img, shape), [(door[0] - x) * 16 + 8, (door[1] - y + 1) * 16])

    special(
        "elm_lab",
        "NewBarkTown",
        (8, 5, 6, 5),
        (10, 9),
        [
            (0.025, 0.19),
            (0.07, 0.11),
            (0.12, 0.075),
            (0.85, 0.075),
            (0.97, 0.17),
            (0.985, 0.23),
            (0.985, 0.77),
            (0.84, 0.77),
            (0.84, 0.99),
            (0.005, 0.99),
            (0.005, 0.68),
            (0.025, 0.68),
        ],
    )
    special(
        "burned_tower",
        "EcruteakCity",
        (19, 8, 7, 7),
        (22, 14),
        [(0, 0), (1, 0), (1, 0.80), (0.94, 0.81), (0.94, 1), (0.04, 1), (0.04, 0.80), (0, 0.80)],
    )
    special(
        "sprout_tower",
        "VioletCity",
        (26, 0, 9, 14),
        (30, 13),
        [
            (0, 0.13),
            (0.43, 0.14),
            (0.49, 0.055),
            (0.51, 0.055),
            (0.56, 0.14),
            (1, 0.13),
            (1, 0.88),
            (0.91, 0.89),
            (0.91, 1),
            (0.09, 1),
            (0.09, 0.89),
            (0, 0.88),
        ],
    )
    special(
        "bell_tower",
        "BellchimeTrail",
        (32, 18, 7, 24),
        (35, 41),
        [
            (0.02, 0.16),
            (0.44, 0.14),
            (0.49, 0),
            (0.51, 0),
            (0.55, 0.14),
            (0.99, 0.16),
            (0.99, 0.90),
            (0.86, 0.91),
            (0.86, 1),
            (0.14, 1),
            (0.14, 0.91),
            (0.02, 0.90),
        ],
    )
    special(
        "radio_tower",
        "GoldenrodCity",
        (13, 7, 8, 16),
        (16, 22),
        [
            (0.02, 0.14),
            (0.08, 0.10),
            (0.18, 0.08),
            (0.34, 0.065),
            (0.44, 0.10),
            (0.56, 0.10),
            (0.61, 0.15),
            (0.61, 0.51),
            (0.77, 0.48),
            (0.93, 0.52),
            (0.98, 0.57),
            (0.98, 0.94),
            (0.91, 0.96),
            (0.58, 0.96),
            (0.53, 1),
            (0.30, 1),
            (0.25, 0.96),
            (0.07, 0.96),
            (0.02, 0.93),
        ],
    )
    special(
        "lighthouse",
        "OlivineCity",
        (37, 36, 5, 14),
        (39, 49),
        [
            (0.18, 0.19),
            (0.37, 0.15),
            (0.41, 0.10),
            (0.58, 0.10),
            (0.62, 0.15),
            (0.82, 0.19),
            (0.91, 0.24),
            (0.87, 0.34),
            (0.77, 0.38),
            (0.77, 0.60),
            (0.98, 0.66),
            (0.98, 0.90),
            (0.80, 1),
            (0.20, 1),
            (0.02, 0.9),
            (0.02, 0.66),
            (0.23, 0.6),
            (0.23, 0.38),
            (0.13, 0.34),
            (0.09, 0.24),
        ],
    )
    special(
        "goldenrod_station",
        "GoldenrodCity",
        (21, 17, 7, 5),
        (24, 21),
        [
            (0, 0.18),
            (0.08, 0.14),
            (0.32, 0.12),
            (0.37, 0.01),
            (0.68, 0.01),
            (0.75, 0.12),
            (0.92, 0.14),
            (0.99, 0.20),
            (0.99, 0.98),
            (0.01, 0.98),
        ],
    )
    special(
        "department_store",
        "GoldenrodCity",
        (36, 25, 7, 12),
        (39, 36),
        [
            (0.03, 0.17),
            (0.1, 0.13),
            (0.9, 0.13),
            (0.97, 0.17),
            (0.97, 0.96),
            (0.90, 1),
            (0.10, 1),
            (0.03, 0.96),
        ],
    )
    special(
        "dance_theater",
        "EcruteakCity",
        (36, 34, 7, 7),
        (39, 40),
        [(0.04, 0.13), (0.96, 0.13), (0.96, 0.78), (0.9, 0.78), (0.9, 1), (0.1, 1), (0.1, 0.78), (0.04, 0.78)],
    )
    special(
        "slowpoke_well",
        "AzaleaTown",
        (51, 5, 3, 3),
        (52, 7),
        [
            (0.02, 0.14),
            (0.12, 0.03),
            (0.88, 0.03),
            (0.98, 0.14),
            (0.98, 0.93),
            (0.91, 1),
            (0.09, 1),
            (0.02, 0.93),
        ],
    )
    special(
        "barn", "Route39", (13, 12, 6, 4), (15, 15), [(0.01, 0.04), (0.99, 0.04), (0.98, 0.98), (0.02, 0.98)]
    )
    special(
        "gate_front",
        "Route29",
        (32, 4, 6, 7),
        (34, 10),
        [(0, 0), (1, 0), (1, 0.90), (0.97, 0.90), (0.97, 0.98), (0.03, 0.98), (0.03, 0.90), (0, 0.90)],
    )
    special(
        "gate_side",
        "EcruteakCity",
        (2, 32, 7, 5),
        (8, 35),
        [
            (0, 0.22),
            (0.06, 0.20),
            (0.06, 0.02),
            (0.95, 0.02),
            (0.95, 0.2),
            (1, 0.22),
            (1, 0.9),
            (0.93, 0.94),
            (0.93, 0.99),
            (0.07, 0.99),
            (0.07, 0.94),
            (0, 0.9),
        ],
    )
    # A native HGSS side entrance puts Elm's upper floor east of his ground floor door.
    stair = hns.patch("NewBarkTown", 12, 8, 1, 2)
    store("elm_stairs", stair, [8, 8])
    # Keep both native DS entrances on one continuous laboratory façade. The door is
    # two donor cells from the west wall. Extend the roof and its window bay to the east.
    lab = Image.open(out / "elm_lab.png").convert("RGBA")
    extended = Image.new("RGBA", (lab.width + 32, lab.height))
    extended.alpha_composite(lab.crop((0, 0, 64, lab.height)), (0, 0))
    bay = lab.crop((48, 0, 64, lab.height))
    for column in [64, 80]:
        extended.alpha_composite(bay, (column, 0))
    extended.alpha_composite(lab.crop((64, 0, lab.width, lab.height)), (96, 0))
    store("elm_lab", extended, catalog["elm_lab"]["anchor"])
    gate = Image.open(out / "gate_front.png").convert("RGBA")
    narrow = Image.new("RGBA", (gate.width - 16, gate.height))
    narrow.alpha_composite(gate.crop((0, 0, 64, gate.height)), (0, 0))
    narrow.alpha_composite(gate.crop((80, 0, gate.width, gate.height)), (64, 0))
    store("cliff_gate", narrow, catalog["gate_front"]["anchor"])
    return catalog
