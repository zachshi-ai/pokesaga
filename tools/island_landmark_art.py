"""Pixel furniture, architecture and geological features for the Alola and expedition fields."""

from functools import lru_cache
from math import cos, pi, sin
from pathlib import Path

from PIL import Image, ImageDraw

ART = Path(__file__).resolve().parents[1] / "assets/island_landmarks"
INK = "#424554"


def prism(d, points, top, side, depth):
    d.polygon([(x, y + depth) for x, y in points], fill=side, outline=INK)
    d.polygon(points, fill=top, outline=INK)


@lru_cache(None)
def make(key):
    im = Image.new("RGBA", (80, 80))
    d = ImageDraw.Draw(im)

    def line(points, color, width=1):
        d.line(points, fill=color, width=width)

    def box(rect, color, edge=INK):
        d.rectangle(rect, fill=color, outline=edge)

    def poly(points, color):
        d.polygon(points, fill=color, outline=INK)

    def ellipse(rect, color, edge=INK):
        d.ellipse(rect, fill=color, outline=edge)

    def pillar(x, y, h, stone="#bda980"):
        box((x - 3, y - h, x + 3, y), stone)
        line((x - 1, y - h + 1, x - 1, y - 2), "#eadfba")
        box((x - 5, y - 2, x + 5, y + 1), stone)

    if key in {"gate", "festival_gate"}:
        for x in (13, 66):
            box((x - 3, 22, x + 3, 73), "#a64739")
            box((x - 4, 66, x + 4, 74), "#635249")
            line((x - 1, 25, x - 1, 65), "#e48e61", 2)
        poly([(4, 15), (17, 19), (62, 19), (76, 15), (69, 24), (12, 24)], "#51454a")
        box((10, 25, 70, 29), "#be5946")
        box((12, 35, 67, 39), "#a84836")
        if key == "festival_gate":
            for x in (23, 40, 57):
                line((x, 29, x, 35), "#493e43")
                ellipse((x - 4, 35, x + 4, 45), "#f2b974")
                box((x - 2, 45, x + 2, 47), "#994e42")
    elif key == "windmill":
        poly([(32, 70), (38, 18), (44, 18), (50, 70)], "#b09475")
        for y in range(30, 65, 8):
            line((37, y, 46, y + 7), "#6e5f59")
            line((46, y, 36, y + 7), "#6e5f59")
        for j in range(10):
            a = j * pi / 5

            def pt(rad, angle):
                return (40 + round(cos(angle) * rad), 23 + round(sin(angle) * rad))

            poly([pt(6, a), pt(22, a), pt(22, a + 0.30), pt(8, a + 0.29)], "#ccc7a8")
        ellipse((37, 20, 43, 26), "#705f53")
    elif key in {"boat", "canoe"}:
        poly(
            [
                (3, 49),
                (17, 53),
                (69, 51),
                (78, 45),
                (70, 60),
                (58, 65),
                (17, 65),
                (6, 58),
            ],
            "#986948",
        )
        line((9, 55, 62, 58, 73, 53), "#eac88d", 2)
        if key == "boat":
            box((22, 37, 62, 51), "#e3cf9b")
            poly([(16, 38), (24, 29), (58, 28), (68, 37)], "#738f85")
            for x in (25, 35, 50):
                box((x, 40, x + 6, 46), "#6c9298")
        else:
            line((39, 52, 38, 11), "#8e7557", 3)
            poly([(36, 12), (12, 42), (36, 40)], "#e2cba1")
            poly([(42, 17), (59, 41), (42, 40)], "#ca7964")
    elif key in {"crystals", "amethyst", "vent", "ice_shard"}:
        colors = {
            "crystals": ("#507b8e", "#8ed2cc", "#dcf2d9"),
            "amethyst": ("#725b80", "#ba90be", "#edcee8"),
            "ice_shard": ("#638da0", "#a5dae5", "#e6f7ec"),
            "vent": ("#935e53", "#d39269", "#fac48e"),
        }[key]
        for x, y, h, w in (
            (26, 60, 26, 9),
            (49, 59, 33, 9),
            (36, 63, 45, 12),
            (58, 63, 17, 7),
        ):
            poly(
                [
                    (x - w, y - 4),
                    (x - w + 2, y - h + 7),
                    (x, y - h),
                    (x + w, y - h + 10),
                    (x + w - 2, y),
                ],
                colors[1],
            )
            d.polygon(
                [
                    (x, y - h + 2),
                    (x + w - 1, y - h + 11),
                    (x + w - 3, y - 1),
                    (x + 1, y - 3),
                ],
                fill=colors[0],
            )
            line((x - w + 2, y - h + 8, x - 1, y - h + 2, x + 1, y - 3), colors[2])
    elif key in {"ruin_idol", "moai", "braziers", "memorial", "stone_arch", "ice_arch"}:
        stone = "#a99982" if key != "ice_arch" else "#a6cdda"
        if "arch" in key:
            for i, (x, y) in enumerate(
                [
                    (10, 64),
                    (10, 53),
                    (14, 43),
                    (20, 34),
                    (29, 29),
                    (40, 26),
                    (51, 29),
                    (60, 34),
                    (66, 43),
                    (69, 53),
                    (69, 64),
                ]
            ):
                box((x - 6, y - 5, x + 6, y + 5), stone)
                line((x - 5, y - 4, x + 4, y - 4), "#e1d9bc")
        elif key == "braziers":
            pillar(39, 68, 19)
            poly([(25, 44), (54, 44), (48, 53), (32, 53)], "#947456")
            poly(
                [
                    (30, 42),
                    (29, 34),
                    (36, 37),
                    (38, 22),
                    (43, 28),
                    (44, 18),
                    (51, 34),
                    (47, 42),
                ],
                "#cf7b47",
            )
            poly([(35, 43), (39, 34), (41, 39), (45, 31), (45, 43)], "#ffda81")
        else:
            box((22, 63, 58, 68), stone)
            box((26, 59, 54, 63), "#bfae8f")
            if key == "memorial":
                poly(
                    [(31, 58), (31, 38), (34, 34), (46, 34), (49, 38), (49, 58)], stone
                )
                for y in (42, 46, 50):
                    line((35, y, 45, y), "#817b75")
            else:
                poly(
                    [
                        (29, 58),
                        (27, 43),
                        (23, 36),
                        (25, 21),
                        (35, 18),
                        (41, 12),
                        (47, 20),
                        (55, 22),
                        (57, 37),
                        (52, 44),
                        (51, 58),
                    ],
                    stone,
                )
                for x in (30, 45):
                    box((x, 30, x + 4, 33), "#5d6863")
                line((40, 31, 36, 40, 43, 40), "#746e66", 2)
                line((33, 48, 40, 46, 48, 49), "#817768", 2)
    elif key in {"dish", "telescope"}:
        pillar(39, 68, 23, "#a5aeb0")
        if key == "dish":
            poly(
                [(12, 18), (22, 40), (36, 48), (46, 46), (55, 35), (61, 21)], "#b4c6ca"
            )
            line((14, 20, 36, 32, 59, 22), "#e2eeea", 3)
            line((37, 34, 43, 15, 52, 23), "#708b96", 2)
            ellipse((40, 12, 45, 17), "#c89767")
        else:
            poly([(14, 23), (21, 13), (58, 34), (52, 43)], "#7396ad")
            poly([(11, 20), (17, 10), (26, 14), (19, 27)], "#b5cbd1")
            line((39, 43, 26, 68, 39, 48, 55, 68), "#847e76", 3)
    elif key in {"coil", "reactor", "capsule"}:
        prism(d, [(22, 64), (36, 58), (56, 62), (42, 70)], "#a6afa9", "#6d878b", 3)
        box((30, 28, 50, 62), "#7fabb0")
        ellipse((29, 22, 51, 33), "#d4e0cd")
        if key == "coil":
            for y in range(29, 58, 6):
                ellipse((24, y, 56, y + 6), "#83ad9e")
            pillar(40, 26, 14, "#cdb78a")
        else:
            box((33, 32, 47, 56), "#5d8e9c")
            line((35, 35, 35, 52), "#c0e3db", 2)
            if key == "capsule":
                ellipse((37, 39, 44, 49), "#b4b77d")
            else:
                line((34, 48, 38, 42, 40, 51, 46, 37), "#a8dcc2", 2)
    elif key in {"reef", "lilies", "jelly", "coral", "mangrove", "bamboo", "cactus"}:
        if key in {"bamboo", "mangrove", "cactus"}:
            for x, y, h in [(23, 62, 30), (33, 67, 48), (46, 64, 37), (55, 63, 23)]:
                if key == "mangrove":
                    for dx in (-9, 8):
                        line((x, y - 18, x + dx, y), "#80674d", 3)
                    ellipse((x - 14, y - h - 8, x + 12, y - h + 9), "#567b58")
                else:
                    box((x - 2, y - h, x + 2, y), "#829856")
                    if key == "bamboo":
                        for v in range(y - h + 5, y - 1, 7):
                            line((x - 2, v, x + 2, v), "#536e4e")
                        poly(
                            [(x, y - h + 8), (x + 12, y - h), (x + 8, y - h + 6)],
                            "#91ad66",
                        )
                    else:
                        line((x, y - 12, x - 7, y - 17, x - 7, y - 27), "#69915f", 3)
        elif key == "jelly":
            ellipse((21, 20, 60, 49), "#b893bc")
            ellipse((24, 26, 52, 44), "#d7b8ce")
            for x in (26, 34, 45, 54):
                line((x, 47, x - 3, 55, x + 3, 61, x - 1, 67), "#bda5c8", 2)
        elif key == "lilies":
            for x, y, w in ((24, 54, 10), (42, 61, 9), (54, 48, 8)):
                ellipse((x - w, y - 4, x + w, y + 4), "#8eae72")
            ellipse((34, 49, 44, 54), "#eac4c7")
        else:
            for x, y, h in [(25, 62, 17), (39, 65, 28), (51, 61, 18)]:
                c = "#b97971" if key == "coral" else "#69968a"
                line((x, y, x - 2, y - h), c, 4)
                line((x - 1, y - 6, x - 8, y - 12, x - 8, y - 19), c, 3)
                line((x - 1, y - 10, x + 6, y - 16, x + 5, y - 21), c, 3)
    elif key in {"stall", "tea", "pergola"}:
        for x in (12, 66):
            pillar(x, 65, 32, "#ad8b68")
        poly(
            [(5, 34), (18, 18), (60, 18), (74, 32), (67, 38), (11, 38)],
            "#7a917b" if key != "stall" else "#bf715f",
        )
        for x in range(18, 60, 8):
            line((x, 20, x - 7, 33), "#abb294" if key != "stall" else "#edb088", 2)
        if key == "stall":
            box((14, 48, 65, 60), "#b18660")
            for x in range(21, 60, 7):
                ellipse((x, 43, x + 6, 49), "#b6b670" if x % 2 else "#d99467")
        elif key == "tea":
            box((24, 50, 56, 54), "#8d775d")
            ellipse((39, 46, 47, 50), "#a7b4a1")
    elif key in {"sun_disc", "moon_disc", "clockface", "vortex"}:
        pillar(40, 69, 21, "#9b8c80")
        gold = "#d3a761" if key != "moon_disc" else "#a0b6ce"
        ellipse((19, 15, 61, 57), gold)
        ellipse((23, 19, 57, 53), "#657688")
        if key == "moon_disc":
            ellipse((29, 23, 51, 49), "#d8dfc5")
            ellipse((36, 22, 53, 41), "#657688", "#657688")
        elif key == "vortex":
            for k in range(4):
                d.arc(
                    (25 + k * 2, 21 + k * 2, 55 - k * 2, 52 - k * 2),
                    15 + k * 40,
                    278 + k * 25,
                    fill="#9cd5d2",
                    width=2,
                )
        elif key == "clockface":
            line((40, 23, 40, 35, 48, 37), "#efce99", 2)
        else:
            ellipse((33, 29, 47, 43), gold)
            for i in range(8):
                a = i * pi / 4
                line(
                    (
                        40 + int(cos(a) * 10),
                        36 + int(sin(a) * 10),
                        40 + int(cos(a) * 14),
                        36 + int(sin(a) * 14),
                    ),
                    gold,
                    2,
                )
    elif key in {
        "loom",
        "easel",
        "rack",
        "archive",
        "gongs",
        "ring",
        "bell",
        "millstone",
    }:
        if key == "ring":
            prism(d, [(8, 48), (39, 40), (73, 48), (41, 63)], "#c1bd96", "#847768", 5)
            for x, y in [(10, 48), (40, 41), (71, 48), (41, 62)]:
                pillar(x, y, 11, "#9f675a")
            for v in (6, 10):
                line(
                    (10, 48 - v, 40, 41 - v, 71, 48 - v, 41, 62 - v, 10, 48 - v),
                    "#ccb894",
                    2,
                )
        elif key in {"easel", "loom"}:
            line((25, 68, 39, 24, 55, 67), "#907351", 3)
            box((25, 28, 54, 52), "#e1cf9e")
            for i, c in enumerate(["#789c93", "#ab787c", "#d8ab6e"]):
                poly([(27, 48 - i * 3), (37 + i * 2, 36 - i * 2), (51, 49 - i)], c)
        elif key in {"bell", "gongs", "millstone"}:
            if key != "millstone":
                for x in (20, 60):
                    pillar(x, 68, 45, "#98795c")
                box((16, 22, 64, 26), "#8f735a")
                line((40, 27, 40, 31), "#6b6861", 2)
            ellipse((24, 31, 55, 59), "#b59c73" if key != "millstone" else "#a6a39a")
            ellipse((35, 41, 45, 50), "#817b6b")
        else:
            box((16, 32, 62, 65), "#9b8168")
            for yy in (37, 49):
                for i, x in enumerate(range(19, 59, 7)):
                    box(
                        (x, yy, x + 4, yy + 8), ["#aa7b70", "#849b91", "#c6ad79"][i % 3]
                    )
                box((17, yy + 8, 61, yy + 10), "#bca488")
    elif key in {"library_front", "gem_front", "salon_front", "visitor_front"}:
        palette = {
            "library_front": ("#557377", "#88aaa2"),
            "gem_front": ("#87718c", "#c5a0b2"),
            "salon_front": ("#947050", "#c6a477"),
            "visitor_front": ("#7086a0", "#a8bfbe"),
        }
        roof, lit = palette[key]
        box((11, 36, 69, 70), "#caba96")
        box((13, 40, 67, 65), "#e2cfaa")
        for px in (13, 27, 51, 66):
            box((px, 38, px + 2, 67), "#796a5c")
        poly([(5, 37), (16, 20), (59, 20), (74, 36), (69, 40), (11, 40)], roof)
        for yy in (25, 29, 33):
            line((17 - (yy - 25) // 2, yy, 60 + (yy - 25) // 2, yy), lit)
        for xx in range(20, 62, 7):
            line((xx, 22, xx - 4, 36), roof, 2)
        if key == "library_front":
            poly([(5, 32), (18, 35), (60, 35), (75, 32), (68, 39), (12, 39)], "#5e7174")
            box((29, 37, 49, 42), "#8b684e")
        source = ART.parents[1] / "assets/emerald/field"
        door = Image.open(source / "home.png").convert("RGBA").crop((47, 59, 64, 80))
        im.alpha_composite(door, (32, 49))
        window = (
            Image.open(source / "home_red.png").convert("RGBA").crop((32, 41, 47, 54))
        )
        im.alpha_composite(window, (15, 48))
        im.alpha_composite(window, (51, 48))
        if key == "gem_front":
            poly([(35, 42), (40, 38), (45, 42), (40, 47)], "#97c8b7")
        elif key == "library_front":
            for xx in (34, 40):
                box((xx, 40, xx + 5, 45), "#d7c9a9")
        else:
            line((29, 44, 51, 44), lit, 2)
        box((11, 68, 30, 70), "#968876")
        box((50, 68, 69, 70), "#968876")
    elif key in {
        "cargo",
        "crate",
        "barrel",
        "trough",
        "fence",
        "broken_sign",
        "camper",
        "beach_umbrella",
        "sea_lantern",
        "camera",
        "ferry",
    }:
        if key in {"crate", "cargo"}:
            for x, y in (
                [(12, 51), (34, 55), (28, 38)]
                if key == "cargo"
                else [(24, 52), (45, 57)]
            ):
                box((x, y - 8, x + 19, y + 10), "#b88f64")
                line((x + 1, y - 5, x + 17, y + 8), "#83654f", 2)
                line((x + 3, y + 8, x + 17, y - 5), "#d4b587", 2)
                line((x, y - 7, x + 19, y - 7), "#e4c49a")
        elif key == "barrel":
            for x, y in [(19, 59), (40, 65)]:
                box((x, y - 18, x + 16, y), "#a27c59")
                ellipse((x, y - 21, x + 16, y - 15), "#c49c6a")
                for yy in (y - 12, y - 4):
                    line((x, yy, x + 16, yy), "#736f63", 2)
        elif key == "trough":
            prism(d, [(9, 52), (16, 45), (68, 45), (62, 54)], "#b79b6d", "#8b735a", 9)
            poly([(14, 51), (18, 47), (63, 47), (60, 51)], "#87afac")
        elif key == "fence":
            for y in (45, 54):
                box((5, y, 73, y + 3), "#ba976e")
            for x in (10, 38, 67):
                box((x, 40, x + 4, 62), "#9e815e")
        elif key == "broken_sign":
            line((40, 66, 36, 32), "#826f5d", 5)
            poly([(16, 35), (56, 26), (61, 42), (19, 52)], "#aa9382")
            line((22, 40, 35, 37, 32, 44, 49, 39), "#726577", 2)
        elif key == "camper":
            box((12, 33, 67, 58), "#d1b580")
            box((16, 38, 31, 46), "#86a8ac")
            box((46, 36, 59, 56), "#c2a572")
            box((48, 39, 57, 46), "#7f9e9f")
            for x in (22, 52):
                ellipse((x, 54, x + 8, 62), "#605e59")
            line((13, 49, 44, 49), "#9c6e59", 3)
        elif key == "beach_umbrella":
            pillar(40, 68, 31, "#a89577")
            poly(
                [
                    (13, 38),
                    (23, 27),
                    (40, 20),
                    (60, 28),
                    (68, 39),
                    (57, 42),
                    (44, 38),
                    (31, 42),
                    (20, 40),
                ],
                "#d38270",
            )
            poly([(24, 38), (40, 21), (37, 38), (31, 42)], "#eacb94")
            poly([(44, 37), (40, 21), (58, 39), (55, 41)], "#eacb94")
        elif key == "sea_lantern":
            pillar(40, 68, 35, "#827f75")
            box((34, 26, 45, 38), "#f0ce93")
            poly([(31, 27), (40, 18), (49, 27)], "#6f8585")
        elif key == "camera":
            line((38, 42, 24, 67, 38, 48, 48, 68), "#746a67", 3)
            box((25, 27, 54, 43), "#738c94")
            ellipse((39, 28, 52, 41), "#a6c3c0")
        else:
            return make("boat")
    else:
        raise KeyError(key)
    bounds = im.getbbox()
    return im.crop(bounds)


def export(keys):
    ART.mkdir(exist_ok=True)
    for key in sorted(keys):
        make(key).save(ART / (key + ".png"), optimize=True)
