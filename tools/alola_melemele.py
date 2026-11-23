"""Author the four-way reading of Melemele's town, forest path and commercial streets.

Retail locations retain their event, trainer and island-exit coordinates. Iki's
new household doors and Hau'oli's shop doors have explicit paired vestibules.
"""

import base64
import json
import zlib
from functools import lru_cache
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageChops
from scipy import ndimage

from kalos_gym_rooms import tile
from unova_art import K

ROOT = Path(__file__).resolve().parents[1]
MAPS = ROOT / "content/regions/alola/maps"
IMAGES = ROOT / "assets/alola/maps"
STREETS = ROOT / "assets/alola/streets"
CUSTOM = "res://assets/alola/streets/"
CATALOG = json.loads((ROOT / "content/emerald_fields.json").read_bytes())["anchors"]
HOMES = [
    (
        "hala_house",
        "岛屿之王哈拉的家",
        (6, 9),
        "hala_lodge",
        "em_dewford_town_hall",
        "哈拉的徒弟",
        "在木台上交手时，哈拉老师总先向守护神行礼。",
    ),
    (
        "iki_west_house",
        "利利小镇・西边的民家",
        (4, 20),
        "village_hut",
        "em_fortree_city_house1",
        "编席的居民",
        "我们把草叶编成坐垫。祭典那天，连门前的石阶都会坐满人。",
    ),
    (
        "iki_east_house",
        "利利小镇・东边的民家",
        (22, 10),
        "village_cottage",
        "em_dewford_town_house1",
        "看护山路的居民",
        "过了祭台，向北穿过树荫就是马哈罗山路。",
    ),
    (
        "iki_south_house",
        "利利小镇・南边的民家",
        (18, 23),
        "village_hut",
        "em_pacifidlog_town_house1",
        "栽花的居民",
        "天一亮，1号道路那边的风就会吹进来。",
    ),
]
CIVIC_ROOMS = [
    (
        "tourism_bureau",
        "好奥乐市・旅游服务中心",
        (45, 38),
        "tourism_bureau",
        "em_lilycove_city_harbor",
        "旅游服务员",
        "北边是2号道路。向东可去海滨区，沿海岸往南走就是港口。",
    ),
    (
        "malasada_shop",
        "好奥乐市・马拉萨达店",
        (68, 26),
        "malasada_shop",
        "em_slateport_city_pokemon_fan_club",
        "马拉萨达店员",
        "欢迎光临。",
    ),
]
SHOP_DOORS = {
    "center_hauoli": ((32, 26), "center"),
    "hauoli_city_hall": ((37, 50), "academy"),
    "hauoli_mall": ((60, 23), "shopping_arcade"),
    "hauoli_police": ((76, 49), "home_blue"),
    "photo_hauoli": ((23, 43), "mart"),
    "ilima_room": ((48, 17), "home"),
    **{key: (point, kind) for key, _, point, kind, *_ in CIVIC_ROOMS},
}


def read(path):
    return json.loads(path.read_bytes())


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n")


def pack(values):
    return base64.b64encode(zlib.compress(np.asarray(values, dtype="<u2").tobytes())).decode()


@lru_cache(None)
def cell(key):
    return (
        Image.open(STREETS / (key + ".png")).convert("RGB")
        if key in ("volcanic", "cobbles", "quay")
        else tile(key)
    )


