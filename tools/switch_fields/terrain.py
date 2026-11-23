"""Turn a hand-authored relief plan into Emerald terrain with matching movement cells."""

from functools import lru_cache
import numpy as np
from scipy.ndimage import map_coordinates
from PIL import Image, ImageDraw
from kalos_gym_rooms import tile
from bake_emerald_field import TOWN
from johto_gba_outdoor import AUTOTILES

FOREST = "FOLMHT"
ROCK = "CK"
WET = "W"
SOLID = ROCK + WET


def relief(rows, w, h, seed):
    width = max(map(len, rows))
    codes = np.array(
        [
            [
                row[min(len(row) - 1, int((x + 0.5) * len(row) / width))]
                for x in range(width)
            ]
            for row in rows
        ]
    )
    y, x = np.mgrid[:h, :w]
    phase = seed / 311
    yy = np.clip(
        y / (h - 1) * (len(rows) - 1)
        + 0.13 * np.sin(x * 0.29 + phase)
        + 0.10 * np.cos(y * 0.21 + x * 0.11),
        0,
        len(rows) - 1,
    )
    xx = np.clip(
        x / (w - 1) * (width - 1)
        + 0.17 * np.sin(y * 0.35 + phase)
        + 0.1 * np.cos(x * 0.19 - y * 0.21),
        0,
        width - 1,
    )
    materials = sorted(set(codes.flat))
    weights = np.stack(
        [
            map_coordinates(
                (codes == k).astype(float), [yy, xx], order=1, mode="nearest"
            )
            for k in materials
        ]
    )
    return np.array(materials)[weights.argmax(axis=0)]


