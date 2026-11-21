"""Tile geography for the hand-connected atlas. art_props use a bottom-centre tile anchor."""

import hashlib
import math
import random

# Terrain numbers follow World.can_enter. In particular water, trees, walls and roofs block walking.
PROFILES = {
    "grass": (0, 1, 3),
    "garden": (0, 1, 12),
    "forest": (0, 1, 3),
    "coast": (10, 2, 13),
    "city": (12, 6, 12),
    "highland": (5, 6, 3),
    "snow": (5, 6, 12),
    "cave": (5, 6, 5),
    "desert": (10, 6, 3),
    "volcano": (5, 6, 5),
    "marsh": (0, 2, 13),
    "ruins": (5, 6, 12),
    "space": (5, 2, 12),
    "interior": (13, 6, 14),
}
BIOME_EXHIBITS = {
    "grass": ("草地调查员", "短草晒过太阳，林缘留下不少宝可梦的脚印。"),
    "garden": ("园丁", "花田之间保留了供宝可梦穿过的狭道。"),
    "forest": ("护林员", "林冠遮住了光，沿着铺过的地面走就能找到出口。"),
    "coast": ("守港人", "看脚下的桩号，木栈道一直连到对岸。"),
    "city": ("街区向导", "广场边有道路指示牌，走近后调查就能看到目的地。"),
    "highland": ("登山员", "这条上山的小径沿等高线绕行，背风处适合休息。"),
    "snow": ("雪线向导", "积雪能盖住小路，石铺路面上仍能辨出方向。"),
    "cave": ("地质员", "洞壁的颜色会随岩层变化，留心分岔口的指示牌。"),
    "desert": ("沙丘向导", "跟着石堆之间的缓坡就能穿过沙地。"),
    "volcano": ("火山调查员", "岩石的深色条带，是熔岩冷却后留下的痕迹。"),
    "marsh": ("湿地观察员", "水退时露出的滩涂会变软，请从架高的木道通过。"),
    "ruins": ("遗迹研究员", "石柱的排列仍能看出原来建筑的方向。"),
    "space": ("空间观测员", "光带两侧的石台很稳定，沿着石台就能步行往返。"),
    "interior": ("接待员", "请沿参观通道前行，门口可以回到来时的街区。"),
}
# Settlement signatures are based on what travellers see there; road shape and the
# land/water silhouette remain independent of the renderer's chosen art pack.
TOWN_PLANS = {
    "quays": "slateport lilycove dewford canalave sunyshore castelia virbank undella driftveil humilau ambrette couriway hulbury hauoli konikoni seafolk marinada levincia heahea dock",
    "islets": "pacifidlog sootopolis",
    "garden": "verdanturf floaroma striaton santalune vaniville ballonlea artazon paniola turffield iki mossui",
    "citadel": "rustboro oreburgh opelucid celestic hammerlocke geosenge shalour cascarrafa pummelo stow",
    "boulevard": "jubilife nimbasa wyndon malie kiloude black_city",
    "terraces": "fortree lavaridge ever_grande snowpoint mistralton aspertia anistar lentimas montenevera alfornada",
    "circle": "lumiose mesagoza mauville central",
    "canal": "pastoria icirrus aquacorde",
}
TOWN_PLAN = {
    token: scheme for scheme, tokens in TOWN_PLANS.items() for token in tokens.split()
}
# Street furniture close enough to be recognised on entering town. Each row
# describes a composition rather than a single reused building at the centre.
PLAZAS = {
    "waterside": ("streetlamp", "planter", "banner"),
    "resort": ("fountain", "plant", "tree"),
    "garden": ("planter", "tree", "planter", "plant"),
    "monument": ("statue", "banner", "streetlamp"),
    "campus": ("statue", "planter", "planter", "banner"),
    "promenade": ("fountain", "streetlamp", "streetlamp"),
    "market": ("banner", "planter", "streetlamp"),
    "mill": ("tower", "rock", "streetlamp"),
    "beacon": ("tower", "banner", "rock"),
    "grove": ("tree", "tree", "plant"),
    "cairns": ("rock", "statue", "rock"),
    "shrine": ("statue", "tree", "rock"),
    "arena": ("banner", "statue", "banner"),
    "castle": ("tower", "banner", "statue"),
    "research": ("pc", "bookshelf", "plant"),
    "archive": ("bookshelf", "statue", "bookshelf"),
    "office": ("desk", "pc", "plant"),
}
PLACE_DETAILS = {
    "campus": "paldea/mesagoza blueberry/central blueberry/academy hoenn/devon",
    "promenade": "sinnoh/jubilife kalos/santalune hoenn/mauville galar/wyndon unova/nimbasa",
    "beacon": "kalos/lumiose alola/heahea sinnoh/sunyshore galar/hulbury paldea/cabo hoenn/mossdeep",
    "monument": "sinnoh/eterna unova/opelucid kalos/geosenge galar/stow paldea/alfornada",
    "shrine": "sinnoh/celestic alola/iki hisui/jubilife distortion/threshold paldea/ruins",
    "garden": "hoenn/verdanturf sinnoh/floaroma unova/striaton kalos/vaniville alola/malie galar/turffield paldea/artazon orange/valencia",
    "mill": "sinnoh/oreburgh sinnoh/windworks galar/motostoke unova/driftveil",
    "grove": "hoenn/fortree galar/ballonlea sinnoh/twinleaf unova/nuvema hisui/obsidian dream/village",
    "cairns": "sinnoh/veilstone hoenn/fallarbor hoenn/granite paldea/montenevera crown/freezington distortion/pillars",
    "castle": "galar/hammerlocke unova/black_city kalos/camphrier",
    "waterside": "hoenn/slateport sinnoh/canalave unova/castelia alola/hauoli paldea/levincia",
    "resort": "hoenn/sootopolis hoenn/lavaridge unova/undella kalos/aquacorde paldea/cascarrafa",
    "arena": "galar/stadium alola/royal orange/stadium sinnoh/hearthome ultra/megalopolis",
    "office": "aether/lobby blueberry/club",
    "archive": "sinnoh/library hoenn/museum paldea/academy",
}
PLACE_DETAIL = {
    key: plan for plan, keys in PLACE_DETAILS.items() for key in keys.split()
}
BIOME_DETAIL = {
    "grass": "grove",
    "forest": "grove",
    "garden": "garden",
    "city": "market",
    "coast": "waterside",
    "snow": "cairns",
    "highland": "cairns",
    "ruins": "shrine",
    "marsh": "grove",
    "cave": "cairns",
    "volcano": "cairns",
    "space": "monument",
    "desert": "cairns",
    "interior": "research",
}
PROP_SIZE = {
    "fountain": (3, 2),
    "tree": (2, 3),
    "tower": (3, 4),
    "streetlamp": (1, 2),
    "banner": (1, 2),
    "planter": (2, 1),
    "plant": (1, 1),
    "statue": (2, 2),
    "rock": (2, 1),
    "pc": (1, 2),
    "desk": (2, 1),
    "bookshelf": (2, 2),
}
ISLANDS = {"coast", "marsh", "space"}
SIDE = [(0, -1), (1, 0), (0, 1), (-1, 0)]


