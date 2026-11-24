"""Galar city street plans, in the same movement cells as shop doors and exits."""

from functools import lru_cache
from pathlib import Path
import json
import zlib

from . import galar_furniture

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

from .terrain import relief

# The mains follow the edge transitions. Each square ends at a particular building,
# market or other site; small lanes joining each front door are added below.
PLANS = {
    "hammerlocke": {
        "ground": "lawn",
        "road": "slate",
        "mains": [
            (3, [(0, 15), (42, 15)]),
            (3, [(21, 0), (21, 30)]),
            (2, [(37, 15), (37, 7), (42, 7)]),
        ],
        "yards": [(18, 10, 29, 15), (34, 11, 40, 15), (6, 15, 12, 19), (34, 21, 40, 25)],
        "alleys": [
            [(9, 18), (13, 18), (13, 15)],
            [(37, 24), (39, 24), (39, 15)],
            [(18, 26), (22, 26)],
        ],
        "fixtures": {
            "tree": [(6, 11), (12, 11), (29, 8), (35, 7), (4, 21), (29, 20), (39, 27)],
            "lamp": [(17, 14), (30, 14), (19, 21), (23, 21), (35, 14)],
            "bench": [(28, 16), (11, 20)],
            "wall": [(15, 11), (18, 11), (30, 11), (33, 11)],
        },
    },
    "motostoke": {
        "ground": "yard",
        "road": "brick",
        "mains": [
            (3, [(0, 17), (38, 17)]),
            (3, [(29, 13), (29, 22), (30, 22), (30, 25), (38, 25), (38, 26)]),
            (2, [(8, 13), (29, 13)]),
        ],
        "yards": [
            (5, 9, 10, 13),
            (11, 10, 17, 14),
            (25, 9, 33, 13),
            (16, 15, 23, 20),
            (27, 21, 33, 25),
        ],
        "alleys": [
            [(8, 12), (8, 17)],
            [(14, 13), (14, 17)],
            [(16, 17), (16, 22), (24, 22), (24, 27), (26, 27)],
            [(18, 21), (18, 22)],
        ],
        "fixtures": {
            "tree": [(4, 7), (13, 6), (26, 7)],
            "lamp": [(10, 14), (18, 14), (25, 14), (33, 14), (6, 18), (26, 18), (33, 24)],
            "pipes": [(6, 18), (11, 22), (23, 19), (34, 10)],
            "crate": [(18, 21), (33, 22)],
            "bench": [(16, 14), (9, 19), (31, 25)],
        },
    },
    "hulbury": {
        "ground": "verge",
        "road": "wharf",
        "mains": [
            (2, [(0, 17), (4, 17), (4, 15), (15, 15), (15, 18), (21, 18)]),
            (2, [(15, 18), (15, 23), (17, 23), (17, 34)]),
        ],
        "yards": [
            (8, 17, 14, 21),
            (17, 14, 21, 17),
            (3, 7, 9, 10),
            (9, 9, 13, 13),
            (18, 24, 22, 27),
        ],
        "alleys": [
            [(6, 9), (6, 15)],
            [(11, 12), (11, 15)],
            [(11, 20), (15, 20)],
            [(19, 17), (19, 18)],
            [(15, 22), (23, 22)],
            [(20, 27), (17, 27)],
        ],
        "fixtures": {
            "tree": [(2, 9), (4, 10), (14, 9)],
            "lamp": [(7, 16), (16, 14), (21, 17)],
            "crate": [(9, 21), (19, 23)],
            "bollard": [(21, 22), (25, 23), (22, 25), (23, 21)],
            "bench": [(12, 13), (21, 19)],
        },
    },
    "wyndon": {
        "ground": "lawn",
        "road": "redstone",
        "mains": [
            (
                3,
                [
                    (19, 0),
                    (19, 5),
                    (20, 5),
                    (20, 13),
                    (21, 13),
                    (21, 19),
                    (21, 23),
                    (20, 25),
                    (20, 27),
                ],
            ),
            (3, [(9, 14), (33, 14), (33, 21)]),
        ],
        "yards": [
            (8, 9, 15, 14),
            (8, 3, 14, 7),
            (15, 6, 22, 10),
            (15, 13, 26, 18),
            (30, 16, 36, 21),
            (7, 20, 13, 25),
            (31, 9, 37, 13),
            (18, 26, 21, 28),
        ],
        "alleys": [
            [(11, 6), (11, 7), (19, 7)],
            [(10, 24), (7, 24), (7, 14), (12, 14)],
            [(34, 12), (34, 14)],
            [(34, 24), (34, 20)],
        ],
        "fixtures": {
            "tree": [
                (3, 5),
                (5, 5),
                (6, 11),
                (3, 20),
                (4, 25),
                (14, 24),
                (28, 5),
                (36, 6),
                (38, 25),
            ],
            "lamp": [(15, 10), (22, 10), (14, 13), (27, 13), (31, 17), (14, 18)],
            "bench": [(15, 17), (24, 18), (11, 25), (20, 28)],
        },
    },
    "spikemuth": {
        "ground": "yard",
        "road": "slate",
        "mains": [
            (3, [(21, 0), (21, 7), (17, 7), (17, 16), (24, 16), (24, 26), (21, 26), (21, 30)]),
            (3, [(5, 20), (12, 20), (12, 16), (36, 16)]),
        ],
        "yards": [(18, 10, 24, 14), (25, 10, 31, 16), (6, 20, 17, 24)],
        "alleys": [
            [(9, 24), (9, 20)],
            [(14, 24), (14, 20)],
            [(21, 13), (21, 16)],
            [(28, 13), (28, 16)],
        ],
        "fixtures": {
            "lamp": [(15, 13), (24, 13), (31, 16), (6, 20), (18, 23)],
            "crate": [(7, 22), (32, 12), (32, 17)],
            "bench": [(31, 18), (14, 18)],
        },
    },
    "wedgehurst": {
        "ground": "lawn",
        "road": "clay",
        "mains": [
            (2, [(10, 14), (34, 14), (34, 13)]),
            (2, [(8, 26), (8, 20), (15, 20), (15, 14)]),
            (2, [(17, 26), (17, 20), (23, 20), (26, 20), (26, 26)]),
            (2, [(28, 14), (28, 6), (34, 6)]),
        ],
        "yards": [(8, 10, 12, 14), (12, 9, 17, 13), (20, 8, 26, 12), (21, 16, 25, 20)],
        "alleys": [[(15, 12), (15, 14)], [(23, 11), (23, 14)], [(23, 19), (23, 20)]],
        "fixtures": {
            "tree": [(4, 10), (6, 10), (19, 8), (28, 10), (12, 17), (11, 20), (30, 23)],
            "lamp": [(13, 13), (17, 13), (26, 12)],
            "bench": [(16, 13), (26, 18)],
        },
    },
}

