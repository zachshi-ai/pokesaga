"""Pixel landmarks aligned to the playable doors and investigation sites in Galar."""

from pathlib import Path
import json
from random import Random

from PIL import Image, ImageDraw
from galar_expansion_ground import repaint

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "assets/galar/landmarks"
INK = "#42434d"
WOOD = "#704c43"
TIMBER = "#a37758"
CREAM = "#ecdbb4"


def canvas(w, h):
    image = Image.new("RGBA", (w, h))
    return image, ImageDraw.Draw(image)


def masonry(d, box, colors, unit=9):
    l, t, r, b = box
    d.rectangle(box, fill=colors[0])
    for row, y in enumerate(range(t, b, 5)):
        for i, x in enumerate(range(l - (row % 2) * unit // 2, r, unit)):
            left, right = max(l, x), min(r, x + unit - 2)
            if right < left:
                continue
            base = colors[1 + (i + row * 3) % 3]
            d.rectangle((left, y, right, min(b, y + 3)), fill=base)
            if right - left > 2:
                d.line((left + 1, y, right - 1, y), fill=colors[-1])


def grating(d, box, paint=TIMBER):
    l, t, r, b = box
    d.rectangle(box, fill="#544749", outline=INK)
    for x in range(l + 2, r, 3):
        d.line((x, t + 1, x, b - 1), fill=paint)
    for y in range(t + 3, b, 4):
        d.line((l + 1, y, r - 1, y), fill=paint)


def roof(d, x, y, width, height, palette):
    lo = x - width // 2
    hi = x + width // 2
    shade, base, light = palette
    p = [
        (lo, y + height - 3),
        (lo + 4, y + height - 3),
        (lo + 14, y),
        (hi - 14, y),
        (hi - 5, y + height - 3),
        (hi, y + height - 3),
        (hi, y + height),
        (lo, y + height),
    ]
    d.polygon(p, fill=base, outline=INK)
    for k in range(lo + 15, hi - 13, 5):
        dx = (k - x) // 7
        d.line((k, y + 2, k + dx, y + height - 4), fill=shade)
        d.line((k + 1, y + 2, k + dx + 1, y + height - 4), fill=light)
    d.line((lo + 1, y + height - 2, hi - 1, y + height - 2), fill=light)
    d.line((lo + 4, y + height + 1, hi - 4, y + height + 1), fill=shade)


def dojo():
    im, d = canvas(110, 73)
    masonry(
        d, (8, 59, 102, 70), ["#51555b", "#828085", "#949199", "#706e75", "#b7b0aa"]
    )
    d.rectangle((9, 30, 101, 60), fill=WOOD, outline=INK)
    d.rectangle((12, 31, 98, 52), fill="#d6bd8d")
    for x in (14, 33, 72, 93):
        d.rectangle((x, 32, x + 3, 60), fill=TIMBER, outline=WOOD)
    for x in (20, 78):
        grating(d, (x, 36, x + 12, 50), "#ceb993")
    for y in (55, 59):
        d.line((10, y, 100, y), fill="#c39871")
    roof(d, 55, 8, 108, 22, ("#715344", "#a57954", "#cfac75"))
    d.rectangle((17, 6, 93, 9), fill=WOOD, outline=INK)
    d.line((18, 6, 91, 6), fill="#d0ab77")
    for x in (40, 67):
        d.rectangle((x, 39, x + 3, 66), fill="#ac7e57", outline=WOOD)
    d.rectangle((45, 44, 66, 65), fill=INK)
    grating(d, (45, 45, 50, 63), "#b58a64")
    grating(d, (61, 45, 66, 63), "#b58a64")
    roof(d, 55, 24, 43, 12, ("#80623f", "#bb944f", "#e1c270"))
    d.rectangle((44, 34, 66, 41), fill="#65483d", outline="#c8a463")
    for x in (48, 52, 56, 60):
        d.line([(x, 38), (x + 2, 36), (x + 1, 39)], fill="#f0d799")
    for y, color in [(64, "#b1aaa0"), (67, "#d6c6ac"), (70, "#b0ac9e")]:
        d.rectangle(
            (43 - (y - 64) // 3, y, 67 + (y - 64) // 3, y + 2),
            fill=color,
            outline="#797472",
        )
    return im


def tower(water):
    im, d = canvas(78, 107)
    tile = (
        ("#34475b", "#456c83", "#759ba5")
        if water
        else ("#553e44", "#87504a", "#ab7162")
    )
    cloth = "#3e7196" if water else "#a04443"
    bright = "#92c6ce" if water else "#e78969"
    masonry(
        d, (12, 97, 66, 103), ["#55525a", "#928a83", "#77737a", "#aba397", "#cdc0a7"]
    )
    for level in range(5):
        y = 84 - level * 17
        left, right = 19 + level, 60 - level
        d.rectangle((left, y - 2, right, y + 14), fill=WOOD, outline=INK)
        d.rectangle((left + 3, y + 2, right - 3, y + 10), fill="#c5ad90")
        if level:
            grating(d, (left + 8, y + 3, right - 8, y + 9))
        else:
            d.rectangle((32, y + 1, 46, y + 15), fill=INK, outline="#ac886b")
            d.rectangle((35, y + 3, 42, y + 14), fill="#423e44")
        for x in (left + 1, right - 4):
            d.rectangle((x, y, x + 3, y + 13), fill=TIMBER, outline=WOOD)
            d.point((x + 1, y + 3), fill=CREAM)
        d.rectangle((left - 4, y + 11, right + 4, y + 13), fill=tile[0], outline=INK)
        d.line((left - 3, y + 11, right + 3, y + 11), fill=tile[2])
        roof(d, 39, y - 6, right - left + 15, 6, tile)
    d.rectangle((32, 8, 46, 16), fill="#bd9563", outline=WOOD)
    d.ellipse((35, 9, 43, 15), fill="#e8d19b", outline="#8d7158")
    d.line((28, 6, 50, 6), fill=INK, width=2)
    d.line((29, 5, 49, 5), fill=tile[2])
    d.line((33, 3, 45, 3), fill=INK, width=2)
    for side in (-1, 1):
        x = 39 + side * 26
        d.polygon(
            [(x, 16), (x + side * 4, 18), (x + side * 11, 76), (x + side * 7, 83)],
            fill=cloth,
            outline=tile[0],
        )
        d.line((x + side, 19, x + side * 8, 71), fill=bright)
    for i in range(3):
        d.rectangle(
            (29 - i, 98 + i * 2, 49 + i, 99 + i * 2), fill=("#ddd0b6", "#a69d93")[i % 2]
        )
    return im


def lair():
    im, d = canvas(101, 55)
    outline = [
        (2, 49),
        (8, 34),
        (17, 28),
        (23, 17),
        (37, 17),
        (43, 8),
        (59, 6),
        (68, 12),
        (80, 11),
        (93, 25),
        (99, 45),
        (94, 51),
        (70, 53),
        (21, 52),
    ]
    d.polygon(outline, fill="#67798a", outline="#465969")
    for pts, c in [
        ([(4, 45), (15, 30), (26, 27), (27, 36), (16, 49)], "#8797a1"),
        (
            [(17, 28), (24, 18), (37, 18), (43, 9), (55, 8), (46, 24), (36, 34)],
            "#aebfc5",
        ),
        (
            [(51, 10), (59, 7), (68, 13), (78, 12), (91, 24), (72, 33), (64, 25)],
            "#92a7b2",
        ),
        ([(70, 32), (91, 25), (97, 44), (84, 49)], "#788d9d"),
    ]:
        d.polygon(pts, fill=c)
    d.polygon(
        [
            (27, 51),
            (30, 37),
            (36, 28),
            (48, 22),
            (58, 22),
            (67, 28),
            (74, 41),
            (74, 50),
        ],
        fill="#4f6172",
        outline="#d5e1de",
    )
    d.polygon(
        [
            (33, 50),
            (36, 38),
            (42, 31),
            (49, 27),
            (57, 27),
            (65, 32),
            (69, 44),
            (69, 50),
        ],
        fill="#313d51",
    )
    d.polygon([(39, 48), (43, 39), (50, 35), (59, 37), (63, 49)], fill="#252e40")
    for a in [
        [
            (7, 34),
            (19, 25),
            (23, 17),
            (36, 16),
            (42, 7),
            (57, 4),
            (62, 6),
            (56, 12),
            (45, 12),
            (40, 19),
            (29, 20),
            (23, 27),
            (14, 30),
        ],
        [(63, 14), (70, 11), (80, 10), (86, 16), (77, 15), (72, 18), (67, 17)],
        [(14, 45), (23, 41), (30, 40), (29, 44), (19, 47)],
    ]:
        d.polygon(a, fill="#e3ece4", outline="#afc6cd")
    for x in (21, 78):
        d.rectangle((x, 38, x + 2, 49), fill=WOOD)
        d.rectangle((x - 2, 35, x + 4, 41), fill="#5d646d", outline=INK)
        d.rectangle((x, 36, x + 2, 39), fill="#edc26e")
    for y in range(46, 53, 3):
        d.line((35 + (52 - y), y, 66 - (52 - y), y), fill="#9a9995")
    return im


def sanctuary():
    """Snow-laden stone chapel and the great tree above its rear wall."""
    im, d = canvas(141, 98)
    leaves = ["#465b5c", "#58736e", "#77908a", "#9caea1", "#d0dcd1"]
    rng = Random(27)
    d.polygon(
        [
            (62, 67),
            (63, 44),
            (51, 32),
            (56, 28),
            (68, 40),
            (77, 19),
            (80, 23),
            (74, 40),
            (86, 31),
            (89, 34),
            (76, 49),
            (77, 67),
        ],
        fill="#786954",
        outline=WOOD,
    )
    for x, y, r in [
        (43, 29, 14),
        (53, 18, 16),
        (69, 15, 14),
        (83, 18, 16),
        (98, 26, 14),
        (80, 31, 17),
        (58, 32, 17),
    ]:
        d.ellipse((x - r, y - r + 3, x + r, y + r), fill=leaves[0])
        d.ellipse((x - r, y - r, x + r - 2, y + r - 4), fill=leaves[1])
        for _ in range(19):
            a, b = rng.randint(-r + 2, r - 2), rng.randint(-r + 2, r - 3)
            if a * a + b * b < (r - 1) ** 2:
                d.line(
                    (x + a, y + b, x + a + 3, y + b),
                    fill=leaves[2 + (rng.randrange(4) == 0)],
                )
        d.line((x - r + 4, y - r + 4, x - 2, y - r + 2), fill=leaves[4], width=2)
    colors = ["#666d73", "#87918f", "#939c96", "#798780", "#b5bdb0"]
    for x, y, height in [(9, 55, 26), (28, 53, 19), (96, 54, 19), (119, 51, 28)]:
        masonry(d, (x, y, x + 12, y + height), colors, 8)
        d.rectangle((x - 2, y - 2, x + 14, y + 1), fill="#dce8e2", outline="#a3b4b1")
        d.rectangle(
            (x - 2, y + height, x + 14, y + height + 3),
            fill="#abb7ab",
            outline="#717d79",
        )
    # Hollow pointed windows keep a view through to the tree.
    for x in (34, 79):
        masonry(d, (x, 48, x + 26, 74), colors)
        d.polygon(
            [(x + 6, 74), (x + 6, 61), (x + 13, 54), (x + 20, 61), (x + 20, 74)],
            fill=(0, 0, 0, 0),
        )
        d.line(
            [(x + 5, 71), (x + 5, 61), (x + 13, 52), (x + 21, 61), (x + 21, 71)],
            fill="#cbd2bc",
            width=2,
        )
        d.polygon(
            [
                (x - 1, 49),
                (x + 10, 38),
                (x + 14, 39),
                (x + 22, 45),
                (x + 27, 43),
                (x + 27, 50),
            ],
            fill="#8a938f",
            outline="#697877",
        )
        d.line(
            [(x, 48), (x + 11, 38), (x + 14, 39), (x + 21, 44)], fill="#e6eade", width=3
        )
    masonry(d, (12, 77, 41, 85), colors)
    masonry(d, (101, 74, 130, 83), colors)
    d.line((12, 76, 41, 76), fill="#e1e8dc", width=2)
    d.line((101, 73, 130, 73), fill="#d5e4dc", width=2)
    for x, y in ((8, 88), (21, 90), (115, 88), (126, 85)):
        d.polygon(
            [(x, y + 3), (x + 2, y), (x + 8, y), (x + 10, y + 3), (x + 7, y + 5)],
            fill="#a4b2a9",
            outline="#75837e",
        )
    return im


def shrine_column():
    im, d = canvas(20, 38)
    colors = ["#697572", "#a1aaa0", "#b4baad", "#9ba69c", "#c2cabe"]
    masonry(d, (4, 9, 15, 31), colors, 6)
    d.rectangle((3, 7, 16, 11), fill="#a3afa5", outline="#788780")
    d.polygon(
        [(2, 8), (2, 4), (6, 3), (9, 1), (11, 3), (15, 2), (18, 5), (17, 8)],
        fill="#dce5d9",
        outline="#a4b4aa",
    )
    d.line((7, 14, 7, 28), fill="#c9d0bf")
    for box in ((2, 30, 17, 33), (1, 34, 18, 36)):
        d.rectangle(box, fill="#b3bcae", outline="#7e8a82")
    return im


def install(name, art, mid, x, y, replace, extra_walls=(), clear=()):
    art.save(ART / (name + ".png"), optimize=True)
    region = mid.split("_")[0]
    path = ROOT / "content/regions" / region / "maps" / (mid + ".json")
    m = json.loads(path.read_bytes())
    key = "res://assets/galar/landmarks/" + name + ".png"
    props = m["hoenn_art"]["p"]
    props[:] = [p for p in props if p[0] != key and (p[1], p[2]) not in replace]
    props.append([key, x, y, [art.width // 2, art.height]])
    for xx, yy in clear:
        m["tiles"][yy][xx] = 0
    for xx, yy in extra_walls:
        m["tiles"][yy][xx] = 1
    if mid in {"armor_towers", "armor_water_tower", "crown_peak", "crown_slope"}:
        repaint(mid, m, ROOT / m["hoenn_art"]["scene"][0].removeprefix("res://"))
    path.write_text(json.dumps(m, ensure_ascii=False, separators=(",", ":")) + "\n")


def build():
    ART.mkdir(parents=True, exist_ok=True)
    install("master_dojo", dojo(), "armor_fields", 27, 11, {(27, 11)})
    # The old idol and gate hung above empty up-arrow triggers. The doors, collision
    # and foot of the staircase now share one coordinate in both approaches.
    install(
        "tower_dark",
        tower(False),
        "armor_towers",
        12,
        9,
        {(14, 7), (11, 7)},
        [(x, y) for x in range(10, 15) for y in range(7, 10)],
        [(14, 6), (11, 6), (12, 10), (12, 11)],
    )
    install(
        "tower_water",
        tower(True),
        "armor_water_tower",
        18,
        7,
        {(18, 7), (20, 4)},
        [(x, y) for x in range(16, 21) for y in range(5, 8)],
    )
    install(
        "crown_shrine",
        sanctuary(),
        "crown_peak",
        16,
        8,
        {(16, 11), (19, 8)},
        [(x, 7) for x in (13, 14, 15, 17, 18, 19)] + [(13, 12), (19, 12)],
        [(x, 11) for x in range(14, 19)] + [(19, 8)],
    )
    pillar = shrine_column()
    pillar.save(ART / "shrine_column.png", optimize=True)
    path = ROOT / "content/regions/crown/maps/crown_peak.json"
    m = json.loads(path.read_bytes())
    key = "res://assets/galar/landmarks/shrine_column.png"
    props = m["hoenn_art"]["p"]
    props[:] = [p for p in props if p[0] != key]
    for x in (13, 19):
        props.append([key, x, 12, [10, 38]])
    path.write_text(json.dumps(m, ensure_ascii=False, separators=(",", ":")) + "\n")
    from galar_crown_station import build as build_station

    build_station(lair())