def stable(name):
    return int.from_bytes(hashlib.sha256(name.encode()).digest()[:6], "big")


def distance(a, b):
    return abs(a[0] - b[0]) + abs(a[1] - b[1])


class Layout:
    def __init__(self, node, neighbours):
        self.node = node
        self.rng = random.Random(stable(node["key"]))
        self.biome = node["biome"]
        self.kind = node["kind"]
        self.neighbours = neighbours
        self.fields = self.kind in ("route", "landmark", "crossing")
        self.floor, self.border, self.road = PROFILES[self.biome]
        self.width = (
            self.rng.choice([31, 35, 39])
            if self.fields
            else self.rng.choice([35, 39, 43])
        )
        self.height = (
            self.rng.choice([23, 27, 31])
            if self.fields
            else self.rng.choice([27, 31, 35])
        )
        if self.biome == "interior":
            self.width, self.height = (
                self.rng.choice([23, 27, 31]),
                self.rng.choice([17, 19, 23]),
            )
        self.hub = (
            self.width // 2 + self.rng.randint(-3, 3),
            self.height // 2 + self.rng.randint(-2, 2),
        )
        self.grid = [[self.floor] * self.width for y in range(self.height)]
        self.paths, self.occupied = set(), set()
        self.gates, self.props, self.npcs, self.objects = {}, [], [], []
        self.terrain()
        self.streets()
        self.landmark()
        self.square_details()
        self.exits()
        self.characters()

    def rect(self, x, y, w, h, t):
        for j in range(max(0, y), min(y + h, self.height)):
            for i in range(max(0, x), min(x + w, self.width)):
                self.grid[j][i] = t

    def inside(self, x, y):
        return 1 <= x < self.width - 1 and 1 <= y < self.height - 1

    def road_cell(self, x, y, width=1):
        if not self.inside(x, y):
            return
        for dy in range(width):
            nx, ny = x, y + dy
            if self.inside(nx, ny):
                self.grid[ny][nx] = self.road
                self.paths.add((nx, ny))

    def line(self, a, b, width=1):
        x, y = a
        self.road_cell(x, y, width)
        while (x, y) != b:
            if x != b[0]:
                x += 1 if x < b[0] else -1
            else:
                y += 1 if y < b[1] else -1
            self.road_cell(x, y, width)

    def ellipse(self, cx, cy, rx, ry, t, ragged=False):
        for y in range(max(1, cy - ry - 1), min(self.height - 1, cy + ry + 2)):
            for x in range(max(1, cx - rx - 1), min(self.width - 1, cx + rx + 2)):
                if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 < (
                    1 + (self.rng.random() - 0.5) * 0.5 if ragged else 1
                ):
                    self.grid[y][x] = t

    def terrain(self):
        w, h = self.width, self.height
        self.rect(0, 0, w, 1, self.border)
        self.rect(0, h - 1, w, 1, self.border)
        self.rect(0, 0, 1, h, self.border)
        self.rect(w - 1, 0, 1, h, self.border)
        if self.biome == "interior":
            self.rect(1, 1, w - 2, 2, 7)
            for y in range(4, h - 3, 5):
                for x in range(3, w - 3, 6):
                    if self.rng.random() < 0.65:
                        self.rect(x, y, 2, 2, 6)
            return
        scatter = {
            "forest": 14,
            "grass": 9,
            "garden": 10,
            "city": 4,
            "coast": 7,
            "space": 8,
            "cave": 14,
            "marsh": 13,
            "volcano": 12,
            "snow": 8,
            "ruins": 8,
            "highland": 10,
            "desert": 7,
        }
        for i in range(scatter[self.biome]):
            cx = self.rng.randrange(2, w - 2)
            cy = self.rng.randrange(2, h - 2)
            f = self.biome
            terrain = self.rng.choice(
                {
                    "forest": [1, 1, 11],
                    "grass": [1, 4, 11],
                    "garden": [4, 4, 11, 1],
                    "coast": [2, 2, 0, 5],
                    "space": [2, 2, 5],
                    "city": [0, 4],
                    "marsh": [2, 2, 11],
                    "desert": [5, 6, 10],
                    "volcano": [6, 6, 5],
                    "highland": [6, 6, 11],
                    "cave": [6, 6, 2],
                    "snow": [6, 1, 5],
                    "ruins": [6, 11, 4],
                }[f]
            )
            self.ellipse(
                cx, cy, self.rng.randint(2, 6), self.rng.randint(2, 4), terrain, True
            )
        if self.biome in ISLANDS:
            # Rivers, estuaries and floating islands each have a continuous shoreline.
            horizontal = self.rng.choice([True, False])
            breadth = w if horizontal else h
            depth = h if horizontal else w
            phase = self.rng.uniform(0, 6)
            freq = self.rng.uniform(0.12, 0.31)
            for i in range(1, breadth - 1):
                level = int(depth * 0.25 + math.sin(i * freq + phase) * depth * 0.1)
                for j in range(1, max(2, level)):
                    x, y = (i, j) if horizontal else (j, i)
                    self.grid[y][x] = 2

    def streets(self):
        cx, cy = self.hub
        if self.kind in ("city", "town"):
            pattern = TOWN_PLAN.get(
                self.node["token"],
                self.rng.choice(["market", "terraces", "boulevard", "garden"]),
            )
            if pattern == "islets":
                self.rect(1, 1, self.width - 2, self.height - 2, 2)
                for x, y in [
                    (6, 6),
                    (self.width - 7, 6),
                    (6, self.height - 6),
                    (self.width - 7, self.height - 6),
                    self.hub,
                ]:
                    self.ellipse(
                        x, y, 5, 4, 10 if self.node["token"] == "pacifidlog" else 12
                    )
                    self.line((x, y), (cx, y), 2)
                    self.line((cx, y), self.hub, 2)
            elif pattern == "quays":
                shore = self.height - 6
                self.rect(1, shore, self.width - 2, self.height - shore - 1, 2)
                self.line((2, shore - 1), (self.width - 3, shore - 1), 2)
                for x in range(5, self.width - 4, 8):
                    self.line((x, shore - 3), (x, self.height - 2), 2)
                self.line(self.hub, (cx, shore - 1), 2)
                self.line((4, cy), (self.width - 5, cy), 2)
            elif pattern == "canal":
                self.rect(cx - 4, 1, 4, self.height - 2, 2)
                self.line((cx + 1, 2), (cx + 1, self.height - 3), 2)
                for y in [cy - 4, cy + 5]:
                    self.line((3, y), (self.width - 4, y), 2)
            elif pattern == "garden":
                for x in (cx - 6, cx + 6):
                    for y in (cy - 4, cy + 4):
                        self.ellipse(x, y, 4, 2, 4)
                self.line((cx, 2), (cx, self.height - 3), 2)
                self.line((3, cy), (self.width - 4, cy), 2)
                for x in (cx - 10, cx + 10):
                    self.line((x, cy - 6), (x, cy + 6), 1)
            elif pattern == "citadel":
                for x in (cx - 8, cx + 8):
                    self.rect(x, 4, 2, cy - 1, 6)
                self.rect(cx - 8, 4, 18, 2, 6)
                self.line((cx, 3), (cx, self.height - 3), 2)
                self.line((3, cy + 3), (self.width - 4, cy + 3), 2)
            elif pattern == "circle":
                rx, ry = self.rng.randrange(4, 8), self.rng.randrange(3, 6)
                corners = [
                    (cx - rx, cy - ry),
                    (cx + rx, cy - ry),
                    (cx + rx, cy + ry),
                    (cx - rx, cy + ry),
                ]
                for j, a in enumerate(corners):
                    self.line(a, corners[(j + 1) % 4], 2)
                self.line(corners[0], (cx, cy - ry))
                self.line((cx, cy - ry), self.hub, 2)
            elif pattern == "market":
                for dy in (-4, 0, 5):
                    self.line((3, cy + dy), (self.width - 4, cy + dy), 2)
                for dx in (-5, 4):
                    self.line((cx + dx, cy - 4), (cx + dx, cy + 5), 2)
            elif pattern == "terraces":
                self.line((3, cy + 4), (self.width - 4, cy + 4), 2)
                self.line((cx - 5, cy + 4), (cx - 5, cy - 4), 2)
                self.line((cx - 5, cy - 4), (self.width - 5, cy - 4), 2)
                self.line(self.hub, (cx, cy + 4), 2)
            else:
                self.line((cx, 3), (cx, self.height - 4), 2)
                self.line((3, cy), (self.width - 4, cy), 2)
        self.rect(cx - 2, cy - 2, 5, 5, 12 if not self.fields else self.road)
        for y in range(cy - 2, cy + 3):
            for x in range(cx - 2, cx + 3):
                self.paths.add((x, y))

    def landmark(self):
        cx, cy = self.hub
        if self.biome == "interior":
            typ = (
                "bookshelf"
                if self.node["token"]
                in ("library", "museum", "academy", "devon", "club")
                else "pc"
            )
            for x in range(4, self.width - 3, 5):
                self.props.append({"kind": typ, "at": [x, 3], "size": [2, 2]})
            return
        if self.kind in ("city", "town", "facility"):
            # Town blocks follow the plaza or the quay. Keep clear alleys around them.
            corners = [
                (5, 6),
                (self.width - 7, 6),
                (6, self.height - 6),
                (self.width - 7, self.height - 6),
            ]
            self.rng.shuffle(corners)
            for i, (x, y) in enumerate(corners[: 2 if self.kind == "town" else 3]):
                wid = self.rng.choice([4, 5, 6])
                height = self.rng.choice([3, 4])
                cells = {
                    (px, py)
                    for py in range(y - height + 1, y + 1)
                    for px in range(x - wid // 2, x - wid // 2 + wid)
                }
                if cells & self.paths:
                    continue
                self.rect(x - wid // 2, y - height + 1, wid, height - 1, 7)
                self.rect(x - wid // 2, y, wid, 1, 6)
                self.occupied.update(cells)
                self.props.append(
                    {
                        "kind": ["home", "mart", "center"][i],
                        "at": [x, y],
                        "size": [wid, height],
                    }
                )
        elif self.biome in ("ruins", "space", "highland", "volcano"):
            for sign in [-1, 1]:
                x, y = cx + sign * 4, cy - 4
                self.grid[y][x] = 6
                self.occupied.add((x, y))
                self.props.append(
                    {
                        "kind": "statue"
                        if self.biome in ("ruins", "space")
                        else "rock",
                        "at": [x, y],
                        "size": [1, 2],
                    }
                )

    def square_details(self):
        if self.kind in ("route", "crossing"):
            return
        cx, cy = self.hub
        key = self.node["key"]
        scheme = PLACE_DETAIL.get(key, BIOME_DETAIL[self.biome])
        if self.kind == "facility" and self.node["token"] == "league":
            scheme = "arena"
        elif self.biome == "interior" and key not in PLACE_DETAIL:
            scheme = (
                "archive"
                if self.node["token"] in ("museum", "library", "manor")
                else "office"
                if self.node["token"] in ("studio", "hotel", "club", "mansion")
                else "research"
            )
        # Mark the ground in front of the landmarks; this also leaves open space
        # to either side of their collision footprints in dense forests and caves.
        for y in range(cy - 3, cy + 5):
            for x in range(cx - 5, cx + 6):
                if (x, y) in self.occupied:
                    continue
                if self.kind in ("town", "city", "facility"):
                    surface = (
                        13
                        if self.biome == "coast"
                        else 14
                        if self.biome == "interior"
                        else 12
                    )
                else:
                    surface = self.road
                self.grid[y][x] = surface
        # Keep a dry approach to each NPC and the navigator. Props can stand on
        # the outer paving, but the central five-tile square is always clear.
        protected = {
            (x, y) for y in range(cy - 2, cy + 3) for x in range(cx - 2, cx + 3)
        }
        flipped = -1 if stable(key + "square") % 2 else 1
        offsets = [
            (-3 * flipped, -1),
            (4 * flipped, 2),
            (2 * flipped, -3),
            (-4 * flipped, 3),
        ]
        if key == "paldea/mesagoza":
            offsets = [(0, -3), (-4, 2), (4, 2), (4, -3)]
        elif key == "sinnoh/jubilife":
            offsets = [(-3, -1), (3, 1), (3, -3)]
        for kind, (dx, dy) in zip(PLAZAS[scheme], offsets):
            w, h = PROP_SIZE[kind]
            x, y = cx + dx, cy + dy
            left = x - w // 2
            footprint = {
                (ix, iy)
                for iy in range(y - h + 1, y + 1)
                for ix in range(left, left + w)
            }
            if footprint & (protected | self.occupied):
                # Nudge away from the plaza on the right when an even-sized
                # sprite straddles the protected inner court.
                offset = 1 if dx >= 0 else -1
                x += offset
                left += offset
                footprint = {(ix + offset, iy) for ix, iy in footprint}
            if footprint & (protected | self.occupied) or not all(
                self.inside(*v) for v in footprint
            ):
                continue
            self.rect(left, y - h + 1, w, h, 6)
            self.paths.difference_update(footprint)
            self.occupied.update(footprint)
            self.props.append({"kind": kind, "at": [x, y], "size": [w, h]})

    def exits(self):
        w, h = self.width, self.height
        slots = []
        for side in range(4):
            for fraction in (0.25, 0.5, 0.75):
                x, y = [
                    (int(w * fraction), 0),
                    (w - 1, int(h * fraction)),
                    (int(w * fraction), h - 1),
                    (0, int(h * fraction)),
                ][side]
                slots.append((side, x, y))
        for key, target, angle, target_kind, target_biome in self.neighbours:
            is_door = target_biome == "interior" or (
                target_kind == "facility" and self.kind in ("city", "town")
            )
            if (
                self.biome != "interior"
                and is_door
                and self.building_entrance(key, target)
            ):
                continue
            # Prefer the direction of the neighbouring location on the region map.
            dx, dy = math.cos(angle), math.sin(angle)
            available = [
                s
                for s in slots
                if all(
                    (s[1] - SIDE[s[0]][0] * n, s[2] - SIDE[s[0]][1] * n)
                    not in self.occupied
                    for n in (1, 2, 3)
                )
            ]
            side, x, y = min(
                available,
                key=lambda s: (
                    -(SIDE[s[0]][0] * dx + SIDE[s[0]][1] * dy)
                    + 0.003 * distance((s[1], s[2]), self.hub)
                ),
            )
            slots.remove((side, x, y))
            sx, sy = SIDE[side]
            entry = (x - sx, y - sy)
            inside = (x - sx * 3, y - sy * 3)
            self.carve_to(inside)
            self.line(inside, entry, 1)
            self.grid[y][x] = 8
            self.occupied.add((x, y))
            self.gates[key] = ([x, y], list(entry))
            # Signposts stand beside the entrance and can be read from the route.
            sign = (inside[0] + sy, inside[1] + sx)
            if (
                self.inside(*sign)
                and sign not in self.occupied
                and sign not in self.paths
            ):
                self.grid[sign[1]][sign[0]] = 6
                self.objects.append(
                    {"kind": "sign", "at": list(sign), "text": f"前往{target}。"}
                )
                self.occupied.add(sign)
        # The pathfinder treats house footprints and signs as solid. Matching the actual
        # tile here prevents decorative buildings or labels from obstructing a shortcut.

    def building_entrance(self, key, title):
        """Place the exit on a building footprint and link its front pavement to the town."""
        w, h = self.width, self.height
        candidates = [(x, y) for y in range(5, h - 4) for x in range(4, w - 4)]
        self.rng.shuffle(candidates)
        for x, y in candidates:
            area = {(i, j) for i in range(x - 2, x + 3) for j in range(y - 2, y + 1)}
            approach = (x, y + 1)
            if area & (self.paths | self.occupied) or approach in self.occupied:
                continue
            if self.grid[y][x] == 2 and self.biome not in ISLANDS:
                continue
            self.rect(x - 2, y - 2, 5, 2, 7)
            self.rect(x - 2, y, 5, 1, 6)
            self.grid[y][x] = 8
            self.occupied.update(area)
            token = key.split("/")[-1]
            prop = (
                "tower"
                if token in ("tower", "lighthouse", "rose", "mastery")
                else "gym"
                if token in ("league", "dojo", "stadium", "club")
                else "lab"
            )
            self.props.append({"kind": prop, "at": [x, y], "size": [5, 3]})
            self.carve_to(approach)
            self.gates[key] = ([x, y], list(approach))
            sign = (x + 3, y)
            if (
                self.inside(*sign)
                and sign not in self.paths
                and sign not in self.occupied
            ):
                self.grid[sign[1]][sign[0]] = 6
                self.objects.append(
                    {"kind": "sign", "at": list(sign), "text": title + "入口"}
                )
                self.occupied.add(sign)
            return True
        return False

    def carve_to(self, target):
        # Search the actual map. Prefer existing roads and passable ground; bridges
        # may cross water but never cut through the footprint of a building or statue.
        import heapq

        start = self.hub
        prev = {start: None}
        cost = {start: 0}
        front = [(0, start)]
        while front:
            total, p = heapq.heappop(front)
            if total != cost[p]:
                continue
            if p == target:
                break
            for dx, dy in SIDE:
                x, y = p[0] + dx, p[1] + dy
                n = (x, y)
                if not self.inside(x, y) or n in self.occupied:
                    continue
                tile = self.grid[y][x]
                extra = 1 if n in self.paths else 3 if tile not in (1, 2, 6, 7) else 5
                nc = total + extra
                if nc < cost.get(n, 10**9):
                    cost[n] = nc
                    prev[n] = p
                    heapq.heappush(front, (nc, n))
        if target not in prev:
            raise ValueError(f"{self.node['key']}: building covers entrance {target}")
        p = target
        while p != start:
            self.road_cell(*p)
            p = prev[p]

    def characters(self):
        cx, cy = self.hub
        who, theme = BIOME_EXHIBITS[self.biome]
        self.npcs.append(
            {
                "at": [cx - 1, cy - 1],
                "name": who,
                "gfx": "scientist"
                if self.biome in ("cave", "space", "interior")
                else "lass",
                "lines": [self.node["blurb"] or theme],
            }
        )
        if self.kind in ("city", "town"):
            self.npcs.append(
                {"at": [cx + 2, cy - 1], "name": "护士", "gfx": "nurse", "heal": True}
            )
            self.npcs.append(
                {"at": [cx - 2, cy + 1], "name": "补给商", "gfx": "clerk", "shop": True}
            )

    def output(self, region):
        data = {
            "name": self.node["name"],
            "size": [self.width, self.height],
            "tiles": self.grid,
            "spawn": list(self.hub),
            "biome": self.biome,
            "style": self.node["kind"],
            "landmark": self.node["token"],
            "art_props": self.props,
            "npcs": self.npcs,
            "objects": self.objects,
            "warps": [],
        }
        if self.fields and self.biome not in ("interior", "space"):
            pool = region.get("encounters", [])
            if pool and any(11 in row for row in self.grid):
                data["encounters"] = pool
                data["encounter_rate"] = 0.09
        return data