# Hue the native source metatiles to a lower-contrast, location-specific ramp.
# Road and verge remain legible at the 16-pixel walking scale.
MATERIALS = {
    "lawn": ("LittlerootTown", 0x001, (136, 174, 132), 0.36),
    "verge": ("LittlerootTown", 0x001, (147, 174, 128), 0.33),
    "sand": ("SlateportCity", 0x124, (217, 202, 154), 0.78),
    "yard": ("SlateportCity", 0x211, (160, 151, 137), 0.34),
    "brick": ("SlateportCity", 0x202, (181, 131, 109), 0.75),
    "redstone": ("SlateportCity", 0x202, (179, 140, 126), 0.68),
    "slate": ("RustboroCity", 0x2BB, (151, 160, 156), 0.72),
    "clay": ("LittlerootTown", 0x121, (200, 174, 137), 0.85),
    "wharf": ("SlateportCity", 0x202, (171, 166, 148), 0.64),
    "court": ("SlateportCity", 0x211, (201, 189, 159), 0.53),
    "flag": ("RustboroCity", 0x2BB, (182, 183, 167), 0.79),
    "planks": ("PacifidlogTown", 0x14, (164, 136, 96), 1.0),
    "rock": ("SlateportCity", 0x124, (159, 146, 123), 0.58),
    "water": ("SlateportCity", 0x0A1, (92, 156, 187), 0.63),
}


@lru_cache(None)
def chip(emerald, material):
    layout, mid, colour, contrast = MATERIALS[material]
    src = emerald.metatile(layout, mid).convert("RGB")
    pixels = np.asarray(src, dtype=float)
    light = pixels @ [0.31, 0.53, 0.16]
    values = np.asarray(colour) + (light - light.mean())[:, :, None] * contrast
    return Image.fromarray(np.clip(values, 0, 255).astype("uint8"))


