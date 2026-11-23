"""Extract Emerald architectural details for Melemele's newly drawn GBA streets.

Usage: python3 tools/alola_settlement_art.py /path/to/pret/pokeemerald
The source coordinates refer to the compiled 16x16 layout, not a screenshot.
"""

import argparse
from pathlib import Path
from PIL import Image, ImageDraw, ImageOps
from bake_emerald_field import Emerald, cut_background

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/alola/streets"


def hut(width, thatch, plaster, trim):
    # A low hipped Hawaiian roof, open veranda, braided posts and timber sill.
    w, h = width, 64
    im = Image.new("RGBA", (w, h))
    d = ImageDraw.Draw(im)
    edge = "#453e37"
    shadow = "#755843"
    light = "#eed89b"
    d.rounded_rectangle((3, 54, w - 3, 60), 3, fill="#707e54")
    d.rectangle((7, 29, w - 8, 57), fill=edge)
    d.rectangle((9, 30, w - 10, 55), fill=plaster)
    for x in range(10, w - 9, 4):
        d.line((x, 34, x, 55), fill=light)
    d.rectangle((5, 52, w - 6, 57), fill=shadow, outline=edge)
    d.line((5, 53, w - 6, 53), fill="#d4ac69")
    d.polygon(
        [(1, 28), (9, 17), (22, 5), (w - 23, 5), (w - 9, 17), (w - 2, 28), (w - 2, 33), (2, 33)], fill=edge
    )
    for y in range(6, 32):
        left = max(3, 23 - (y - 5)) if y < 25 else 3
        color = thatch[0 if y < 14 else 1 if y < 24 else 2]
        d.line((left, y, w - 1 - left, y), fill=color)
        for x in range(left + 1 + (y // 4) % 3, w - left - 2, 5):
            if y % 5 in (2, 3):
                d.point((x, y), fill=thatch[3])
                if y % 5 == 3:
                    d.point((x - 1, y), fill=thatch[3])
        if y in (12, 22, 29):
            for x in range(left, w - left - 1, 4):
                d.line((x, y, x + 1, y + 1), fill=thatch[2])
    d.line((22, 4, w - 23, 4), fill=edge, width=2)
    d.line((23, 4, w - 24, 4), fill=light)
    for x in (8, w - 11):
        d.rectangle((x, 31, x + 3, 54), fill=trim, outline=edge)
        for y in (34, 43, 50):
            d.line((x, y, x + 3, y), fill=light)
    for x in (14, w - 26):
        d.rectangle((x, 36, x + 10, 45), fill="#493e39", outline=shadow)
        d.rectangle((x + 1, 37, x + 8, 43), fill="#719caa")
        d.line((x + 2, 37, x + 2, 42), fill="#a8d0cb")
        d.line((x + 5, 37, x + 5, 44), fill=edge)
        d.line((x - 1, 46, x + 11, 46), fill=light)
    cx = w // 2
    d.rectangle((cx - 7, 33, cx + 7, 55), fill=edge)
    d.rectangle((cx - 5, 35, cx + 5, 54), fill="#392f35")
    d.line((cx - 6, 34, cx + 6, 34), fill=trim)
    for y, col in ((56, "#714f38"), (58, "#ddb982"), (60, "#986e4d"), (62, "#e5c78c")):
        d.line((cx - 9 - (y - 56) // 3, y, cx + 9 + (y - 56) // 3, y), fill=col, width=2)
    return im


def palm():
    im = Image.new("RGBA", (46, 51))
    d = ImageDraw.Draw(im)
    d.ellipse((16, 43, 32, 48), fill="#658665")
    d.polygon(
        [(21, 47), (28, 47), (28, 42), (25, 35), (23, 21), (20, 15), (17, 16), (18, 29), (20, 39)],
        fill="#5c5843",
    )
    d.line([(22, 44), (23, 40), (21, 35), (19, 22)], fill="#af915a", width=3)
    for x, y in [(22, 40), (21, 35), (20, 30), (19, 25)]:
        d.line((x, y, x + 3, y - 1), fill="#d2b879")
    for spine, leaf in [
        (
            [(21, 17), (12, 15), (3, 17), (0, 22)],
            [(20, 16), (9, 12), (2, 16), (0, 23), (6, 20), (4, 23), (11, 20), (12, 18)],
        ),
        (
            [(21, 16), (27, 9), (36, 8), (44, 12)],
            [(20, 15), (25, 8), (33, 4), (38, 6), (45, 12), (37, 11), (39, 15), (34, 12), (30, 11)],
        ),
        (
            [(21, 16), (17, 7), (11, 3), (5, 3)],
            [(21, 17), (16, 7), (11, 2), (5, 1), (2, 3), (7, 5), (7, 8), (12, 8), (11, 11), (16, 12)],
        ),
        (
            [(22, 15), (29, 13), (40, 17), (44, 23)],
            [
                (20, 16),
                (26, 12),
                (34, 12),
                (41, 16),
                (45, 24),
                (39, 20),
                (39, 23),
                (35, 19),
                (35, 22),
                (30, 18),
                (28, 20),
            ],
        ),
        (
            [(20, 15), (15, 19), (8, 26), (8, 30)],
            [
                (20, 14),
                (14, 16),
                (8, 21),
                (6, 30),
                (10, 27),
                (11, 29),
                (12, 24),
                (15, 23),
                (15, 25),
                (18, 20),
            ],
        ),
        (
            [(21, 17), (26, 22), (30, 31)],
            [(21, 16), (28, 19), (31, 25), (31, 33), (28, 29), (27, 31), (26, 26), (24, 28), (23, 22)],
        ),
        (
            [(21, 15), (20, 7), (23, 2)],
            [(18, 15), (17, 8), (20, 4), (24, 0), (24, 6), (26, 4), (23, 13), (22, 17)],
        ),
    ]:
        d.polygon(leaf, fill="#326841", outline="#345b3a")
        d.line(spine, fill="#99b54d", width=2)
    d.ellipse((18, 15, 22, 19), fill="#8f713d")
    d.point((19, 16), fill="#dfbc60")
    return im


def frame_art():
    return {
        "palm": palm(),
        "hala_lodge": hut(94, ["#d9b451", "#b78a40", "#8d653d", "#f5d480"], "#deba73", "#ad6546"),
        "village_hut": hut(62, ["#bbba62", "#a3a354", "#787d44", "#ded486"], "#d9c28a", "#9d7751"),
        "village_cottage": hut(62, ["#c58b50", "#b87a48", "#945e42", "#eed089"], "#dbc99c", "#758a64"),
    }


def facade(native, layout, origin, size, outline):
    image = native.patch(layout, *origin, *size)
    mask = Image.new("L", image.size)
    ImageDraw.Draw(mask).polygon(outline, fill=255)
    image.putalpha(mask)
    return image.crop(mask.getbbox())


def city_fronts(native):
    mall = facade(
        native,
        "LilycoveCity",
        (19, 17),
        (9, 9),
        [(24, 24), (120, 24), (127, 30), (127, 117), (119, 127), (24, 127), (16, 119), (16, 32)],
    )
    bakery = facade(
        native,
        "SlateportCity",
        (24, 7),
        (9, 7),
        [(23, 1), (121, 1), (127, 6), (127, 95), (16, 95), (16, 8)],
    )
    # A scalloped awning and a hanging malasada sign distinguish the counter from the harbor.
    d = ImageDraw.Draw(bakery)
    for x in range(4, bakery.width - 4, 8):
        c = ("#df7662", "#ffdfae")[(x // 8) % 2]
        d.rectangle((x, 53, x + 7, 61), fill=c)
        d.pieslice((x, 58, x + 7, 65), 0, 180, fill=c)
    d.rectangle((7, 65, 9, 75), fill="#514b43")
    d.rounded_rectangle((3, 71, 24, 83), radius=3, fill="#744e43", outline="#524849")
    d.ellipse((8, 73, 18, 81), fill="#efb76c", outline="#a96945")
    d.ellipse((11, 75, 15, 78), fill="#945e45")
    bureau = facade(
        native,
        "SlateportCity",
        (2, 21),
        (6, 6),
        [(2, 29), (11, 25), (62, 25), (79, 32), (79, 89), (72, 95), (8, 95), (0, 88), (0, 33)],
    )
    # Slateport's covered market has open sides, tubs, baskets and separate shadows.
    paving = native.patch("SlateportCity", 8, 44, 1, 1)
    market = cut_background(native.patch("SlateportCity", 2, 41, 5, 3), [paving])
    crates = cut_background(native.patch("SlateportCity", 3, 34, 4, 4), [paving])
    return {
        "shopping_arcade": mall,
        "malasada_shop": bakery,
        "tourism_bureau": bureau,
        "market_canopy": market,
        "market_goods": crates,
    }


def main(source):
    OUT.mkdir(parents=True, exist_ok=True)
    art = frame_art()
    native = Emerald(source)
    art.update(city_fronts(native))
    # Paving, small bridges, and reef terraces use their actual Emerald source palettes.
    for key, layout, coordinate in [
        ("cobbles", "SlateportCity", (15, 14)),
        ("quay", "SlateportCity", (25, 40)),
        ("volcanic", "JaggedPass", (10, 7)),
    ]:
        x, y = coordinate
        art[key] = native.patch(layout, x, y, 1, 1)
    art["volcanic"] = ImageOps.colorize(art["volcanic"].convert("L"), "#302b39", "#ab9b91")
    for key, image in art.items():
        image.save(OUT / (key + ".png"), optimize=True)


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("emerald", type=Path)
    main(p.parse_args().emerald)