@lru_cache(None)
def ground(em, k):
    bank = {
        "U": ("Route113", 0x71),
        "V": ("GraniteCave_1F", 0x201),
        "J": ("RustboroCity", 0x2BB),
        "D": ("Route111", 0x251),
        "S": (TOWN, 0x121),
        "I": ("ShoalCave_LowTideIceRoom", 0x38D),
        "Z": ("GraniteCave_1F", 0x201),
        "P": ("RustboroCity", 0x2BB),
        "W": (TOWN, 0x170),
    }
    if k in bank:
        return em.metatile(*bank[k]).convert("RGB")
    if k == "Y":
        return tile("tall")
    if k == "B":
        return tile("flowers")
    im = tile("grass").copy()
    d = ImageDraw.Draw(im)
    if k in "MHT":
        im = im.convert("RGB")
        mapper = {
            "M": lambda r, g, b: (r * 3 // 5 + 10, g * 3 // 5 + 17, b * 4 // 5 + 28),
            "H": lambda r, g, b: (r + 8, g - 4, b - 16),
            "T": lambda r, g, b: (r + 41, g - 20, b - 21),
        }[k]
        im.putdata(
            [tuple(min(255, max(0, v)) for v in mapper(*pix)) for pix in im.getdata()]
        )
        return im
    if k == "N":
        im = Image.new("RGB", (16, 16), "#e2e6de")
        d = ImageDraw.Draw(im)
        d.line((2, 5, 6, 5), fill="#d2dbd9")
        d.line((9, 13, 12, 12), fill="#f3f3e0")
        d.point((11, 3), fill="#c6d6d7")
    if k in ["X", "E"]:
        im = tile("sand").copy()
        im.putdata(
            [
                (r * 4 // 5 - 20, g * 4 // 5 - 12, b * 5 // 6)
                if k == "X"
                else (r * 2 // 3, g * 4 // 5, b * 3 // 4)
                for r, g, b in im.getdata()
            ]
        )
        d = ImageDraw.Draw(im)
        d.line((1, 8, 5, 8), fill="#a7a488" if k == "X" else "#96a98a")
    if k == "A":
        im = tile("sand").copy()
        d = ImageDraw.Draw(im)
        for x in (2, 9):
            d.line((x, 0, x, 15), fill="#ab8a63", width=3)
            d.line((x + 1, 0, x + 1, 15), fill="#c6a97c")
            d.line((x - 1, 4, x + 2, 2), fill="#839058")
            d.line((x - 1, 11, x + 2, 9), fill="#889a60")
    return im


def shape(cells, k, x, y):
    h, w = cells.shape
    around = lambda a, b: b < 0 or a < 0 or b >= h or a >= w or cells[b, a] == k
    up, down, left, right = (
        around(x, y - 1),
        around(x, y + 1),
        around(x - 1, y),
        around(x + 1, y),
    )
    return (
        (0 if not up else 2 if not down else 1),
        (0 if not left else 2 if not right else 1),
        [up, down, left, right],
    )


@lru_cache(None)
def chip(em, k, idx, idy, neighbours, under):
    if k in "GCFLTYBMHOSJIVXEDNAZUP":
        return (
            ground(em, "N" if k == "L" else k)
            if k != "C"
            else em.metatile(TOWN, AUTOTILES["cliff"][idy][idx]).convert("RGB")
        )
    if k == "K":
        return em.metatile(
            "GraniteCave_1F",
            [[0x210, 0x211, 0x212], [0x218, 0x201, 0x21A], [0x220, 0x221, 0x222]][idy][
                idx
            ],
        ).convert("RGB")
    if k == "W":
        im = em.metatile(TOWN, 0x170).convert("RGB")
        d = ImageDraw.Draw(im)
        for n, ok in enumerate(neighbours):
            if ok:
                continue
            pts = [(0, 1, 15, 1), (0, 14, 15, 14), (1, 0, 1, 15), (14, 0, 14, 15)][n]
            d.line(pts, fill="#a8c8bb", width=3)
            d.line(
                [(0, 0, 15, 0), (0, 15, 15, 15), (0, 0, 0, 15), (15, 0, 15, 15)][n],
                fill="#a8a989",
            )
        return im
    if k == "p":
        return ground(em, "P")
    if k == "d":
        if under in "FLGBYO":
            return em.metatile(TOWN, AUTOTILES["trail"][idy][idx]).convert("RGB")
        return ground(
            em,
            "N"
            if under in "NI"
            else "V"
            if under in "KVZ"
            else "D"
            if under == "D"
            else "S",
        )
    if k in ("=", "!"):
        im = Image.new("RGB", (16, 16), "#b59d74")
        d = ImageDraw.Draw(im)
        for i in (1, 6, 11):
            d.line((0, i, 15, i), fill="#876f5c")
            d.line((1, i + 1, 14, i + 1), fill="#ccb68c")
            d.point((1, i + 3), fill="#7c6b58")
            d.point((13, i + 3), fill="#7c6b58")
        return im.transpose(Image.Transpose.TRANSPOSE) if k == "!" else im
    if k == "^":
        im = ground(em, "J").copy()
        d = ImageDraw.Draw(im)
        for yy in [2, 7, 12]:
            d.line((0, yy, 15, yy), fill="#9b9688", width=2)
            d.line((0, yy + 2, 15, yy + 2), fill="#e6dcc1")
        return im
    raise KeyError(k)


def paint(em, base, surface):
    h, w = base.shape
    out = Image.new("RGB", (16 * w, 16 * h))
    for y in range(h):
        for x in range(w):
            k = surface[y, x]
            row, col, adj = shape(surface, k, x, y)
            out.paste(chip(em, k, col, row, tuple(adj), base[y, x]), (x * 16, y * 16))
    return out


@lru_cache(None)
def masonry(palette, variant=0):
    """Seamless staggered pixel stonework, with deliberately quiet grout at game scale."""
    palettes = {
        "warm": ("#bbad95", "#c8b99e", "#ab9d88", "#d2c3a8"),
        "gray": ("#a3a9a6", "#b0b6b1", "#969e9a", "#bac0b7"),
        "brick": ("#b58b79", "#bf9681", "#a68172", "#cda58d"),
        "dark": ("#777886", "#828491", "#696c79", "#93949c"),
        "wood": ("#bb956e", "#c8a37b", "#a88263", "#d3b18b"),
        "cave": ("#9c8674", "#a7917b", "#8c796d", "#b29c84"),
        "slate": ("#738b8a", "#809594", "#687e80", "#98a7a0"),
        "snow": ("#d6deda", "#e2e7e1", "#c6d3d2", "#eef0e8"),
        "lab": ("#738896", "#8498a1", "#667c8b", "#a3b4b8"),
    }
    base, upper, lower, high = palettes[palette]
    im = Image.new("RGB", (16, 16), base)
    d = ImageDraw.Draw(im)
    if palette in ("cave", "slate", "snow"):
        for x, y in [
            [(2, 3), (9, 12), (13, 6)],
            [(7, 5), (1, 12), (14, 15)],
            [(4, 9), (13, 4), (6, 15)],
        ][variant % 3]:
            d.line((x, y, x + 2, y), fill=upper)
            d.point((x - 1, y + 1), fill=lower)
        return im
    for y in (0, 8):
        x = (y + 3) % 16
        d.line((0, y, 15, y), fill=lower)
        d.line((x, y, x, y + 7), fill=lower)
        d.line((x + 1, y + 1, min(15, x + 5), y + 1), fill=upper)
    if palette == "wood":
        d.line((2, 5, 7, 5), fill=upper)
        d.point((13, 12), fill=upper)
    return im


MATERIALS = {
    "brick": {
        "galar_motostoke",
        "galar_wedgehurst",
        "galar_wyndon",
        "paldea_cabo",
        "paldea_medali",
        "paldea_marinada",
    },
    "dark": {"galar_spikemuth", "galar_ballonlea", "galar_rose"},
    "wood": {"hisui_jubilife", "hisui_heights"},
    "gray": {
        "galar_hammerlocke",
        "paldea_levincia",
        "paldea_league",
        "paldea_glaseado",
        "galar_circhester",
        "paldea_cascarrafa",
    },
    "snow": {"paldea_montenevera", "galar_10", "galar_slope"},
}


def finish_ground(em, mid, base, surface):
    im = paint(em, base, surface)
    h, w = base.shape
    style = next((k for k, ids in MATERIALS.items() if mid in ids), "warm")
    miners = mid in (
        "galar_mine",
        "galar_mine2",
        "galar_tunnel",
        "galar_pass_kalos_cyllage",
        "paldea_cave",
        "paldea_inlet",
    )
    shade = (
        "slate"
        if mid in ("galar_mine2", "galar_pass_kalos_cyllage", "paldea_inlet")
        else "cave"
    )
    for y in range(h):
        for x in range(w):
            k = surface[y, x]
            variant = (x * 7 + y * 3 + x * y) % 3
            if k == "W":
                tex = em.metatile(TOWN, 0xA1).convert("RGB")
                pen = ImageDraw.Draw(tex)
                edge = x == 0 or y == 0 or x == w - 1 or y == h - 1
                for dx, dy, lines in [
                    (-1, 0, (0, 0, 0, 15)),
                    (1, 0, (15, 0, 15, 15)),
                    (0, -1, (0, 0, 15, 0)),
                    (0, 1, (0, 15, 15, 15)),
                ]:
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and surface[ny, nx] not in "W=!":
                        pen.line(lines, fill="#a2ced0", width=3)
                        pen.line(
                            lines,
                            fill="#bbc7a1" if base[ny, nx] in "SGYBXE" else "#a7b9ac",
                        )
                noise = (x * 73856093 ^ y * 19349663) % 31
                if noise < 6 and not edge:
                    dx = 2 + noise % 4
                    dy = 3 + (y + x) % 7
                    pen.line((dx, dy, dx + 3, dy + 1, dx + 7, dy), fill="#a2cfe0")
                    pen.point((dx + 8, dy - 1), fill="#80b9d7")
            elif mid == "hisui_mirelands" and k in "dX":
                tex = masonry("cave", variant).copy()
                pen = ImageDraw.Draw(tex)
                if (x + y) % 3 == 0:
                    pen.line((2, 9, 5, 9), fill="#93937a")
                    pen.point((8, 6), fill="#879473")
            elif k in "PpJ":
                tex = masonry(style)
            elif k == "C" and y + 1 < h and surface[y + 1, x] == "C":
                tex = (
                    em.metatile("Route113", 0x218).convert("RGB")
                    if (x + y) % 9 == 0
                    else masonry("cave", variant)
                )
            elif k == "K":
                tex = masonry("slate" if shade == "cave" else "cave", variant).copy()
                pix = ImageDraw.Draw(tex)
                if y + 1 >= h or surface[y + 1, x] != "K":
                    pix.rectangle(
                        (0, 7, 15, 15), fill="#64595b" if shade == "cave" else "#4d6069"
                    )
                    pix.line((0, 6, 5, 5, 12, 6, 15, 4), fill="#a29282", width=2)
                    pix.line((7, 8, 7, 12), fill="#69676a")
                else:
                    for yy in (2, 10):
                        xx = (y % 2) * 6 if yy == 2 else 5
                        pix.line(
                            (xx, yy, xx + 5, yy - 1, xx + 10, yy + 1), fill="#737376"
                        )
            elif k in "VZ" or k == "d" and miners:
                tex = masonry(shade, variant)
            elif k == "N" or k == "d" and base[y, x] in "NI":
                tex = masonry("snow", variant)
            else:
                continue
            im.paste(tex, (x * 16, y * 16))
    return im
