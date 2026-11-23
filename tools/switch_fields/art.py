"""Sixteen-pixel field sprites for the three Switch-to-GBA atlases."""

from functools import lru_cache
from pathlib import Path
import math
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/switch_fields/props"
FIELD = ROOT / "assets/emerald/field"

# building key: public room name, architectural silhouette and colour family
BUILDINGS = {
    "lakeside": ("宝可梦博士的家", "gable", "ivory"),
    "barn": ("谷仓", "gable", "ochre"),
    "nursery": ("寄放屋", "gable", "rose"),
    "fairy": ("剧场大厅", "theatre", "lilac"),
    "cottage": ("居民家", "gable", "umber"),
    "hotel": ("爱奥尼亚酒店", "hotel", "ice"),
    "castle": ("拳关城堡", "castle", "umber"),
    "station": ("车站候车厅", "station", "teal"),
    "lighthouse": ("灯塔值班室", "beacon", "ivory"),
    "fishmarket": ("鱼市", "market", "teal"),
    "works": ("蒸汽工场", "factory", "brick"),
    "club": ("演出场地", "theatre", "slate"),
    "shutter": ("街角商店", "shop", "slate"),
    "bazaar": ("古物市场", "market", "ochre"),
    "pitch": ("草路竞技场门厅", "stadium", "teal"),
    "lab": ("研究所", "gable", "brick"),
    "lodgings": ("村民宿舍", "rowhouse", "umber"),
    "craft": ("工艺店", "shop", "umber"),
    "kiln": ("制陶工坊", "factory", "terracotta"),
    "housewhite": ("街边民居", "gable", "terracotta"),
    "windmill": ("风车磨坊", "mill", "ivory"),
    "studio": ("艺术工坊", "gable", "lilac"),
    "family": ("主角家", "gable", "terracotta"),
    "manor": ("妮莫家", "manor", "ivory"),
    "waterworks": ("水渠管理室", "aqueduct", "teal"),
    "bakery": ("烘焙工坊", "shop", "ochre"),
    "gatehouse": ("闸口值班室", "lab", "slate"),
    "leaguehall": ("联盟大厅", "hall", "ice"),
    "neon": ("海岸演播室", "tower", "lilac"),
    "piercafe": ("海边咖啡馆", "shop", "teal"),
    "market": ("拍卖市场", "market", "terracotta"),
    "eatery": ("宝食堂", "shop", "umber"),
    "terrace": ("露台民居", "rowhouse", "rose"),
    "books": ("书店", "shop", "umber"),
    "cafe": ("街角咖啡馆", "shop", "terracotta"),
    "lodge": ("山中小屋", "gable", "ice"),
    "concert": ("演出准备室", "shop", "lilac"),
    "workshop": ("采石工坊", "factory", "ochre"),
    "stationzero": ("观测站", "lab", "ice"),
    "galaxy": ("银河队总部", "galaxy", "teal"),
    "stadiumgate": ("宫门竞技场", "stadium", "brick"),
    "rosehead": ("洛兹大厦", "tower", "teal"),
    "uva": ("葡萄学院", "academy", "lilac"),
    "leaguegate": ("联盟入口", "hall", "ice"),
    "zerolab": ("第零区研究所", "lab", "slate"),
}
PALETTES = {
    "ivory": ("#6c645b", "#ad9f87", "#eedeb6", "#b3a186", "#d27955", "#985846"),
    "umber": ("#53454b", "#95765c", "#d5b78f", "#a48b70", "#716869", "#4f515c"),
    "ochre": ("#655342", "#a9824d", "#e7ce8f", "#b59e70", "#ae7d4e", "#8b604b"),
    "rose": ("#674b59", "#a87574", "#efd1b1", "#bb9690", "#ba7a82", "#8d5c70"),
    "lilac": ("#514661", "#9b86a2", "#dfcccf", "#a494b2", "#98739d", "#705b88"),
    "ice": ("#47586c", "#8396a4", "#e3e7da", "#adbcc3", "#889aac", "#627891"),
    "teal": ("#42585c", "#709394", "#d8dac4", "#a6b4a6", "#5a9590", "#47737b"),
    "brick": ("#584447", "#a77164", "#d49b7e", "#a88073", "#99746b", "#735661"),
    "slate": ("#424653", "#737887", "#acafb1", "#8f939e", "#64657c", "#49536c"),
    "terracotta": ("#66514c", "#b28a6d", "#eee0bc", "#bfab91", "#bd7962", "#9c6255"),
}


def bitmap(name):
    return Image.open(FIELD / (name + ".png")).convert("RGBA")


def panel(d, box, edge, mid, light):
    x, y, r, b = box
    d.rectangle(box, fill=mid, outline=edge)
    d.line((x + 1, b - 1, x + 1, y + 1, r - 1, y + 1), fill=light)