def repeat(tile, size):
    return Image.fromarray(np.tile(np.asarray(tile), (size[1] // 16, size[0] // 16, 1)))


def points(cells):
    return [(16 * x + 8, 16 * y + 8) for x, y in cells]


def street_mask(size, paths):
    mask = Image.new("L", size)
    draw = ImageDraw.Draw(mask)
    for width, path in paths:
        width *= 16
        nodes = points(path)
        draw.line(nodes, fill=255, width=width, joint="curve")
        radius = width // 2
        for x, y in nodes:
            draw.ellipse((x - radius, y - radius, x + radius - 1, y + radius - 1), fill=255)
    return mask


def terrace_mask(size, yards):
    mask = Image.new("L", size)
    draw = ImageDraw.Draw(mask)
    for x, y, r, b in yards:
        draw.rounded_rectangle(
            (16 * x + 2, 16 * y + 2, 16 * (r + 1) - 3, 16 * (b + 1) - 3), radius=8, fill=255
        )
    return mask


def paint(im, texture, mask):
    im.paste(texture, (0, 0), mask)


def kerb(im, mask, openings, light, shade):
    # Mark the outermost pixel and the inset highlight; no kerb across a junction.
    inset = mask.filter(ImageFilter.MinFilter(3))
    rim = ImageChops.subtract(mask, inset)
    highlight = ImageChops.subtract(inset, mask.filter(ImageFilter.MinFilter(5)))
    paint(im, shade, ImageChops.subtract(rim, openings))
    paint(im, light, ImageChops.subtract(highlight, openings))


def add_furniture(data, plan):
    props = data["hoenn_art"]["p"]
    cells = data["tiles"]
    protected = {tuple(data["spawn"])}
    for group in ("warps", "objects", "npcs"):
        protected.update(tuple(v["at"]) for v in data[group])
    for warp in data["warps"]:
        x, y = warp["at"]
        protected.add((x, y + 1))
    for kind, spots in plan["fixtures"].items():
        path = {
            "tree": "res://assets/emerald/field/tree.png",
            "lamp": "res://assets/emerald/field/streetlamp.png",
            "bench": "res://assets/galar/street/bench.png",
            "crate": "res://assets/switch_fields/props/crate.png",
            "bollard": "res://assets/galar/street/bollard.png",
            "wall": "res://assets/galar/street/wall.png",
            "pipes": "res://assets/galar/street/pipes.png",
        }[kind]
        with Image.open(Path(__file__).resolve().parents[2] / path[6:]) as art:
            anchor = [art.width // 2, art.height]
        for x, y in spots:
            prop = [path, x, y, anchor]
            occupied = [(x, y), (x - 1, y)] if kind in ("tree", "bench", "crate") else [(x, y)]
            if kind == "wall":
                occupied = [(x - 1, y), (x, y), (x + 1, y)]
            if prop in props or any(cells[b][a] != 0 or (a, b) in protected for a, b in occupied):
                continue
            if any(abs(p[1] - x) <= 1 and abs(p[2] - y) <= 1 for p in props):
                continue
            props.append(prop)
            for a, b in occupied:
                cells[b][a] = 1


def city_art(emerald, key, data, plan, rows):
    w, h = data["size"]
    size = (w * 16, h * 16)
    base = relief(rows, w, h, zlib.crc32(key.encode()) % 1993)
    cells = np.array(data["tiles"])
    water = cells == 2
    # Map limits still block walking, but an open sea or river continues beyond
    # the camera. Only extend water where the elevation plan and adjacent wet cell agree.
    water[0] |= (base[0] == "W") & water[1]
    water[-1] |= (base[-1] == "W") & water[-2]
    water[:, 0] |= (base[:, 0] == "W") & water[:, 1]
    water[:, -1] |= (base[:, -1] == "W") & water[:, -2]
    # Rocky brows follow the true cliff footprint. Existing buildings, signs and trees
    # also block movement; these are never turned into cliffs or piers.
    cliff = (base == "C") & (cells == 1)
    structures = [(x, y) for _, x, y, *_ in data["hoenn_art"]["p"]]
    for x, y in structures:
        if y > 0:
            cliff[max(0, y - 2) : y + 1, max(0, x - 2) : x + 3] = False
    water_mask = Image.fromarray(water.astype("uint8") * 255).resize(size, Image.Resampling.NEAREST)
    # Soften tile corners on the beach while keeping the centre of every collision
    # cell on its actual material. Brick canal quays keep their squared corners.
    if key == "galar_hulbury":
        water_mask = water_mask.filter(ImageFilter.GaussianBlur(5)).point(
            lambda p: 255 if p >= 128 else 0
        )
    rock_mask = Image.fromarray(cliff.astype("uint8") * 255).resize(size, Image.Resampling.NEAREST)
    land = ImageChops.invert(ImageChops.lighter(water_mask, rock_mask))
    mains = street_mask(size, plan["mains"])
    yards = terrace_mask(size, plan["yards"])
    alleys = street_mask(size, [(1, path) for path in plan["alleys"]])
    roadway = ImageChops.lighter(mains, alleys)
    # The castled town and industrial quarters have deep plazas and courtyards.
    # Front walks cross the kerb where the lane and their forecourt intersect.
    im = repeat(chip(emerald, plan["ground"]), size)
    if key == "galar_hulbury":
        sand = Image.fromarray(np.isin(base, ["W", "S"]).astype("uint8") * 255).resize(
            size, Image.Resampling.NEAREST
        )
        paint(im, repeat(chip(emerald, "sand"), size), sand)
    court_type = "flag" if plan["road"] in ("brick", "slate", "redstone") else "court"
    paint(im, repeat(chip(emerald, court_type), size), yards)
    kerb(im, yards, roadway, "#d2c5a7", "#918b78")
    paint(im, repeat(chip(emerald, plan["road"]), size), roadway)
    kerb(im, roadway, yards, "#d6c9ac", "#918a7b")
    dress_ground(im, key, land, roadway, yards, emerald)
    paint(im, repeat(chip(emerald, "rock"), size), rock_mask)
    # A bank has a cap and a short shaded face, facing down towards the player.
    down = Image.new("L", size)
    down.paste(rock_mask, (0, -8))
    face = ImageChops.subtract(rock_mask, down)
    rockface = Image.new("RGB", (32, 16), "#9c8c77")
    strata = ImageDraw.Draw(rockface)
    strata.line((0, 4, 3, 3, 8, 3, 11, 5, 16, 4, 21, 5, 26, 3, 31, 4), fill="#ada08a")
    strata.line((6, 3, 8, 6, 7, 8), fill="#897e6b")
    strata.line((18, 4, 20, 7, 23, 8), fill="#897b6c")
    rock_texture = Image.new("RGB", size)
    for y in range(0, size[1], 16):
        for x in range(0, size[0], 32):
            rock_texture.paste(rockface, (x, y))
    paint(im, rock_texture, face)
    paint(im, "#736f63", ImageChops.subtract(rock_mask, ImageChops.offset(rock_mask, 0, -1)))
    paint(im, repeat(chip(emerald, "water"), size), water_mask)
    if water.any():
        quay = ImageChops.multiply(water_mask, water_mask.filter(ImageFilter.MinFilter(5)))
        edge = ImageChops.subtract(water_mask, quay)
        paint(im, "#b3cec2", edge)
        shoreline = ImageChops.multiply(
            land, ImageChops.subtract(water_mask.filter(ImageFilter.MaxFilter(5)), water_mask)
        )
        paint(im, "#b5ab8e", shoreline)
        # Calm water uses sparse short glints, concentrated below the stone quay.
        ripples = Image.new("RGBA", size)
        draw = ImageDraw.Draw(ripples)
        for y, x in np.argwhere(water):
            phase = int((int(x) * 73856093 ^ int(y) * 19349663 ^ 83492791) % 43)
            if phase < 4:
                px, py = x * 16 + 3 + phase * 2, y * 16 + 5 + (x % 5)
                draw.line((px, py, px + 3, py + 1, px + 7, py), fill="#9bc5ce")
        im.paste(ripples, (0, 0), ripples)
        # Each wooden deck has a mapped purpose and a continuous landing. The
        # south gate in Hammerlocke, for instance, is a stone causeway throughout.
        docks = {
            "galar_hammerlocke": [(6, 18, 10, 18)],
            "galar_motostoke": [(33, 23, 37, 24)],
            "galar_hulbury": [(19, 22, 26, 23)],
            "galar_wyndon": [(14, 13, 17, 13), (26, 14, 30, 14), (19, 21, 21, 26)],
        }
        wood = np.zeros_like(water)
        for left, top, right, bottom in docks[key]:
            wood[top : bottom + 1, left : right + 1] = True
        wood &= ~water
        if key == "galar_wyndon":
            wood[13:20, 16:27] = False
            civic = np.zeros_like(water)
            civic[13:20, 16:27] = ~water[13:20, 16:27]
            podium = Image.fromarray(civic.astype("uint8") * 255).resize(
                size, Image.Resampling.NEAREST
            )
            paint(im, repeat(chip(emerald, "flag"), size), podium)
            kerb(im, podium, mains, "#d7c9a9", "#7e887e")
        # A naturally open harbour inlet was spanned by the route survey. The actual
        # walkable strip takes marine boards, not an unconnected stretch of road.
        deck = Image.fromarray(wood.astype("uint8") * 255).resize(size, Image.Resampling.NEAREST)
        planks = chip(emerald, "planks").copy()
        pen = ImageDraw.Draw(planks)
        for sy in (0, 5, 10):
            pen.line((0, sy, 15, sy), fill="#9a8060")
            pen.line((1, sy + 1, 14, sy + 1), fill="#c4a780")
            pen.point((2, sy + 2), fill="#867456")
            pen.point((13, sy + 2), fill="#867456")
        paint(im, repeat(planks, size), deck)
        kerb(im, deck, ImageChops.lighter(roadway, yards), "#ccb38b", "#917854")
        # A stone course visible below a bank gives the canals their depth. Keep
        # open sea and beach edges soft, and leave the timber pier on its own piles.
        wet_below = ImageChops.multiply(water_mask, ImageChops.offset(land, 0, 4))
        if key in ("galar_hammerlocke", "galar_motostoke", "galar_wyndon"):
            wall = Image.new("RGB", (16, 16), "#838e86")
            pen = ImageDraw.Draw(wall)
            for sy in (0, 4, 8, 12):
                pen.line((0, sy, 15, sy), fill="#73857d")
                j = (sy + 3) % 16
                pen.line((j, sy, j, sy + 3), fill="#718078")
            paint(im, repeat(wall, size), wet_below)
        if key != "galar_wyndon":
            # Rails follow straight waterfront segments in front of the water.
            # Leave crossings and beaches open, and keep rail shadows on the wet side.
            edgepen = ImageDraw.Draw(im)
            for y in range(2, h - 1):
                for x in range(2, w - 2):
                    if not water[y, x - 1 : x + 2].all() or water[y - 1, x - 1 : x + 2].any():
                        continue
                    if (
                        wood[y - 1, x]
                        or base[y - 1, x] in "SG"
                        or key == "galar_hulbury"
                        and y > 26
                    ):
                        continue
                    left = x * 16
                    top = y * 16
                    edgepen.line((left, top - 2, left + 15, top - 2), fill="#6c7369")
                    edgepen.line((left, top - 4, left + 15, top - 4), fill="#b4b3a1")
                    if x % 2 == 0:
                        edgepen.rectangle((left + 2, top - 6, left + 4, top + 1), fill="#6e7267")
                        edgepen.point((left + 3, top - 6), fill="#d4c7ab")
    return im


def fit_landmarks(mid, data):
    props = data["hoenn_art"]["p"]
    root = Path(__file__).resolve().parents[2]

    def reskin(prop, name):
        name = "res://assets/galar/street/" + name + ".png"
        with Image.open(root / name[6:]) as image:
            prop[0], prop[3] = name, [image.width // 2, image.height]

    for prop in props:
        if prop[0] in (
            "res://assets/switch_fields/props/bench.png",
            "res://assets/emerald/field/carebench.png",
        ):
            reskin(prop, "bench")
        if mid == "galar_wyndon" and prop[0].endswith("/props/ferris.png"):
            reskin(prop, "wheel")
        if mid == "galar_motostoke" and prop[0].endswith("/props/chimney.png"):
            reskin(prop, "chimney")
        if mid == "galar_motostoke" and prop[0].endswith("/props/arch.png"):
            reskin(prop, "hoist")
        if mid == "galar_hammerlocke" and prop[0].endswith("/props/column.png"):
            reskin(prop, "gatepier")
    if mid != "galar_hammerlocke":
        return
    old = next((q for q in props if q[1:3] == [9, 27] and q[0].endswith("/props/arch.png")), None)
    if old is None:
        return
    props.remove(old)
    for y in (26, 27):
        for x in (8, 9, 10):
            data["tiles"][y][x] = 2
    for x in (18, 22):
        pier = ["", x, 26, []]
        reskin(pier, "gatepier")
        props.append(pier)
        data["tiles"][26][x] = 1
    for site in data["switch_sites"]:
        if site["kind"] == "arch":
            site["at"] = [20, 26]


def dress_ground(im, key, land, roadway, yards, emerald):
    """Low, walkable inlays and planting borders leave all original crossings open."""
    # A few bedding plots are pegged to the flanks of an identified square, not
    # sprinkled through the walking route or across the page in a checkerboard.
    beds = {
        "galar_hammerlocke": [(12, 8, 17, 10), (29, 9, 32, 11), (24, 19, 28, 20), (3, 18, 5, 20)],
        "galar_motostoke": [(4, 7, 7, 8), (11, 5, 16, 6), (25, 6, 30, 7), (4, 20, 7, 20)],
        "galar_hulbury": [(1, 10, 4, 12), (10, 6, 14, 7), (13, 11, 15, 12)],
        "galar_wyndon": [(2, 7, 6, 9), (24, 7, 27, 9), (3, 21, 5, 24), (29, 22, 31, 24)],
        "galar_spikemuth": [(4, 11, 8, 12), (33, 19, 37, 20)],
        "galar_wedgehurst": [(5, 9, 8, 10), (25, 9, 27, 10), (11, 16, 13, 17)],
    }
    mask = ImageChops.multiply(land, terrace_mask(im.size, beds[key]))
    mask = ImageChops.subtract(mask, ImageChops.lighter(yards, roadway))
    paint(im, repeat(chip(emerald, "lawn"), im.size), mask)
    kerb(im, mask, Image.new("L", im.size), "#b5ba91", "#889575")
    grass = ImageDraw.Draw(im)
    for x, y, r, b in beds[key]:
        for px in range(x * 16 + 10, r * 16 + 8, 10):
            for py in range(y * 16 + 10, b * 16 + 8, 9):
                py += ((px // 10) % 2) * 3
                if not mask.getpixel((px, py)):
                    continue
                grass.line((px - 2, py + 2, px, py + 3, px + 2, py), fill="#739477")
                if (px // 10 + py // 9) % 3 == 0:
                    grass.point((px, py), fill="#e2c18a")
                    grass.point((px - 1, py - 1), fill="#e5dbb6")
    flower = emerald.metatile("LittlerootTown", 0x004, upper_only=True)
    for lx, ty, rx, by in beds[key]:
        for gx in range(lx + 1, rx, 2):
            px, py = 16 * gx, 16 * by
            if mask.getpixel((px + 8, py + 8)):
                im.paste(flower, (px, py), flower)
    # Slotted metal drain covers at the factory platforms and along Spikemuth's
    # service lane; the daylight towns use brass corner studs in their squares.
    drains = (
        {
            "galar_motostoke": [(5, 17), (11, 17), (23, 17), (32, 17), (29, 23)],
            "galar_spikemuth": [(14, 16), (20, 16), (27, 16), (34, 16)],
        }
    ).get(key, [])
    for x, y in drains:
        X, Y = x * 16 + 2, y * 16 + 11
        grass.rectangle((X, Y, X + 11, Y + 4), fill="#877c73")
        for xx in range(X + 2, X + 11, 3):
            grass.line((xx, Y + 1, xx, Y + 3), fill="#615e5b")


def apply(emerald, specifications, root):
    galar_furniture.write(root)
    for city, plan in PLANS.items():
        mid = "galar_" + city
        path = root / "content/regions/galar/maps" / (mid + ".json")
        data = json.loads(path.read_bytes())
        fit_landmarks(mid, data)
        add_furniture(data, plan)
        picture = city_art(emerald, mid, data, plan, specifications[mid][0])
        image_file = root / data["hoenn_art"]["scene"][0][6:]
        picture.quantize(200, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).save(
            image_file, optimize=True
        )
        path.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n")