class Field:
    def __init__(self, m):
        self.m = m
        self.w, self.h = m["size"]
        phys = m["physics"]
        self.s = np.array(phys["collision"], bool)
        self.water = np.asarray(phys.get("water", np.zeros_like(self.s)), bool)
        self.grass = np.asarray(phys.get("grass", np.zeros_like(self.s)), bool)
        self.surface = Image.new("RGB", (self.w * 16, self.h * 16))
        self.layers = np.full((self.h, self.w), "grass", object)
        self.props = []
        self.reserved = set()
        self.objects = m["objects"]
        for row in m["warps"] + m["npcs"] + m["alola_item_tiles"] + m["alola_trainer_tiles"]:
            self.protect(row["at"])
        for xy in list(m["alola_anchors"].values()) + [m["spawn"]]:
            self.protect(xy)
        self.landmark_rect = []

    def protect(self, xy):
        x, y = xy
        self.reserved.add((x, y))

    def path(self, points, width=3, material="path"):
        mask = Image.new("1", (self.w, self.h))
        d = ImageDraw.Draw(mask)
        d.line(points, fill=1, width=width)
        r = width // 2
        for x, y in points:
            d.rectangle((x - r, y - r, x + r, y + r), fill=1)
        self.layers[np.asarray(mask, bool)] = material

    def trail(self, points, width):
        # Centre the footpath on reachable ground even when its straight guide crosses
        # an outcrop, a patch of tall grass, or an unrelated 3D-model collision.
        import heapq

        terrain = (~self.s) & (~self.water)
        groups, _ = ndimage.label(terrain)
        start = self.m["spawn"]
        terrain &= groups == groups[start[1], start[0]]
        clear = terrain & ~self.grass
        _, nearest = ndimage.distance_transform_edt(~clear, return_indices=True)

        def snap(point):
            x, y = point
            return (int(nearest[1, y, x]), int(nearest[0, y, x]))

        anchors = [snap(p) for p in points]
        openness = ndimage.distance_transform_edt(clear)
        for a, b in zip(anchors, anchors[1:]):
            guide = Image.new("1", (self.w, self.h))
            ImageDraw.Draw(guide).line((a, b), fill=1)
            away = ndimage.distance_transform_edt(~np.asarray(guide))
            cost = np.minimum(away, 15) * 0.28 + np.maximum(0, 2.5 - openness) + 1 + self.grass * 9
            queue = [(0, a)]
            visited = {a: 0}
            previous = {}
            while queue:
                g, current = heapq.heappop(queue)
                if current == b:
                    break
                x, y = current
                if g > visited[current]:
                    continue
                for dx, dy in ((0, -1), (1, 0), (0, 1), (-1, 0)):
                    xx, yy = x + dx, y + dy
                    if not (0 <= xx < self.w and 0 <= yy < self.h and terrain[yy, xx]):
                        continue
                    ng = g + float(cost[yy, xx])
                    if ng >= visited.get((xx, yy), float("inf")):
                        continue
                    previous[xx, yy] = current
                    visited[xx, yy] = ng
                    heapq.heappush(queue, (ng, (xx, yy)))
            walk = [b]
            while walk[-1] != a:
                walk.append(previous[walk[-1]])
            self.path(walk, width)

    def block(self, box, blocked=True):
        x, y, r, b = box
        self.s[y : b + 1, x : r + 1] = blocked

    def decor(self, key, x, y, anchor=None):
        self.props.append(
            [key, int(x), int(y)] if anchor is None else [CUSTOM + key + ".png", int(x), int(y), anchor]
        )

    def ground(self):
        out = np.zeros((self.h, 16, self.w, 16, 3), np.uint8)
        tiles = out.transpose(0, 2, 1, 3, 4)
        land = self.layers.copy()
        path = land == "path"
        pad = np.pad(path, 1, constant_values=True)
        dx = np.where(~pad[1:-1, :-2], 0, np.where(~pad[1:-1, 2:], 2, 1))
        dy = np.where(~pad[:-2, 1:-1], 0, np.where(~pad[2:, 1:-1], 2, 1))
        land[path] = np.char.add(np.char.add("trail_", dy[path].astype(str)), dx[path].astype(str))
        land[self.grass] = "tall"
        dry = ~self.water
        pad = np.pad(dry, 1, constant_values=False)
        shore = pad[:-2, 1:-1].astype("uint8") + 2 * pad[2:, 1:-1] + 4 * pad[1:-1, 2:] + 8 * pad[1:-1, :-2]
        for e in range(16):
            land[self.water & (shore == e)] = "shore_" + str(e)
        for key in np.unique(land):
            tiles[land == key] = np.asarray(cell(str(key)).convert("RGB"))
        self.surface = Image.fromarray(out.reshape(self.h * 16, self.w * 16, 3))
        # Outdoor ground is textured to its edge. Grass, paths, sidewalks and water
        # get distinct transitions rather than the square seams of a 3D mesh projection.
        self.border(
            path & ~self.grass & ~self.water,
            "trail_11",
            "grass",
            [((178, 164, 104), (137, 151, 93)), ((203, 183, 112), (188, 163, 105))],
        )
        street = np.isin(self.layers, ["quay", "cobbles"]) & ~self.water & ~self.grass
        self.border(
            street,
            "quay",
            "grass",
            [
                ((88, 110, 107), (78, 101, 103)),
                ((144, 153, 151), (109, 128, 128)),
                ((206, 207, 181), (185, 188, 172)),
                ((227, 225, 199), (202, 203, 185)),
                ((201, 199, 182), (150, 162, 158)),
            ],
        )
        self.border(
            self.water,
            "shore_0",
            "grass",
            [
                ((82, 127, 125), (98, 142, 138)),
                ((128, 175, 157), (142, 180, 165)),
                ((202, 224, 197), (174, 208, 183)),
                ((146, 192, 191), (103, 177, 185)),
                ((112, 169, 186), (140, 184, 189)),
            ],
            smooth=7,
        )

    def border(self, mask, key, dry_key, tones, smooth=4):
        if not mask.any():
            return
        # A threshold through the centre of neighbouring tiles rounds the visible corners.
        # All passability and encounter tests continue to use those centres.
        small = Image.fromarray(mask.astype("uint8") * 255)
        extent = self.surface.size
        raw = small.resize(extent, Image.Resampling.NEAREST)
        smooth_mask = (
            small.resize(extent, Image.Resampling.BILINEAR)
            .filter(ImageFilter.GaussianBlur(smooth))
            .point(lambda v: 255 if v >= 127 else 0)
        )

        def repeat(material):
            image = cell(material).convert("RGB")
            return Image.fromarray(np.tile(np.asarray(image), (self.h, self.w, 1)))

        self.surface.paste(repeat(dry_key), mask=ImageChops.subtract(raw, smooth_mask))
        self.surface.paste(repeat(key), mask=ImageChops.subtract(smooth_mask, raw))
        # 1px highlights, intermittent silt and bevel joints survive native camera zoom.
        a = np.asarray(smooth_mask) > 0
        rim = a & ~ndimage.binary_erosion(a, iterations=len(tones), border_value=1)
        yy, xx = np.where(rim)
        if len(xx) == 0:
            return
        source = np.asarray(self.surface).copy()
        inner = a
        for index, (light, dark) in enumerate(tones):
            nxt = ndimage.binary_erosion(inner, border_value=1)
            yy, xx = np.where(inner & ~nxt)
            light = np.array(light)
            dark = np.array(dark)
            joints = (xx // 3 + yy // 3) % 6 == 0
            source[yy, xx] = np.where(joints[:, None], dark, light)
            inner = nxt
        self.surface = Image.fromarray(source)

    def trees(self, mask, palms=False):
        # The traversable gap beneath a canopy remains walkable; only trunks block.
        self.layers[mask] = "grass"
        used = np.zeros_like(mask)
        for y in range(1, self.h):
            for x in range(1, self.w - 1):
                if not mask[y, x] or used[y, x] or (x, y) in self.reserved:
                    continue
                if (x * 31 + y * 13) % 11 > 6:
                    continue
                if (x + 1, y) in self.reserved or not mask[y, x + 1]:
                    continue
                if palms and (x * 17 + y * 9) % 7 == 0:
                    self.decor("palm", x, y, [23, 48])
                else:
                    self.decor("tree", x, y)
                used[max(0, y - 2) : y + 2, max(0, x - 1) : x + 2] = True

    def save(self):
        self.m["physics"]["collision"] = self.s.astype("uint8").tolist()
        for k, arr in [("water", self.water), ("grass", self.grass)]:
            if arr.any():
                self.m["physics"][k] = arr.astype("uint8").tolist()
            else:
                self.m["physics"].pop(k, None)
        self.m["hoenn_art"]["t"] = pack(np.where(self.s, K["wall"], K["grass"]))
        self.m["hoenn_art"]["p"] = self.props
        self.surface.quantize(192, dither=Image.Dither.NONE).save(
            IMAGES / (self.m["alola_image"] + ".png"), optimize=True
        )
        write(MAPS / (self.m["id"] + ".json"), self.m)


def doorstep(f, key, point, kind):
    x, y = point
    if kind in ("hala_lodge", "village_hut", "village_cottage"):
        w = 6 if kind == "hala_lodge" else 4
        f.decor(kind, x, y - 1, [(94 if w == 6 else 62) // 2, 63])
        box = (x - w // 2, y - 3, x + (w - 1) // 2, y - 1)
    elif kind in ("shopping_arcade", "malasada_shop", "tourism_bureau"):
        w, h = Image.open(STREETS / (kind + ".png")).size
        left = (x * 16 + 8 - w // 2) // 16
        right = (x * 16 + 8 + w // 2 - 1) // 16
        box = (left, y - (h // 16) + 1, right, y - 1)
        f.decor(kind, x, y - 1, [w // 2, h])
    else:
        w, h = Image.open(ROOT / "assets/emerald/field" / (kind + ".png")).size
        ax, ay = CATALOG[kind]
        left = x + (8 - ax) // 16
        box = (left, y - (ay // 16) + 1, left + w // 16 - 1, y - 1)
        f.decor(kind, x, y - 1)
    f.block(box)
    f.landmark_rect.append(box)
    f.s[y, x] = False
    f.protect(point)
    f.protect((x, y + 1))
    return box


def platform(f):
    # Raised, octagonal timber arena with tapa-chevron trim around the fighting circle.
    x, y = 12 * 16 + 8, 13 * 16 + 8
    image = f.surface
    d = ImageDraw.Draw(image)
    r = 44

    def shape(yy, n):
        return [
            (x - n + 11, yy - n),
            (x + n - 11, yy - n),
            (x + n, yy - n + 11),
            (x + n, yy + n - 11),
            (x + n - 11, yy + n),
            (x - n + 11, yy + n),
            (x - n, yy + n - 11),
            (x - n, yy - n + 11),
        ]

    d.polygon(shape(y + 6, r), fill="#634b40", outline="#493b35")
    d.polygon(shape(y + 3, r), fill="#a8784b", outline="#79563b")
    deck = Image.new("RGB", image.size)
    dd = ImageDraw.Draw(deck)
    dd.rectangle((x - r, y - r, x + r, y + r), fill="#c89958")
    for row in range(y - r, y + r + 1, 7):
        dd.line((x - r, row, x + r, row), fill="#9a6945")
        dd.line((x - r, row + 1, x + r, row + 1), fill="#e0b87a")
        for ox in range(x - r + (row % 3) * 14, x + r, 33):
            dd.line((ox, row + 2, ox, row + 6), fill="#b38251")
    mask = Image.new("1", image.size)
    ImageDraw.Draw(mask).polygon(shape(y, r), fill=1)
    image.paste(deck, (0, 0), mask)
    d.line(shape(y, r) + [shape(y, r)[0]], fill="#81543c", width=2)
    for a, b in [(34, "#ba784b"), (31, "#eed299"), (28, "#9a5b41"), (9, "#e8ca87")]:
        d.ellipse((x - a, y - a, x + a, y + a), outline=b, width=2)
    for dx, dy in ((0, -21), (21, 0), (0, 21), (-21, 0)):
        d.polygon(
            [(x + dx, y + dy - 4), (x + dx + 4, y + dy), (x + dx, y + dy + 4), (x + dx - 4, y + dy)],
            fill="#e4c68a",
        )
    for xx, yy in [
        (x - r + 11, y - r + 5),
        (x + r - 12, y - r + 5),
        (x - r + 4, y + r - 14),
        (x + r - 4, y + r - 14),
    ]:
        d.rectangle((xx - 2, yy - 8, xx + 3, yy + 2), fill="#745537", outline="#614734")
        d.line((xx - 2, yy - 8, xx + 2, yy - 8), fill="#e9c17b", width=2)
    for i in range(3):
        d.line(
            (x - 13 - i, y + r + i * 2 + 1, x + 13 + i, y + r + i * 2 + 1),
            fill=["#d9aa68", "#a47b4e", "#e7c58a"][i],
            width=2,
        )


def ensure_anchors(f):
    m = f.m
    free = (~f.s) & (~f.water)
    for row in m["warps"]:
        x, y = row["at"]
        free[y, x] = False
    occupied = {tuple(m["spawn"])}
    occupied.update(tuple(r["at"]) for r in m["npcs"] + m["alola_item_tiles"] + m["alola_trainer_tiles"])
    for x, y in occupied:
        free[y, x] = False
    # Sources used generic spokes. Keep each eligible position unless a new wall covers it.
    for key, point in m["alola_anchors"].items():
        x, y = map(int, point)
        if not free[y, x] or (x, y) in occupied:
            options = np.argwhere(free)
            options = sorted(options.tolist(), key=lambda q: (abs(q[1] - x) + abs(q[0] - y), q[0], q[1]))
            for yy, xx in options:
                if (
                    (xx, yy) not in occupied
                    and 1 <= xx < f.w - 1
                    and 1 <= yy < f.h - 1
                    and sum(free[yy + dy, xx + dx] for dx, dy in ((0, 1), (1, 0), (-1, 0), (0, -1))) >= 2
                ):
                    x, y = xx, yy
                    break
            m["alola_anchors"][key] = [x, y]
        occupied.add((x, y))


def iki(f):
    f.s[:] = False
    f.s[[0, -1], :] = True
    f.s[:, [0, -1]] = True
    f.path([(24, 25), (24, 22), (22, 21), (15, 21), (12, 18), (12, 15)], 3)
    f.path([(3, 20), (3, 21), (9, 21), (12, 18)], 2)
    f.path([(6, 9), (6, 11), (9, 12), (12, 13), (18, 12), (22, 11), (22, 10)], 2)
    f.path([(12, 11), (12, 8), (9, 6), (8, 5), (8, 1)], 3)
    f.path([(18, 23), (18, 21)], 2)
    f.path([(12, 16), (16, 16), (18, 15)], 2)
    for key, _, point, kind, *_ in HOMES:
        doorstep(f, key, point, kind)
    mask = np.zeros_like(f.s)
    mask[:3, :] = True
    mask[:, 0:2] = True
    mask[:, 26:] = True
    mask[25:, :] = True
    mask[3:6, 1:5] = True
    mask[3:7, 15:27] = True
    mask[12:15, 22:27] = True
    mask[21:25, 6:12] = True
    mask &= f.layers != "path"
    for l, t, r, b in f.landmark_rect:
        mask[max(0, t - 3) : b + 2, max(0, l - 1) : r + 2] = False
    for y, x in np.argwhere(mask):
        if 0 < y < f.h - 1 and 0 < x < f.w - 1:
            f.s[y, x] = True
    f.trees(mask, palms=True)
    for x, y in [
        (9, 9),
        (18, 9),
        (20, 17),
        (8, 18),
        (15, 24),
        (3, 12),
        (24, 15),
        (16, 6),
        (8, 16),
        (17, 12),
        (17, 13),
        (8, 10),
        (9, 10),
    ]:
        f.layers[y, x] = "flowers"
    for x, y in [(2, 13), (18, 6), (21, 18), (14, 24)]:
        f.decor("palm", x, y, [23, 48])
        f.s[y, x] = True
    f.ground()
    platform(f)
    ensure_anchors(f)


def road_scene(f, src, mid):
    # Keep the survey's water, tall-grass fields, collision and route exits exactly aligned.
    raw = np.asarray(src.convert("RGB").resize((f.w, f.h), Image.Resampling.BOX), float)
    r, g, b = raw.transpose(2, 0, 1)
    blue = (b > r * 1.4) & (b > g * 1.04)
    blue_groups, n = ndimage.label(f.s & blue)
    counts = np.bincount(blue_groups.ravel(), minlength=n + 1)
    connected = np.zeros(n + 1, dtype=bool)
    connected[blue_groups[ndimage.binary_dilation(f.water, iterations=1)]] = True
    sea = f.water | (
        (blue_groups != 0)
        & ((counts[blue_groups] > 32) | (connected[blue_groups] & (counts[blue_groups] > 3)))
    )
    sand = (r > g * 0.97) & (r > b * 1.22) & (g > b * 1.08) & (r > 119)
    track = ndimage.binary_closing(sand, iterations=1) & ~sea & ~f.s
    f.layers[track] = "path"
    if mid == "1":
        # The 3D atlas also paints roofs and roofs' shadows a sandy colour.
        # Only the surveyed through-road and its real branches are dirt paths here.
        f.layers[:] = "grass"
        f.trail(
            [
                (12, 12),
                (16, 16),
                (26, 16),
                (27, 22),
                (38, 26),
                (47, 29),
                (57, 29),
                (72, 30),
                (87, 31),
                (95, 38),
                (99, 46),
                (113, 47),
                (120, 53),
                (126, 58),
            ],
            3,
        )
        f.trail([(36, 6), (37, 10), (44, 17), (47, 26)], 2)
        f.trail([(25, 15), (22, 11), (19, 9), (14, 10), (12, 12)], 2)
        f.trail([(87, 31), (84, 25), (79, 22), (72, 22)], 2)
    if mid == "mahalo":
        f.layers[:] = "grass"
        f.path([(19, 26), (19, 23), (14, 19), (13, 16), (13, 11)], 3)
        f.path([(13, 14), (8, 14), (7, 9), (10, 7), (15, 7)], 2)
    f.layers[f.s & ~sea] = "darkgrass"
    dry_wall = f.s & ~sea
    lava = (r > g * 1.12) & (b < g * 0.92) & (r < 161)
    cliffs = (g + b + r < 203) & ~blue & ~sea
    if mid in ("3", "5", "7", "8", "10", "11", "12", "13", "16", "17"):
        rockland = (lava | cliffs) & ~sea
        if mid in ("7", "12", "13"):
            f.layers[rockland] = "rockfloor"
            f.layers[ndimage.binary_erosion(rockland, iterations=2)] = "volcanic"
        else:
            f.layers[rockland] = "stone"
        rim = rockland & ~np.roll(rockland, -1, axis=0)
        f.layers[rim] = "cliff"
    if mid in ("7", "13", "14", "15"):
        beach = sand & ~sea
        if mid in ("7", "13"):
            beach = (beach & ~lava) | ((ndimage.distance_transform_edt(~sea) < 4) & ~rockland & ~sea)
        f.layers[beach] = "sand"
    bare = ((r > g * 1.1) & (r > b * 1.25) | cliffs) & dry_wall
    if mid == "mahalo":
        bare |= dry_wall
    # Raised rock faces use contiguous bands, and footpaths cannot draw over their bases.
    exposed = bare & ndimage.binary_dilation(~f.s & ~sea)
    f.layers[exposed] = "cliff"
    woods = dry_wall & ~bare
    if mid == "mahalo":
        woods = dry_wall.copy()
    if mid in ("7", "12", "13", "14", "15"):
        woods &= (g > r * 1.07) & ~cliffs
    f.trees(woods, palms=mid in ("1", "2", "5", "7", "8", "9", "14", "15", "16"))
    yy, xx = np.indices(f.s.shape)
    rocks = bare & ~exposed & (((xx * 13 + yy * 11) % 19) == 0)
    for y, x in np.argwhere(rocks):
        if (x, y) not in f.reserved:
            f.decor("rock", x, y)
    flowers = (
        (~f.s)
        & ~sea
        & ~f.grass
        & (f.layers == "grass")
        & ndimage.binary_dilation(woods, iterations=2)
        & (((xx * 43 + yy * 37) % 17) == 2)
    )
    f.layers[flowers] = "flowers"
    # Impassable ocean at the model border looks like the sea too.
    from alola_streets import FRONTS

    for warp in f.m["warps"]:
        dest = warp["to"]["map"].removeprefix("alola_")
        kind = "center" if dest.startswith("center_") else FRONTS.get(dest)
        if not kind:
            continue
        x, y = warp["at"]
        # Prefer the original size where it fits the established structure's base.
        for appearance in (kind, kind + "_compact"):
            if appearance not in CATALOG:
                continue
            tex = ROOT / "assets/emerald/field" / (appearance + ".png")
            width, height = Image.open(tex).size
            ax, ay = CATALOG[appearance]
            left = x + (8 - ax) // 16
            top = y - ay // 16 + 1
            right = left + width // 16
            if left < 0 or top < 0 or right > f.w or not f.s[y - 1, left:right].any():
                continue
            # The image and collision share the same origin and base tile.
            # Leave pre-existing script stands available even beside compact buildings.
            for yy in range(top, y):
                for xx in range(left, right):
                    if (xx, yy) not in f.reserved:
                        f.s[yy, xx] = True
            f.decor(appearance, x, y - 1)
            # Sidewalks and their doors remain clear on both sides of the warp.
            f.layers[y : y + 2, max(0, x - 1) : x + 2] = "quay"
            break
    if mid == "1":
        for x, y in [(52, 26), (53, 25), (54, 25), (61, 26), (62, 26), (61, 32), (60, 32), (55, 33)]:
            if not f.s[y, x] and not f.grass[y, x]:
                f.layers[y, x] = "flowers"
        for x, y in ((51, 26), (63, 25), (63, 32)):
            if (x, y) not in f.reserved and not f.grass[y, x]:
                f.decor("palm", x, y, [23, 48])
                f.s[y, x] = True
    if mid in ("7", "12", "13"):
        rock_fixtures = bare & f.s & ~exposed & (((xx * 19 + yy * 7) % 29) == 2)
        for y, x in np.argwhere(rock_fixtures):
            if (x, y) not in f.reserved:
                f.decor("boulder", x, y)
    if mid in ("7", "12", "13"):
        # On Ula'ula the volcanic ridges extend into accessible ground. Along their
        # flat, open margins, group dark rocks without sealing a one-cell passage.
        broad = ndimage.binary_erosion(~(sea | f.s | f.grass), iterations=3)
        rocks = broad & rockland & (((xx * 23 + yy * 17) % 53) == 3)
        for y, x in np.argwhere(rocks):
            if (x, y) in f.reserved:
                continue
            f.decor("boulder", x, y)
            f.s[y, x] = True
    water = f.water
    f.water = sea
    f.ground()
    f.water = water
    if mid == "mahalo":
        for x, y in ((9, 12), (16, 13), (11, 20), (18, 21)):
            if (x, y) not in f.reserved and f.s[y, x]:
                f.decor("palm", x, y, [23, 48])
        for x, y in [(13, 17), (13, 16), (13, 12)]:
            # A tread and two retaining stones mark the uphill approach.
            d = ImageDraw.Draw(f.surface)
            px = x * 16
            py = y * 16
            d.rectangle((px - 12, py + 7, px + 26, py + 10), fill="#a69b72")
            d.line((px - 12, py + 7, px + 26, py + 7), fill="#ddcb9b")
            d.line((px - 12, py + 11, px + 26, py + 11), fill="#786e53")


def city(f):
    m = f.m
    # The downtown arcade, City Hall and the police station each receive a real address.
    old = {w["to"]["map"].removeprefix("alola_"): w for w in m["warps"]}
    for dest, (point, _) in SHOP_DOORS.items():
        door = old[dest]
        door["at"] = list(point)
        door["alola_label"] = door["alola_label"].removeprefix(m["name"] + "・").removeprefix("好奥乐市・")
    sea = f.water.copy()
    # Quays and planted public docks edge the imported coast. The northern basin
    # remains visibly bounded and can be walked around from the central plaza.
    basins, _ = ndimage.label(sea)
    basin_areas = np.bincount(basins.ravel())
    larger_water = sea & (basin_areas[basins] >= 50)
    esplanade = ndimage.binary_dilation(larger_water, iterations=1) & ~sea
    # Coastal city blocks lie inside the imported shoreline.
    ground = ~sea
    f.layers[ground] = "grass"
    dry_blocks = f.s & ground
    f.layers[dry_blocks] = "darkgrass"
    f.layers[esplanade] = "quay"
    # The north/south commercial street branches to the beach, marina and island road.
    routes = [
        (
            [
                (45, 3),
                (45, 12),
                (40, 16),
                (39, 30),
                (40, 39),
                (52, 41),
                (60, 39),
                (76, 40),
                (86, 47),
                (94, 44),
            ],
            5,
        ),
        ([(18, 44), (30, 44), (39, 41), (44, 52), (66, 52), (78, 52), (89, 62)], 4),
        ([(46, 29), (59, 29), (76, 28), (89, 24), (101, 27)], 4),
        ([(88, 45), (92, 36), (96, 29), (101, 23)], 3),
        ([(30, 25), (30, 30), (40, 30)], 3),
        ([(43, 51), (39, 55), (35, 58), (35, 65)], 2),
        ([(21, 29), (17, 26), (16, 19), (14, 16)], 2),
    ]
    for points, width in routes:
        f.path(points, width, "cobbles")
    for dest, (point, kind) in SHOP_DOORS.items():
        x, y = point
        # A walkable sidewalk and the connected street are kept clear of clipped base mesh collisions.
        anchor = {
            "ilima_room": (43, 22),
            "hauoli_mall": (60, 29),
            "hauoli_city_hall": (41, 52),
            "hauoli_police": (76, 52),
            "photo_hauoli": (24, 44),
            "center_hauoli": (32, 30),
            "tourism_bureau": (45, 40),
            "malasada_shop": (68, 29),
        }[dest]
        f.path([(x, y), (x, y + 1), anchor], 3, "quay")
    street = np.isin(f.layers, ["quay", "cobbles"]) & ~sea
    f.s[street] = False
    # Shallow setbacks belong to the shops' pavements. Place lights on the paved strip.
    sidewalk = ndimage.binary_dilation(street, iterations=1) & ~sea & ~street
    f.layers[sidewalk] = "quay"
    f.s[sidewalk] = False
    street |= sidewalk
    for dest, (point, kind) in SHOP_DOORS.items():
        doorstep(f, dest, point, kind)
    # Native docks, public grounds, and planted courtyards supply the blocks between shop doors.
    f.layers[sea] = "water"
    mask = f.s & ~sea & ~street
    for l, t, r, b in f.landmark_rect:
        mask[max(t - 4, 0) : b + 2, max(l - 2, 0) : r + 3] = False
    # A pair of outdoor market rows and a waterfront unloading yard put visible
    # activity in the otherwise empty blocks west and east of the commercial street.
    for key, x, y in [
        ("market_canopy", 24, 28),
        ("market_canopy", 18, 25),
        ("market_goods", 23, 24),
        ("market_canopy", 83, 23),
        ("market_canopy", 91, 23),
        ("market_goods", 87, 20),
        ("market_canopy", 65, 49),
        ("market_goods", 68, 47),
        ("market_goods", 84, 54),
    ]:
        w, h = Image.open(STREETS / (key + ".png")).size
        x0 = x - w // 32
        area = [(xx, yy) for yy in range(y - h // 16 + 1, y + 1) for xx in range(x0, x0 + w // 16)]
        if any(f.water[yy, xx] or (xx, yy) in f.reserved for xx, yy in area):
            continue
        f.decor(key, x, y, [w // 2, h])
        f.s[y, x0 : x0 + w // 16] = True
        f.layers[y - 2 : y + 2, x0 - 1 : x0 + w // 16 + 1] = "quay"
        mask[y - 3 : y + 2, x0 - 1 : x0 + w // 16 + 1] = False
    # Thin rows of pavement lights, tall palms, and planters flank the avenue.
    flower_config = (
        (39, 30),
        (53, 30),
        (65, 31),
        (73, 30),
        (74, 43),
        (71, 48),
        (43, 47),
        (35, 52),
        (31, 42),
        (86, 51),
    )
    for x, y in flower_config:
        if (
            (x, y) in f.reserved
            or f.water[y, x]
            or any(l - 1 <= x <= r + 1 and t - 1 <= y <= b + 1 for l, t, r, b in f.landmark_rect)
        ):
            continue
        key = "streetlamp" if (x + y) % 3 == 0 else "planter"
        f.decor(key, x, y)
        f.s[y, x] = True
        f.layers[y, x] = "quay"
    # Blocks in the shopping district form enclosed squares with lawns, benches
    # and trimmed street trees; keep each doorway separately visible along the street.
    landmarks = [
        ("fountain", 52, 35),
        ("carebench", 49, 37),
        ("carebench", 56, 37),
        ("planter", 49, 32),
        ("planter", 55, 32),
        ("palm", 46, 34),
        ("palm", 58, 34),
        ("banner", 26, 29),
        ("banner", 34, 29),
        ("tree", 46, 20),
        ("tree", 52, 20),
        ("planter", 43, 18),
        ("planter", 52, 17),
        ("palm", 33, 48),
        ("palm", 42, 49),
        ("planter", 59, 26),
        ("planter", 63, 26),
        ("planter", 73, 51),
    ]
    for key, x, y in landmarks:
        if (x, y) in f.reserved or f.water[y, x]:
            continue
        if key == "palm":
            f.decor(key, x, y, [23, 48])
        else:
            f.decor(key, x, y)
        if key not in ("tree", "palm"):
            f.layers[y, x] = "quay"
        f.s[y, x] = True
        mask[max(0, y - 1) : y + 2, max(0, x - 1) : x + 2] = False
    for x, y in ((52, 35), (37, 52), (74, 51), (60, 25), (24, 45)):
        for xx in range(x - 3, x + 4):
            if not f.water[y, xx] and not f.s[y, xx]:
                f.layers[y, xx] = "quay"
    # Flower boxes fill three tiles and benches fill two. Preserve protected actor
    # approaches and the entire frontage, including the corners, as physical fixtures.
    for key, x, y, *_ in f.props:
        if key not in ("planter", "carebench", "fountain"):
            continue
        span = {"planter": (-1, 1), "carebench": (0, 1), "fountain": (-1, 1)}[key]
        for xx in range(x + span[0], x + span[1] + 1):
            if (xx, y) not in f.reserved:
                f.s[y, xx] = True
                f.layers[y, xx] = "quay"
                mask[max(0, y - 1) : y + 2, max(0, xx - 1) : xx + 2] = False
    f.trees(mask, palms=True)
    # Draw low kerbs beside former cliff fragments so concealed collisions have a visible boundary.
    kerb = (f.s & ~sea) & ndimage.binary_dilation(~f.s & ~sea) & ~mask
    for l, t, r, b in f.landmark_rect:
        kerb[t : b + 1, l : r + 1] = False
    f.layers[kerb & ~np.isin(f.layers, ["quay", "cobbles"])] = "darkgrass"
    f.grass &= ~street
    f.ground()
    ensure_anchors(f)
    for dest, (p, _) in SHOP_DOORS.items():
        indoor = read(MAPS / ("alola_" + dest + ".json"))
        for w in indoor["warps"]:
            if w["to"]["map"] == m["id"]:
                w["to"]["at"] = [p[0], p[1] + 1]
        write(MAPS / (indoor["id"] + ".json"), indoor)


def interiors(exterior, rows):
    atlas = Image.open(ROOT / "assets/hoenn_native/tiles.png").convert("RGBA")
    for key, title, point, kind, layout, npc, line in rows:
        src = read(ROOT / "content/hoenn_native/maps" / (layout + ".json"))
        w, h = src["size"]
        surface = Image.new("RGBA", (w * 16, h * 16), "#293539")
        for layer in ("t", "a"):
            if layer not in src["hoenn_art"]:
                continue
            ids = np.frombuffer(
                zlib.decompress(base64.b64decode(src["hoenn_art"][layer])), dtype="<u2"
            ).reshape(h, w)
            for y, x in np.argwhere(ids):
                i = int(ids[y, x])
                l = (i % 64) * 16
                t = (i // 64) * 16
                surface.alpha_composite(atlas.crop((l, t, l + 16, t + 16)), (int(x) * 16, int(y) * 16))
        surface.convert("RGB").quantize(128).save(IMAGES / (key + ".png"), optimize=True)
        entry = src["warps"][0]["at"]
        exit_y = entry[1]
        entry_x = entry[0]
        collision = src["physics"]["collision"]
        arrival = [entry_x, exit_y - 1]
        if collision[arrival[1]][arrival[0]]:
            raise ValueError((key, arrival))
        warp = {
            "at": list(point),
            "trigger": "step",
            "alola_label": title,
            "source_warp": "adapted_house",
            "to": {"region": "alola", "map": "alola_" + key, "at": arrival, "alola_native": True},
        }
        exterior["warps"].append(warp)
        room = {k: exterior[k] for k in ("region", "alola_native")}
        name = "alola_" + key
        room.update(
            id=name,
            name=title,
            size=[w, h],
            alola_zones=[],
            alola_zone=-1,
            alola_location="",
            alola_image=key,
            alola_anchors={},
            alola_center=False,
            alola_item_tiles=[],
            alola_trainer_tiles=[],
            spawn=arrival,
            allow_cycling=False,
            allow_fly=False,
            allow_running=True,
            physics={"size": [w, h], "collision": collision},
            objects=[],
            npcs=[
                {
                    "name": npc,
                    "at": src["npcs"][0]["at"],
                    "gfx": "woman" if key == "iki_south_house" else "expert_m",
                    "lines": [line],
                }
            ],
            warps=[
                {
                    "at": door["at"],
                    "trigger": "down",
                    "alola_label": exterior["name"],
                    "source_warp": "adapted_house",
                    "to": {
                        "region": "alola",
                        "map": exterior["id"],
                        "at": [point[0], point[1] + 1],
                        "alola_native": True,
                    },
                }
                for door in src["warps"]
            ],
            hoenn_art={
                "s": [w, h],
                "t": pack(np.full((h, w), K["floor"])),
                "p": [],
                "scene": ["res://assets/alola/maps/" + key + ".png", 0, 0],
            },
        )
        if key == "malasada_shop":
            room["npcs"][0].update(alola_malasada_counter=True, gfx="woman")
        write(MAPS / (name + ".json"), room)


def junctions(f):
    from alola_streets import FRONTS

    home_ids = {row[0] for row in HOMES + CIVIC_ROOMS}
    draw = ImageDraw.Draw(f.surface)
    for w in f.m["warps"]:
        dest = w["to"]["map"].removeprefix("alola_")
        if dest in FRONTS or dest in home_ids or dest.startswith("center_"):
            continue
        x, y = w["at"]
        px = x * 16
        py = y * 16
        # Inlaid threshold at the precise tile that crosses into the next named area.
        draw.rounded_rectangle(
            (px + 1, py + 8, px + 14, py + 14), radius=2, fill="#8b795b", outline="#726650"
        )
        draw.line((px + 3, py + 9, px + 12, py + 9), fill="#e2d6a7")
        draw.line((px + 4, py + 12, px + 7, py + 10, px + 10, py + 12), fill="#eadcb2", width=1)


def main(baseline=ROOT):
    source_maps = baseline / MAPS.relative_to(ROOT)
    source_images = baseline / IMAGES.relative_to(ROOT)
    ids = [
        "1",
        "2",
        "3",
        "4",
        "5",
        "6",
        "7",
        "8",
        "9",
        "10",
        "11",
        "12",
        "13",
        "14",
        "15",
        "16",
        "17",
        "mahalo",
        "iki",
        "hauoli",
    ]
    for mid in ids:
        m = read(source_maps / ("alola_" + mid + ".json"))
        f = Field(m)
        if mid == "iki":
            m["warps"] = [w for w in m["warps"] if w.get("source_warp") != "adapted_house"]
            interiors(m, HOMES)
            iki(f)
        elif mid == "hauoli":
            m["warps"] = [w for w in m["warps"] if w.get("source_warp") != "adapted_house"]
            interiors(m, CIVIC_ROOMS)
            city(f)
        else:
            # Use the actual retail-derived source image written by build_alola_maps.
            with Image.open(source_images / (mid + ".png")) as old:
                road_scene(f, old, mid)
        junctions(f)
        f.save()
    p = MAPS.parent / "region.json"
    reg = read(p)
    reg["maps"] = sorted(a.stem for a in MAPS.glob("*.json"))
    write(p, reg)


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--baseline", type=Path, default=ROOT, help="Unmodified output directory of build_alola_maps"
    )
    main(parser.parse_args().baseline)