def window(d, x, y, w=9, h=11):
    d.rectangle((x, y, x + w, y + h), fill="#565669")
    d.rectangle((x + 1, y + 1, x + w - 1, y + h - 1), fill="#8eb0be")
    d.line((x + 2, y + h - 3, x + w - 3, y + 2), fill="#c5d5cd", width=2)
    d.line((x + w // 2, y + 1, x + w // 2, y + h - 1), fill="#6d7884")
    d.line((x - 1, y + h, x + w + 1, y + h), fill="#a39b8a")


def building(key):
    name, form, palette = BUILDINGS[key]
    ink, mid, wall, shade, roof, edge = PALETTES[palette]
    w, h = {
        "beacon": (42, 80),
        "tower": (66, 92),
        "mill": (76, 83),
        "castle": (102, 78),
        "academy": (115, 81),
        "galaxy": (108, 76),
        "stadium": (103, 65),
        "hotel": (89, 72),
        "manor": (91, 65),
        "factory": (82, 64),
        "aqueduct": (78, 58),
        "hall": (89, 65),
        "theatre": (74, 60),
        "market": (84, 47),
        "station": (79, 58),
        "rowhouse": (76, 53),
        "lab": (69, 53),
        "shop": (62, 48),
    }.get(form, (65, 57))
    im = Image.new("RGBA", (w, h))
    d = ImageDraw.Draw(im)
    cx = w // 2
    b = h - 2
    if form == "beacon":
        d.ellipse((3, h - 9, w - 4, h - 2), fill="#7d826c")
        d.polygon(
            [(9, b - 2), (w - 10, b - 2), (cx + 7, 21), (cx - 7, 21)],
            fill=wall,
            outline=ink,
        )
        for y in [35, 52]:
            d.polygon(
                [(cx - 9, y), (cx + 9, y), (cx + 10, y + 6), (cx - 10, y + 6)],
                fill=roof,
            )
        panel(d, (cx - 11, 14, cx + 11, 23), ink, "#e3c77d", "#f4e4a3")
        d.line((cx, 15, cx, 22), fill=ink)
        d.rectangle((cx - 14, 23, cx + 14, 26), fill=edge, outline=ink)
        d.polygon(
            [(cx - 13, 13), (cx - 4, 5), (cx + 4, 5), (cx + 13, 13)],
            fill=roof,
            outline=ink,
        )
        d.line((cx, 5, cx, 1), fill=ink)
    elif form == "mill":
        d.polygon([(18, b), (56, b), (48, 24), (28, 24)], fill=wall, outline=ink)
        d.polygon([(22, 26), (31, 13), (43, 13), (54, 26)], fill=roof, outline=ink)
        for y in [37, 53]:
            window(d, cx - 3, y, 6, 6)
        for dx, dy in [(1, -1), (1, 1), (-1, 1), (-1, -1)]:
            px, py = cx - 1, 31
            d.line((px, py, px + dx * 24, py + dy * 24), fill=ink, width=2)
            pts = [
                (px + dx * t - dy * s, py + dy * t + dx * s)
                for t, s in [(5, 0), (22, 0), (22, 4), (5, 4)]
            ]
            d.polygon(pts, fill="#e5d6aa", outline=ink)
            for t in [9, 14, 19]:
                d.line(
                    (
                        px + dx * t,
                        py + dy * t,
                        px + dx * t - dy * 4,
                        py + dy * t + dx * 4,
                    ),
                    fill=mid,
                )
        d.ellipse((cx - 4, 28, cx + 2, 34), fill="#a18867", outline=ink)
    else:
        depth = {
            "tower": 19,
            "castle": 25,
            "academy": 24,
            "galaxy": 24,
            "stadium": 21,
            "factory": 17,
            "market": 24,
        }.get(form, 20)
        top = {
            "castle": 28,
            "tower": 18,
            "factory": 21,
            "academy": 27,
            "galaxy": 29,
            "hotel": 15,
            "stadium": 22,
        }.get(form, 9)
        left = 4
        right = w - 5
        if form == "factory":
            for xx, hh in [(w - 19, 3), (w - 30, 8)]:
                panel(d, (xx, hh, xx + 6, top + 10), ink, mid, shade)
                d.rectangle((xx - 1, hh, xx + 7, hh + 3), fill=edge)
                for y in range(hh + 6, top + 7, 5):
                    d.line((xx + 1, y, xx + 5, y), fill=shade)
        panel(d, (left, top + depth - 4, right, b), ink, wall, shade)
        d.rectangle((left + 1, b - 6, right - 1, b - 2), fill=shade)
        for x in range(left + 2, right - 2, 15):
            d.point((x, b - 4), fill=mid)
        ismarket = form == "market"
        d.polygon(
            [(1, top + depth), (left + 6, top), (right - 6, top), (w - 2, top + depth)],
            fill=roof,
            outline=edge,
        )
        for y in range(top + 3, top + depth - 1, 4):
            l = round((top + depth - y) / depth * 7) + 2
            d.line((l, y, w - l - 1, y), fill=mid)
            for x in range(l + ((y // 4) % 2) * 4, w - l, 8):
                d.point((x, y + 1), fill=edge)
        d.line((1, top + depth, w - 2, top + depth), fill=ink, width=2)
        if form in [
            "gable",
            "rowhouse",
            "manor",
            "galaxy",
            "academy",
            "theatre",
            "castle",
        ]:
            for apex in (
                [cx, cx - 29, cx + 29]
                if form in ["academy", "galaxy", "manor"]
                else [cx]
            ):
                y = top - 4 if form not in ["academy", "galaxy", "castle"] else top - 12
                d.polygon(
                    [(apex - 13, top + depth), (apex, y), (apex + 13, top + depth)],
                    fill=wall,
                    outline=ink,
                )
                d.line(
                    (apex - 14, top + depth, apex, y - 1, apex + 14, top + depth),
                    fill=edge,
                    width=3,
                )
                d.line((apex, y + 3, apex, top + depth), fill=mid, width=2)
        if form in ["tower", "hotel", "lab", "aqueduct", "hall", "station", "stadium"]:
            d.rectangle((4, top + 2, w - 5, top + 6), outline=edge, fill=shade)
            if form in ["tower", "stadium", "lab"]:
                d.rectangle(
                    (cx - 13, top - 2, cx + 13, top + 8), fill="#6e929e", outline=ink
                )
                d.line((cx - 10, top + 4, cx + 10, top + 4), fill="#c9dcd1")
        rows = [b - 22] if h - top - depth < 38 else [top + depth + 4, b - 18]
        for wy in rows:
            for x in range(9, w - 12, 15):
                if abs(x + 4 - cx) < 12:
                    continue
                window(d, x, wy, 9, 10)
        if form == "castle":
            for x in (3, w - 21):
                panel(d, (x, 17, x + 16, b - 3), ink, shade, wall)
                d.rectangle((x - 2, 13, x + 18, 22), fill=mid, outline=ink)
                for xx in range(x - 1, x + 17, 6):
                    d.rectangle((xx, 9, xx + 3, 15), fill=mid, outline=ink)
                window(d, x + 6, 29, 4, 9)
                d.line((x + 2, 44, x + 13, 44), fill=mid)
        if form in ("academy", "galaxy", "manor", "station", "hotel"):
            d.rectangle((cx - 7, top - 6, cx + 7, top + 6), fill=shade, outline=ink)
            d.ellipse((cx - 4, top - 4, cx + 4, top + 4), fill="#e6d6a6", outline=mid)
            d.line((cx, top - 3, cx, top, cx + 2, top + 1), fill=ink)
        if form == "stadium":
            for x in [6, w - 11]:
                d.line((x, 3, x, top + 12), fill=ink, width=2)
                d.polygon([(x, 3), (x + 8, 5), (x, 9)], fill="#ca6563")
        if form in ("market", "shop", "theatre", "station"):
            col = "#ead6a4"
            y = b - 18
            for x in range(7, w - 7, 6):
                c = roof if (x - 7) // 6 % 2 else col
                d.rectangle((x, y, min(w - 7, x + 5), y + 5), fill=c)
                d.rectangle((x + 1, y + 5, min(w - 7, x + 4), y + 7), fill=c)
            if ismarket:
                for x in [9, w - 11]:
                    d.rectangle((x, y + 8, x + 2, b - 1), fill=edge)
        if form == "galaxy":
            for x in (7, w - 11):
                d.rectangle((x, top + depth + 1, x + 3, b - 1), fill=edge)
            d.polygon(
                [(cx - 4, 8), (cx, 4), (cx + 4, 8), (cx, 12)],
                fill="#d1b463",
                outline=ink,
            )
        if form == "aqueduct":
            for x in [7, w - 17]:
                d.arc((x, b - 14, x + 10, b + 4), 180, 360, fill=ink, width=2)
        if form == "factory":
            for x in range(9, w - 6, 9):
                d.line((x, b - 9, x + 3, b - 9), fill=mid)
        if key in ("eatery", "club", "fairy"):
            for x in [cx - 11, cx + 8]:
                d.ellipse(
                    (x, b - 17, x + 4, b - 10),
                    fill="#d8997b" if key == "eatery" else "#b9a6dd",
                    outline=ink,
                )
    # The door is always centred above the collision tile; the pixel anchors below are used by the map compiler.
    door = bitmap("home_blue").crop((16, 45, 31, 64))
    im.alpha_composite(door, (cx - 7, h - 19))
    d.line((cx - 7, h - 2, cx + 7, h - 2), fill="#b6a58e")
    return im


@lru_cache(None)
def vegetation(name):
    tree = bitmap("tree")
    data = []
    for r, g, b, a in tree.getdata():
        if g > r * 1.05 and g > b * 1.10:
            l = (r + 2 * g + b) // 4
            if name == "autumn":
                r, g, b = min(228, l + 94), min(170, l + 35), max(58, l - 15)
            if name == "mushwood":
                r, g, b = l // 2 + 39, l // 2 + 64, l // 2 + 76
            if name == "snowtree":
                r, g, b = min(219, l + 96), min(235, l + 110), min(238, l + 117)
        data.append((r, g, b, a))
    tree.putdata(data)
    return tree


def feature(key):
    if key in ("berry", "flowers", "fountain", "lamp", "bench"):
        return bitmap(
            {
                "berry": "berry_tree",
                "flowers": "flowers",
                "fountain": "fountain",
                "lamp": "streetlamp",
                "bench": "carebench",
            }[key]
        )
    if key in (
        "gianttree",
        "painted",
        "olive",
        "fir",
        "snowtree",
        "autumn",
        "mushwood",
    ):
        t = vegetation(
            {
                "fir": "snowtree",
                "painted": "autumn",
                "gianttree": "tree",
                "olive": "tree",
            }.get(key, key)
        ).copy()
        d = ImageDraw.Draw(t)
        if key == "gianttree":
            t = t.resize((48, 66), Image.Resampling.NEAREST)
        if key == "olive":
            for x, y in [(11, 14), (16, 18), (21, 13), (9, 20)]:
                d.rectangle((x, y, x + 1, y + 2), fill="#3c4f4b")
        if key == "painted":
            for y, c in [(29, "#e7bc55"), (32, "#bd728c"), (35, "#81b9c2")]:
                d.arc((8, y - 4, 24, y + 3), 0, 165, fill=c, width=2)
        return t
    ink = "#4e5155"
    stone = "#989890"
    light = "#cbc5ad"
    wood = "#a97c53"
    bark = "#705a48"
    leaf = "#73974f"
    gold = "#d6b467"
    blue = "#649ca9"
    w, h = {
        "ferris": (68, 69),
        "crystal": (35, 32),
        "bulb": (31, 35),
        "turbine": (51, 61),
        "fossil": (55, 28),
        "mural": (76, 44),
        "geoglyph": (66, 40),
        "court": (74, 40),
        "plaza": (78, 45),
        "stage": (75, 45),
        "mosaic": (67, 35),
        "maze": (67, 35),
        "stones": (58, 36),
        "waterfall": (43, 51),
        "quarry": (51, 37),
        "stairs": (64, 34),
        "viaduct": (66, 37),
        "timberbridge": (64, 25),
        "columns": (62, 38),
        "shrine": (67, 48),
        "altar": (53, 34),
        "campbig": (67, 43),
        "lookout": (45, 42),
        "watchtower": (38, 55),
        "wreck": (64, 41),
        "minecart": (38, 28),
        "bamboo": (30, 43),
        "barrier": (53, 28),
        "slopeflags": (50, 26),
        "coil": (28, 53),
        "lift": (46, 45),
        "shrinegate": (52, 50),
        "gate": (53, 41),
        "ruins": (52, 35),
        "ruinarch": (47, 39),
        "arch": (44, 36),
        "awning": (54, 28),
        "hay": (34, 23),
        "driftwood": (42, 24),
        "stump": (35, 26),
        "timbers": (49, 31),
        "tower": (37, 63),
        "pump": (41, 41),
        "chimney": (30, 58),
        "cairn": (25, 27),
        "floe": (33, 21),
        "fountain": (36, 30),
        "lighthouse": (35, 55),
        "sunflower": (28, 31),
        "stall": (42, 33),
        "icearch": (54, 44),
        "pitch": (56, 28),
    }.get(key, (35, 32))
    im = Image.new("RGBA", (w, h))
    d = ImageDraw.Draw(im)
    c = w // 2
    b = h - 2

    def box(bb, col):
        panel(d, bb, ink, col, light)

    def tent(x, y, size):
        d.polygon(
            [(x - size, y), (x - 1, y - size), (x + size, y), (x + 9, y + 2)],
            fill="#d2b47d",
            outline=bark,
        )
        d.polygon(
            [(x - size, y), (x - 1, y - size), (x + 3, y)], fill="#af875b", outline=bark
        )
        d.polygon(
            [(x - size + 5, y), (x - 2, y - size + 5), (x - 1, y)], fill="#645d51"
        )
        d.line((x - 1, y - size, x + size - 2, y - 3), fill="#f1d19a")

    def pillar(x, y, n):
        box((x - 3, y - n, x + 3, y - 3), stone)
        d.line((x - 1, y - n + 2, x - 1, y - 5), fill=light)
        box((x - 6, y - 4, x + 6, y), stone)
        box((x - 6, y - n - 3, x + 6, y - n), light)

    def gem(x, y, n, col):
        d.polygon(
            [
                (x - n // 2, y - 2),
                (x - n // 3, y - n),
                (x + 1, y - n - 4),
                (x + n // 2, y - n + 1),
                (x + n // 3, y),
            ],
            fill=col,
            outline=ink,
        )
        d.line((x + 1, y - n - 3, x - 1, y - 3), fill="#d3e7de")

    def beam(a, z, sz=3):
        d.line((a, z), fill=bark, width=sz + 2)
        d.line((a, z), fill=wood, width=sz)

    def rock(x, y, n):
        d.polygon(
            [
                (x - n, y - 3),
                (x - n + 2, y - n),
                (x - 2, y - n - 4),
                (x + n - 4, y - n),
                (x + n, y - 3),
                (x + 3, y),
            ],
            fill=stone,
            outline=ink,
        )
        d.line(
            (x - n + 3, y - n, x - 2, y - n - 2, x + 3, y - n + 1), fill=light, width=2
        )

    if key in (
        "ruinarch",
        "arch",
        "icearch",
        "ruins",
        "columns",
        "column",
        "shrine",
        "altar",
        "standing",
        "cairn",
        "stones",
        "quarry",
    ):
        if key in ("standing", "cairn", "stones", "quarry"):
            loc = (
                [(c, b, 10)]
                if key in ("standing", "cairn")
                else [(8, b - 2, 7), (w - 9, b - 3, 7), (c, b // 2, 8)]
            )
            for x, y, n in loc:
                rock(x, y, n)
                rock(x - 1, y - n + 1, n - 3)
                if key == "cairn":
                    rock(x, y - n - 5, 3)
        elif key == "shrine":
            for i in range(3):
                box((4 + i * 3, b - 3 - i * 3, w - 5 - i * 3, b - i * 3), stone)
            for x in [14, c, w - 15]:
                pillar(x, b - 10, 20)
            d.polygon([(3, 15), (c, 2), (w - 4, 15)], fill=light, outline=ink)
            d.line((8, 16, w - 9, 16), fill=stone, width=3)
        elif key == "altar":
            box((4, b - 8, w - 5, b), stone)
            box((8, b - 14, w - 9, b - 7), light)
            d.polygon(
                [(c - 3, b - 13), (c - 1, 6), (c + 2, 4), (c + 2, b - 13)],
                fill="#9ab3b3",
                outline=ink,
            )
            d.line((c - 6, 13, c + 7, 13), fill=gold, width=3)
        else:
            for x in [c] if key == "column" else [8, w - 9]:
                pillar(x, b, 19 if key == "ruins" else h - 12)
            if key not in ("column", "columns", "ruins"):
                box((4, 4, w - 5, 11), "#a6cdd5" if key == "icearch" else light)
            if key == "ruins":
                rock(c - 1, b - 2, 8)
    elif key in ("camp", "campbig", "tent"):
        tent(c - 5, b - 2, 14 if key != "campbig" else 20)
        box((w - 11, b - 7, w - 2, b - 1), wood)
        if key == "campbig":
            d.ellipse((40, 30, 53, 39), fill=stone, outline=ink)
            d.polygon([(44, 35), (47, 25), (50, 35)], fill="#d58c5a")
    elif key in (
        "minecart",
        "rail",
        "timbers",
        "viaduct",
        "timberbridge",
        "jetty",
        "wreck",
        "log",
        "driftwood",
        "stump",
    ):
        if key in ("viaduct", "timberbridge", "jetty", "rail"):
            for x in range(4, w - 2, 7):
                d.rectangle((x, b - 13, x + 3, b - 1), fill=bark)
                d.line((x + 1, b - 12, x + 1, b - 3), fill=wood)
            for y in [b - 11, b - 4] if key == "rail" else [b - 18, b - 12, b - 7]:
                beam((1, y), (w - 2, y))
            if key != "rail":
                for x in range(3, w - 2, 11):
                    d.line((x, b - 21, x, b - 15), fill=bark, width=2)
        elif key == "minecart":
            for x in [9, w - 10]:
                d.ellipse((x - 4, b - 7, x + 4, b), fill=ink, outline=stone)
            d.polygon(
                [(2, 8), (w - 3, 8), (w - 7, b - 6), (7, b - 6)],
                fill="#8b8a80",
                outline=ink,
            )
            d.rectangle((1, 7, w - 2, 10), fill=stone, outline=ink)
            for x in [9, 17, 24]:
                rock(x, 8, 4)
        elif key == "timbers":
            for x in [6, w - 8]:
                beam((x, b), (x, 6), 5)
            beam((2, 6), (w - 3, 6), 6)
            beam((6, 17), (16, 7))
            beam((w - 8, 17), (w - 18, 7))
        elif key == "wreck":
            d.polygon(
                [
                    (1, b - 13),
                    (20, b - 11),
                    (w - 3, b - 20),
                    (w - 12, b - 2),
                    (c, b),
                    (9, b - 3),
                ],
                fill=wood,
                outline=bark,
            )
            for row in [4, 8]:
                d.line(
                    (5, b - 12 + row, 20, b - 10 + row, w - 7, b - 19 + row), fill=bark
                )
            beam((c, b - 11), (c - 5, 4))
            d.polygon(
                [(c - 4, 4), (c - 3, 16), (c + 11, 15)], fill="#c7b99b", outline=bark
            )
        elif key == "stump":
            d.polygon([(5, b), (9, 12), (25, 11), (30, b)], fill=wood, outline=bark)
            d.ellipse((7, 8, 27, 17), fill="#ccae79", outline=bark)
            d.ellipse((12, 10, 22, 14), outline=bark)
        else:
            beam((4, b - 1), (w - 6, b - 15), 7)
            beam((w // 2, b - 8), (w // 2 - 2, b - 18))
            d.ellipse((2, b - 6, 8, b), fill="#d3ab77", outline=bark)
    elif key in ("crystal", "ore", "floe", "fossil"):
        if key == "fossil":
            for i in range(7):
                d.arc(
                    (5 + i * 6, 4 + abs(i - 3), 15 + i * 6, b - 3),
                    30,
                    170,
                    fill="#d7bf97",
                    width=3,
                )
            beam((5, 12), (w - 6, 13), 2)
        elif key == "floe":
            d.polygon(
                [
                    (1, b - 8),
                    (11, 4),
                    (w - 9, 5),
                    (w - 2, b - 7),
                    (w - 11, b),
                    (8, b - 1),
                ],
                fill="#c0e0e2",
                outline=blue,
            )
            d.line((2, b - 8, 12, 7, w - 9, 8), fill="#e5eeee", width=2)
        else:
            rock(c, b, 12)
            color = "#97cad4" if key == "crystal" else "#c79e74"
            for x, y, n in [(c - 5, b - 2, 10), (c + 1, b - 4, 20), (c + 8, b - 2, 12)]:
                gem(x, y, n, color)
    elif key in ("bulb", "reed", "sunflower", "cactus", "bamboo"):
        if key == "bulb":
            for x, y, n, col in [(10, b - 2, 10, "#9388c0"), (w - 8, b, 6, "#7db0c0")]:
                d.rectangle((x - 2, y - n - 3, x + 2, y), fill="#c6bdcf", outline=ink)
                d.pieslice(
                    (x - n, y - n * 2 - 4, x + n, y - 3),
                    180,
                    360,
                    fill=col,
                    outline=ink,
                )
                d.ellipse((x - 3, y - n * 2 - 1, x, y - n * 2 + 2), fill="#e6d3bb")
        elif key == "bamboo":
            for x, y in [(5, 13), (13, 3), (23, 9)]:
                d.rectangle((x, y, x + 2, b), fill="#a3ab68", outline="#657c50")
                for yy in range(y + 3, b - 1, 7):
                    d.line((x - 1, yy, x + 3, yy), fill="#a5b983")
                    d.polygon([(x, yy), (x - 6, yy - 6), (x - 3, yy - 1)], fill=leaf)
        elif key == "cactus":
            d.rounded_rectangle((c - 3, 6, c + 3, b), 2, fill=leaf, outline=ink)
            d.line((c - 8, 13, c - 8, 20, c, 21), fill=leaf, width=4)
            d.line((c + 7, 12, c + 7, 17, c, 18), fill=leaf, width=4)
        else:
            for x, y in [(7, 14), (16, 7), (23, 12)]:
                d.line((x + 1, b, x, y), fill="#63784d", width=2)
                d.line((x, b - 5, x + 5, y + 4), fill=leaf, width=2)
                if key == "sunflower":
                    d.ellipse(
                        (x - 3, y - 4, x + 4, y + 3), fill=gold, outline="#b39242"
                    )
                    d.point((x, y), fill=bark)
                else:
                    d.line((x, y, x, y + 5), fill="#9f7e50", width=2)
    elif key in (
        "watchtower",
        "lookout",
        "tower",
        "chimney",
        "turbine",
        "pump",
        "coil",
        "lift",
        "ferris",
    ):
        if key == "ferris":
            r = 24
            d.ellipse((c - r, 2, c + r, 2 + 2 * r), outline=ink, width=3)
            cy = r + 2
            for i in range(8):
                x, y = (
                    round(c + r * math.cos(i * math.pi / 4)),
                    round(cy + r * math.sin(i * math.pi / 4)),
                )
                d.line((c, cy, x, y), fill=stone)
                box((x - 3, y + 1, x + 3, y + 6), roofcolor(i))
            for x in [c - 15, c + 15]:
                d.line((c, cy, x, b), fill=ink, width=4)
                d.line((c, cy, x, b), fill=light, width=2)
        elif key == "turbine":
            d.polygon(
                [(c - 4, b), (c - 1, 21), (c + 2, 21), (c + 4, b)],
                fill=light,
                outline=ink,
            )
            for dx, dy in [(4, -20), (16, 12), (-18, 6)]:
                d.polygon(
                    [(c, 23), (c + dx, 23 + dy), (c + dx // 2 - 2, 23 + dy // 2 + 2)],
                    fill="#e4ddc4",
                    outline=stone,
                )
        elif key in ("watchtower", "lookout", "lift"):
            for x in [7, w - 9]:
                beam((x, b), (x, 14), 4)
            beam((6, b - 2), (w - 8, 20), 2)
            beam((w - 9, b - 2), (7, 22), 2)
            box((4, 14, w - 5, 22), wood)
            d.polygon([(1, 13), (c, 3), (w - 2, 13)], fill="#847865", outline=ink)
            for y in range(24, b, 4):
                d.line((8, y, 15, y), fill=wood)
        else:
            box((c - 6, 10, c + 6, b), stone if key in ("coil", "pump") else wood)
            box((c - 9, 5, c + 9, 10), shadecolor(key))
            box((c - 10, b - 4, c + 10, b), stone)
            if key == "coil":
                for y in range(11, b - 5, 6):
                    d.ellipse((c - 8, y, c + 8, y + 4), fill=blue, outline=ink)
            elif key == "pump":
                d.arc((1, 10, c + 5, b + 4), 180, 315, fill=blue, width=5)
                box((c + 8, b - 14, w - 3, b - 2), stone)
            else:
                for y in range(16, b - 8, 7):
                    d.line((c - 5, y, c + 5, y), fill=bark)
    elif key in (
        "mural",
        "geoglyph",
        "court",
        "mosaic",
        "maze",
        "plaza",
        "stage",
        "stairs",
        "steep",
        "bath",
        "waterfall",
    ):
        if key in ("mural", "geoglyph"):
            if key == "mural":
                box((1, 4, w - 2, b), stone)
            col = "#e8dda7"
            d.ellipse((c - 4, 7, c + 4, 15), outline=col, width=2)
            d.line((c, 15, c - 2, 24, c - 10, b - 4), fill=col, width=2)
            d.line((c - 1, 23, c + 7, b - 4), fill=col, width=2)
            d.line((c, 18, c - 10, 13, c - 15, 7), fill=col, width=2)
            d.line((c, 17, c + 12, 14, c + 17, 20), fill=col, width=2)
        elif key == "waterfall":
            d.polygon(
                [(8, 4), (w - 9, 4), (w - 5, b - 4), (w - 10, b), (7, b), (2, b - 4)],
                fill="#78b8cc",
                outline=blue,
            )
            for x in range(10, w - 7, 5):
                d.line((x, 5, x - 2, b - 6), fill="#c9e0d8", width=2)
        elif key in ("stairs", "steep"):
            for y in range(5, b - 1, 4):
                box((3, y, w - 4, y + 4), stone)
        elif key == "bath":
            d.ellipse((0, 3, w - 1, b), fill=stone, outline=ink)
            d.ellipse((3, 5, w - 4, b - 3), fill=blue, outline=light)
        elif key == "stage":
            box((1, b - 12, w - 2, b), wood)
            d.rectangle(
                (3, b - 15, w - 4, b - 9), fill=shadecolor("metal"), outline=ink
            )
            for x in [5, w - 14]:
                box((x, b - 29, x + 8, b - 14), ink)
                d.ellipse((x + 1, b - 24, x + 7, b - 18), outline=stone)
            d.line((c, b - 14, c, b - 25, c + 3, b - 27), fill=stone, width=2)
        elif key == "maze":
            for pts in [
                [
                    (2, b),
                    (2, 3),
                    (w - 3, 3),
                    (w - 3, b - 3),
                    (c, b - 3),
                    (c, 12),
                    (13, 12),
                    (13, b - 4),
                ],
                [(c + 9, 10), (w - 10, 10), (w - 10, b - 10)],
            ]:
                d.line(pts, fill="#597b54", width=5)
                d.line(pts, fill="#91ac65", width=2)
        else:
            colors = {"court": "#b69079", "plaza": "#c0b59f", "mosaic": "#998daf"}
            box((1, 2, w - 2, b), colors[key])
            d.rectangle((4, 5, w - 5, b - 3), outline="#eee0b5")
            d.line((c, 6, c, b - 4), fill=light)
            d.ellipse(
                (c - 8, h // 2 - 6, c + 8, h // 2 + 6), outline="#efdebb", width=2
            )
    elif key in ("shrinegate", "gate", "barrier", "slopeflags"):
        for x in [7, w - 9]:
            beam((x, b), (x, 7), 4)
        if key == "slopeflags":
            for x in [7, w - 9]:
                d.polygon([(x, 4), (x + 7, 7), (x, 11)], fill="#bb696b", outline=bark)
        else:
            beam((2, 8), (w - 3, 8), 5)
            beam((5, 15), (w - 5, 15), 3)
    elif key in ("stall", "awning", "hay", "crate", "buoy"):
        if key in ("stall", "awning"):
            for x in [4, w - 6]:
                beam((x, b), (x, 9))
                box((3, b - 8, w - 4, b), wood)
            for x in range(1, w - 2, 5):
                d.rectangle(
                    (x, 5, min(w - 2, x + 4), 14),
                    fill=gold if ((x - 1) // 5) % 2 else "#b67764",
                    outline=bark,
                )
        elif key == "hay":
            for x, y in [(3, 9), (14, 4)]:
                d.rounded_rectangle((x, y, x + 15, y + 10), 3, fill=gold, outline=bark)
                d.ellipse((x + 7, y + 1, x + 15, y + 9), outline=wood)
        elif key == "buoy":
            d.ellipse((c - 6, b - 5, c + 6, b), fill=blue)
            d.polygon(
                [(c - 5, b - 4), (c - 2, b - 15), (c + 2, b - 15), (c + 5, b - 4)],
                fill="#be7268",
                outline=ink,
            )
            d.line((c, b - 16, c, b - 22), fill=wood)
        else:
            box((7, 10, 27, b - 2), wood)
            beam((9, 12), (25, b - 4), 2)
            beam((25, 12), (9, b - 4), 2)
    elif key == "bookcase":
        panel(d, (1, 3, w - 2, b), bark, "#a5876c", "#dac3a1")
        d.rectangle((4, 6, w - 5, b - 4), fill="#6e6962")
        for yy in (7, 16):
            for xx, col in zip(
                range(5, w - 6, 4),
                ["#9a727c", "#869ea1", "#ba9c67", "#829581", "#9d7b86", "#9295ab"],
            ):
                d.rectangle((xx, yy + xx % 2, xx + 2, yy + 6), fill=col)
                d.line((xx, yy + 3, xx + 2, yy + 3), fill="#d5c2a0")
            d.rectangle((3, yy + 7, w - 4, yy + 9), fill=wood)
    elif key == "reactor":
        d.ellipse((2, b - 6, w - 3, b), fill="#657582", outline=ink)
        d.rectangle((4, 8, w - 5, b - 3), fill="#8b9da4", outline=ink)
        d.rectangle((7, 11, w - 8, b - 8), fill="#5d7f8e", outline="#c1d1cd")
        gem(c, b - 9, 10, "#8fc6d0")
        d.ellipse((3, 4, w - 4, 12), fill="#acbec1", outline=ink)
        d.line((c - 6, 6, c + 6, 6), fill="#d4dfd3")
    elif key == "urn":
        d.ellipse((c - 7, b - 16, c + 7, b), fill="#ba8265", outline=bark)
        d.rectangle((c - 4, b - 20, c + 4, b - 14), fill="#c4966d", outline=bark)
        d.line((c - 5, b - 20, c + 5, b - 20), fill=light, width=2)
    elif key == "ruin":
        return bitmap("ruin")
    else:
        raise KeyError(key)
    return im


def roofcolor(i):
    return ("#b87872", "#c7a16a", "#7f99aa", "#a38baa")[i % 4]


def shadecolor(k):
    return "#7c9398" if k in ("pump", "metal") else "#947865"


@lru_cache(None)
def asset(key):
    img = building(key) if key in BUILDINGS else feature(key)
    path = OUT / (key + ".png")
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, optimize=True)
    return img, "res://" + str(path.relative_to(ROOT)), [img.width // 2, img.height]
