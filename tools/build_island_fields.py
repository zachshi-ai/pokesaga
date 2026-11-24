"""Draw Alola's remaining fields and the expansion islands at Emerald's 16px walking scale.

Read a clean terrain export using --source; IDs, door pairs, encounters and story anchors
come from those records. Art and walkability are verified together before any file is saved.
"""

import argparse
import hashlib
import json
from functools import lru_cache
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
from scipy.sparse import csr_matrix
from scipy.sparse.csgraph import dijkstra

from alola_melemele import CATALOG, STREETS, cell, pack
from alola_streets import FRONTS
import island_architecture as architecture
import island_scenery as scenery
import island_special_spaces as special
from island_landmark_art import ART, make
from island_places import ALOLA, EXPEDITIONS, parse
import alola_route1_coast
from kalos_gym_rooms import sprite

ROOT = Path(__file__).resolve().parents[1]
MAPS = Path("content/regions")
FIELD = ROOT / "assets/emerald/field"
OUTPUT = ROOT / "assets/expedition_fields"
P = 16


def site_seed(name):
    return int.from_bytes(hashlib.sha256(name.encode()).digest()[:4], "big")


NATURAL = {
    "grassland forest forestdell rainforest bamboo orchard wildflowers garden ranch": "grass",
    "wetlands lagoon harbour surfbeach coast beach headland basaltshore promenade floatvillage": "sand",
    "basalt volcano ravine coppercliff gorge upland cavern ferncave mine deepcave tidalcave caldera": "rockfloor",
    "alpine glacier icecave snowtown": "snow",
    "dunes dustbowl": "sand",
    "graves ruinsvillage sanctuary": "grass",
    "westerntown": "ground",
    "oldtown festival terrace": "cobbles",
    "suntemple earthtemple moontemple sunlake moonlake": "stone",
    "vortexfield abyss floatingfall powerland prismcity prismtower": "rockfloor",
    "derelictstreet": "cobbles",
}
ROOMS = {
    "laboratory cleanroom gallery conservatory civic campus studio": "clinic",
    "manor nursery living study atelier dining beachlodge roadside desertlodge resort": "wood",
    "market warehouse derelict castle throne switchwing warpwing": "pave",
    "summit crystalhall earthcourt skycourt mooncourt royalcourt dojo": "tiles",
}
MATERIAL = {s: mat for group, mat in (NATURAL | ROOMS).items() for s in group.split()}
INTERIORS = {s for group in ROOMS for s in group.split()}
WOODS = set(
    "forest forestdell rainforest orchard bamboo wildflowers grassland garden conservatory ranch wetlands".split()
)
COAST = set(
    "coast beach surfbeach lagoon harbour basaltshore headland floatvillage sunlake moonlake".split()
)
SPACE = set("abyss vortexfield floatingfall powerland prismtower prismcity".split())
TOWNS = set(
    "oldtown festival westerntown derelictstreet ruinsvillage harbour promenade terrace floatvillage snowtown prismcity".split()
)
SHRINES = set("earthtemple moontemple suntemple sanctuary".split())
COURTS = set("royalcourt dojo skycourt mooncourt earthcourt summit".split())
PALETTES = {
    "volcano": ("#a75d4b", "#d48c5b"),
    "caldera": ("#9a5347", "#e4a16b"),
    "coppercliff": ("#a67d68", "#dbb687"),
    "alpine": ("#9dbcc7", "#e2ebdf"),
    "glacier": ("#93b5cb", "#e3f0e7"),
    "icecave": ("#648c9d", "#b8dae1"),
    "abyss": ("#584d84", "#9985b5"),
    "vortexfield": ("#494b77", "#9c91bf"),
    "prismcity": ("#4c617a", "#9abfc1"),
    "powerland": ("#374457", "#96a8b2"),
    "prismtower": ("#535977", "#af96c0"),
    "floatingfall": ("#535878", "#94b5bb"),
    "deepcave": ("#605370", "#b1a1a6"),
    "dustbowl": ("#b69569", "#debe91"),
}
UNTOUCHED = {str(n) for n in range(1, 18)} | set(
    "home iki hauoli mahalo hala_house iki_west_house iki_east_house iki_south_house tourism_bureau malasada_shop sandy_cave".split()
)
ALIASES = {"palm": STREETS / "palm.png"}


def load(p):
    return json.loads(p.read_bytes())


def write(p, m):
    p.write_text(json.dumps(m, ensure_ascii=False, separators=(",", ":")) + "\n")


@lru_cache(None)
def prop(key):
    if key in ALIASES:
        im = Image.open(ALIASES[key]).convert("RGBA")
        return (
            "res://" + ALIASES[key].relative_to(ROOT).as_posix(),
            (im.width // 2, im.height),
            im,
        )
    if (FIELD / (key + ".png")).exists():
        im = sprite(key)
        return key, tuple(CATALOG[key]), im
    im = make(key)
    dest = ART / (key + ".png")
    dest.parent.mkdir(exist_ok=True)
    im.save(dest, optimize=True)
    return "res://" + dest.relative_to(ROOT).as_posix(), (im.width // 2, im.height), im


@lru_cache(None)
def chip(key, style):
    im = cell(key).convert("RGB")
    if style in PALETTES and key in (
        "rockfloor",
        "rock",
        "stone",
        "cliff",
        "pave",
        "snow",
        "ice",
        "sand",
    ):
        shadow, light = PALETTES[style]
        from PIL import ImageOps

        toned = ImageOps.colorize(ImageOps.grayscale(im), shadow, light)
        im = Image.blend(im, toned, 0.65 if style in SPACE else 0.46)
    return im


def mask_line(shape, points, width):
    im = Image.new("1", (shape[1], shape[0]))
    d = ImageDraw.Draw(im)
    d.line(points, fill=1, width=width, joint="curve")
    return np.asarray(im, bool)


class Field:
    def __init__(self, m, mid, style, features, arrivals):
        self.m, self.mid, self.style, self.features = m, mid, style, features
        self.w, self.h = m["size"]
        self.native = "alola_image" in m
        self.salt = site_seed(mid)
        self.y, self.x = np.indices((self.h, self.w))
        if self.native:
            phys = m["physics"]
            self.s = np.array(phys["collision"], bool)
            self.water = np.array(phys.get("water", np.zeros_like(self.s)), bool)
            self.grass = np.array(phys.get("grass", np.zeros_like(self.s)), bool)
        else:
            g = np.asarray(m["tiles"])
            self.s = np.isin(g, [1, 6, 7])
            self.water = g == 2
            self.grass = g == 11
        self.spawn = tuple(m["spawn"])
        self.story = tuple(m.get("alola_anchors", {}).get("story", m["spawn"]))
        self.door = {tuple(e["at"]) for e in m["warps"]}
        self.npcs = {tuple(e["at"]) for e in m.get("npcs", [])}
        self.entries = {tuple(v) for v in arrivals}
        self.interactions = set(tuple(v) for v in m.get("alola_anchors", {}).values())
        for e in (
            m.get("objects", [])
            + m.get("alola_item_tiles", [])
            + m.get("alola_trainer_tiles", [])
        ):
            if "at" in e:
                self.interactions.add(tuple(e["at"]))
        self.reserved = (
            self.door | self.npcs | self.interactions | self.entries | {self.spawn}
        )
        if self.native:
            self.reserved.update(scenery.edition_points().get(m["id"], set()))
            if mid in special.PLANS:
                _, trail, loop = special.PLANS[mid]
                self.reserved.update(trail[1:] + loop[1:])
        self.props = []
        self.occupied = np.zeros_like(self.s)
        self.land = np.full(self.s.shape, MATERIAL[style], object)
        self.route = np.zeros_like(self.s)
        self.drifts = np.sin(self.x * 0.23 + np.cos(self.y * 0.14) * 1.4) + np.sin(
            self.y * 0.19 - self.x * 0.055 + self.salt % 18
        )
        self.blocked_objects = self.npcs | self.door

    def walkable(self):
        grid = ~(self.s | self.water)
        for x, y in self.blocked_objects:
            if 0 <= x < self.w and 0 <= y < self.h:
                grid[y, x] = False
        return grid

    def limits(self):
        labels, _ = ndimage.label(self.walkable())
        x, y = self.spawn
        group = labels[y, x]
        return (labels == group) if group else np.zeros_like(self.s)

    def accessible(self):
        area = self.limits()
        if any(not area[y, x] for x, y in self.entries):
            return False
        nearby = ndimage.binary_dilation(area)
        return all(nearby[y, x] for x, y in self.reserved)

    def carve_expansion(self):
        # Place coastlines, high ground and paths in each site's own orientation, then connect its
        # existing map edges. This removes the older central rectangles used by the world atlas.
        h, w = self.h, self.w
        style = self.style
        self.s[:] = False
        self.water[:] = False
        pad = self.drifts
        u = self.x / (w - 1)
        v = self.y / (h - 1)
        if style in COAST | {
            "wetlands",
            "garden",
            "conservatory",
            "floatingfall",
            "vortexfield",
            "abyss",
        }:
            if style in {
                "lagoon",
                "wetlands",
                "garden",
                "conservatory",
                "sunlake",
                "moonlake",
                "floatingfall",
            }:
                self.water[:] = ((u - 0.68 - 0.12 * np.sin(6 * v)) / 0.27) ** 2 + (
                    (v - 0.40) / 0.40
                ) ** 2 < 1
                if style in {"wetlands", "floatingfall"}:
                    self.water |= abs(u - 0.29 - 0.17 * np.sin(6 * v)) < 0.10
            elif style in {"vortexfield", "abyss"}:
                self.s[:] = abs(u - 0.50) * 1.3 + abs(v - 0.5) > 0.72 + 0.11 * pad
            else:
                self.water[:] = (v > 0.59 + 0.14 * np.sin(u * 6 + self.salt % 6)) | (
                    u < 0.11 + 0.05 * np.cos(6 * v)
                )
        elif style in INTERIORS:
            self.s[:] = (u < 0.065) | (u > 0.94) | (v < 0.12) | (v > 0.95)
            if style in COURTS:
                self.s |= (abs(u - 0.5) + abs(v - 0.5) * 0.8) > 0.72
            else:
                self.s |= (v < 0.25) & ((u < 0.22) | (u > 0.79))
        elif style in {
            "cavern",
            "ravine",
            "glacier",
            "alpine",
            "caldera",
            "volcano",
            "coppercliff",
            "sanctuary",
            "earthtemple",
            "moontemple",
        }:
            self.s[:] = ((abs(u - 0.5) * 1.25 + abs(v - 0.5)) > 0.73 + 0.12 * pad) | (
                (pad > 1.45) & (abs(u - 0.5) > 0.21)
            )
        else:
            self.s[:] = ((pad > 1.04) & (abs(v - 0.5) > 0.22)) | (
                (u < 0.18) & (v > 0.65)
            )
        self.s[[0, -1], :] = True
        self.s[:, [0, -1]] = True
        self.s[self.water] = False
        # Vary the route's side of the landmark. The exits stay at their registered return points.
        sx, sy = self.spawn
        for x, y in sorted(self.reserved):
            if (x, y) == self.spawn:
                continue
            bend = (round(x * 0.40 + sx * 0.60), round(sy * 0.35 + y * 0.65))
            if abs(x - sx) > abs(y - sy):
                bend = (round(x * 0.55 + sx * 0.45), sy)
            elif self.salt % 2:
                bend = (sx, round(y * 0.65 + sy * 0.35))
            passage = mask_line(self.s.shape, [self.spawn, bend, (x, y)], 3)
            self.water[passage] = False
            self.s[passage] = False
            if (x, y) in self.door:
                self.route |= passage
        self.grass &= ~(self.water | self.s | self.route)
        if not self.accessible():
            raise ValueError((self.mid, "disconnected revised landscape"))

    def trails(self):
        # Dijkstra on the actual connected ground. Walks to all doors share the same trunk and skirt grass.
        walk = ~(self.s | self.water)
        if not walk.any():
            return
        w, h = self.w, self.h
        cost = (
            1
            + np.maximum(0, 2.3 - ndimage.distance_transform_edt(walk)) * 0.65
            + self.grass * 4
        )
        indices = np.arange(w * h).reshape(h, w)
        edges = []
        ends = []
        prices = []
        for a, b in [
            ((slice(None, -1), slice(None)), (slice(1, None), slice(None))),
            ((slice(None), slice(None, -1)), (slice(None), slice(1, None))),
        ]:
            ok = walk[a] & walk[b]
            ids, ids2 = indices[a][ok], indices[b][ok]
            edges.extend([ids, ids2])
            ends.extend([ids2, ids])
            values = (cost[a][ok] + cost[b][ok]) * 0.5
            prices.extend([values, values])
        graph = csr_matrix(
            (np.concatenate(prices), (np.concatenate(edges), np.concatenate(ends))),
            shape=(w * h, w * h),
        )
        start = self.spawn[1] * w + self.spawn[0]
        _, parents = dijkstra(graph, indices=start, return_predecessors=True)
        track = np.zeros_like(walk)
        for x, y in self.door | {self.story}:
            idx = y * w + x
            while idx != -9999 and not track.flat[idx]:
                track.flat[idx] = True
                idx = int(parents[idx])
        self.route |= ndimage.binary_dilation(track, iterations=1) & walk
        self.route &= walk

    def place(self, key, where, max_shift=7, scenic=False):
        asset, anchor, img = prop(key)
        x, y = where
        # Artist's anchor is the object's baseline. Furniture owns its wall/floor footprint
        # and its door approaches and NPC standpoints remain reachable on the new map.
        half = max(0, (img.width - 7) // 32)
        depth = max(1, min(3, (img.height + 14) // 32))
        coords = [
            (abs(xx - x) + abs(yy - y), int(self.route[yy, xx]), xx, yy)
            for yy in range(
                max(depth - 1, y - max_shift), min(self.h, y + max_shift + 1)
            )
            for xx in range(
                max(half, x - max_shift), min(self.w - half, x + max_shift + 1)
            )
        ]
        coords.sort(key=lambda t: (t[0] + t[1] * 3, t[1], t[3], t[2]))
        for _, _, xx, yy in coords:
            patch = (slice(yy - depth + 1, yy + 1), slice(xx - half, xx + half + 1))
            if self.occupied[patch].any() or self.water[patch].any():
                continue
            if scenic and not self.s[patch].all():
                continue
            footprint = {
                (i, j)
                for i in range(xx - half, xx + half + 1)
                for j in range(yy - depth + 1, yy + 1)
            }
            if footprint & self.reserved:
                continue
            old = self.s[patch].copy()
            if not old.all():
                self.s[patch] = True
                if not self.accessible():
                    self.s[patch] = old
                    continue
            self.occupied[
                max(0, yy - depth) : yy + 2, max(0, xx - half - 1) : xx + half + 2
            ] = True
            self.props.append([asset, xx, yy, list(anchor)])
            return (xx, yy)
        return None

    def scatter(self):
        # Trunks and mineral outcrops are only planted on existing solid ground.
        st = self.style
        if st in INTERIORS or st in TOWNS or st in SHRINES:
            return
        dense = st in WOODS
        key = (
            "palm"
            if st in COAST
            else "bamboo"
            if st == "bamboo"
            else "berry_tree"
            if st == "orchard"
            else "tree"
            if dense
            else "ice_shard"
            if st in {"alpine", "glacier", "icecave"}
            else "amethyst"
            if st in SPACE
            else "boulder"
        )
        eligible = self.s & ndimage.binary_dilation(~self.s & ~self.water, iterations=4)
        if st in WOODS:
            eligible |= self.s & (self.drifts > -0.5)
        step = 3 if dense else 6
        for y in range(2, self.h, step):
            for x in range(1 + (y // step) % 2, self.w, step):
                if not eligible[y, x] or (x * 23 + y * 17 + self.salt) % 7 < 2:
                    continue
                self.place(key, (x, y), 1, scenic=True)

    def art(self):
        st = self.style
        dry = ~self.water
        if st in INTERIORS:
            self.land[self.s] = "wall"
            self.land[self.s & np.roll(~self.s, -1, axis=0)] = "wallcap"
            self.land[self.route & ~self.s] = (
                "wood" if st in {"dojo", "living", "nursery", "atelier"} else "stone"
            )
        else:
            cliffs = self.s & ndimage.binary_dilation(~self.s & dry, iterations=1)
            self.land[self.s] = "darkgrass" if st in WOODS | TOWNS else "rock"
            self.land[cliffs] = "verge" if st in WOODS | {"westerntown"} else "cliff"
            if st in WOODS:
                self.land[(self.drifts > 1.32) & ~self.s] = (
                    "flowers" if st in {"wildflowers", "garden", "orchard"} else "verge"
                )
            if st in COAST:
                self.land[(ndimage.distance_transform_edt(dry) > 4) & ~self.s] = (
                    "grass"
                    if st not in {"basaltshore", "sunlake", "moonlake", "harbour"}
                    else "rockfloor"
                    if st == "basaltshore"
                    else "stone"
                )
            if st in {"alpine", "glacier", "icecave"}:
                self.land[(self.drifts > 1.03) & ~self.s] = "ice"
            if st in {"volcano", "basalt", "caldera", "basaltshore"}:
                self.land[(self.drifts > 0.45) & ~self.s] = "volcanic"
            if st in SPACE:
                self.land[(self.drifts > 0.6) & ~self.s] = "rockfloor"
            if st in {"graves", "oldtown", "festival", "ruinsvillage"}:
                self.land[(self.drifts > 0.9) & ~self.s] = "cobbles"
            self.land[self.route & ~self.s] = (
                "path"
                if st in WOODS | {"upland", "westerntown", "grassland", "graves"}
                else "quay"
                if st in TOWNS
                else "stone"
                if st in SHRINES | SPACE
                else MATERIAL[st]
            )
        path = self.land == "path"
        pad = np.pad(path, 1, constant_values=True)
        dx = np.where(~pad[1:-1, :-2], 0, np.where(~pad[1:-1, 2:], 2, 1))
        dy = np.where(~pad[:-2, 1:-1], 0, np.where(~pad[2:, 1:-1], 2, 1))
        self.land[path] = np.char.add(
            np.char.add("trail_", dy[path].astype(str)), dx[path].astype(str)
        )
        # The original encounter data marks caves, sand and underwater fields with the
        # same encounter bit as long grass. Keep the encounter behaviour and use terrain-specific art.
        if st in WOODS | TOWNS | {"grassland", "headland", "upland"}:
            self.land[self.grass & ~self.s] = "tall"
        else:
            self.land[self.grass & ~self.s] = MATERIAL[st]
        pad = np.pad(dry, 1)
        edges = (
            pad[:-2, 1:-1].astype(int)
            + 2 * pad[2:, 1:-1]
            + 4 * pad[1:-1, :-2]
            + 8 * pad[1:-1, 2:]
        )
        for mask in range(16):
            self.land[self.water & (edges == mask)] = "shore_" + str(mask)
        pixels = np.empty((self.h, P, self.w, P, 3), np.uint8)
        grid = pixels.transpose(0, 2, 1, 3, 4)
        for mat in np.unique(self.land):
            grid[self.land == mat] = np.asarray(chip(str(mat), st))
        # An object blocks movement at its base but sits on the surrounding floor.
        # Painting these new footprints as walls created small rectangles under every bench.
        grid[self.s & ~self.terrain_solid] = np.asarray(chip(MATERIAL[st], st))
        scenery.flower_meadow(self, grid)
        architecture.room_floor(self, grid)
        if st in architecture.CAVES:
            architecture.rocky_edges(self, grid)
        return Image.fromarray(pixels.reshape(self.h * P, self.w * P, 3))

    def survey(self, source):
        self.offmap = np.zeros_like(self.s)
        self.seascape = np.zeros_like(self.s)
        if not self.native:
            return
        p = source / "assets/alola/maps" / (self.m["alola_image"] + ".png")
        if not p.exists():
            return
        with Image.open(p) as img:
            raw = np.asarray(
                img.convert("RGB").resize((self.w, self.h), Image.Resampling.BOX), int
            )
        r, g, b = raw.transpose(2, 0, 1)
        border = np.zeros_like(self.s)
        border[[0, -1], :] = True
        border[:, [0, -1]] = True
        night = self.s & (r < 48) & (g < 58) & (b < 61) & (abs(r - g) < 16)
        self.offmap = ndimage.binary_propagation(border & night, mask=night)
        # Non-surfable offshore water and the rocky horizon are visibly outside the land.
        if self.style in COAST | TOWNS | WOODS:
            sea = self.s & (b > r * 1.36) & (b > g * 1.06)
            self.seascape = ndimage.binary_propagation(
                sea & (border | ndimage.binary_dilation(self.water)), mask=sea
            )
        dry = ~(self.s | self.water)
        if self.style in WOODS | TOWNS | {"promenade", "headland", "upland"}:
            paving = dry & (r > g * 0.96) & (r > b * 1.18) & (g > b * 1.04) & (r > 105)
            self.route |= ndimage.binary_opening(paving)
        self.survey_rgb = raw

    def draw_relief(self, image):
        st = self.style
        pix = np.asarray(image).copy().reshape(self.h, P, self.w, P, 3)
        grid = pix.transpose(0, 2, 1, 3, 4)
        grid[self.seascape] = np.asarray(chip("shore_0", st))
        if self.offmap.any():
            color = "#26323a" if st not in SPACE else "#2b2944"
            void = np.full((P, P, 3), tuple(bytes.fromhex(color[1:])), np.uint8)
            grid[self.offmap] = void
        if self.native and st not in INTERIORS and st not in TOWNS:
            r, g, b = self.survey_rgb.transpose(2, 0, 1)
            rockface = (
                self.terrain_solid
                & ~(self.seascape | self.offmap)
                & (r > g * 1.04)
                & (g > b * 1.07)
            )
            # Outline contour lines inside mountains using changes of the original surveyed relief.
            bands = np.floor((r * 0.35 + g * 0.48 + b * 0.17) / 29)
            tier = rockface & (bands > np.roll(bands, -1, axis=0)) & ~self.occupied
            grid[tier] = np.asarray(chip("cliff", st))
        image = Image.fromarray(pix.reshape(self.h * P, self.w * P, 3))
        d = ImageDraw.Draw(image)
        if st in INTERIORS:
            # Draw a plinth and frieze along each irregular northern wall, following accessible floor.
            floor = ~self.s & ~self.water
            edge = floor & np.roll(self.terrain_solid, 1, axis=0)
            edge[0] = False
            for y, x in np.argwhere(edge):
                if self.offmap[y - 1, x]:
                    continue
                for off, c in [(0, "#625a65"), (2, "#aaa18e"), (3, "#d8c8a8")]:
                    d.line((x * P, y * P + off, (x + 1) * P - 1, y * P + off), fill=c)
        return image

    def walkway(self, image):
        st = self.style
        # Scene-specific light, paint and flooring use flat overlays. They do not change collision.
        sx, sy = self.story
        cx, cy = (sx + 0.5) * P, (sy + 0.5) * P
        d = ImageDraw.Draw(image)

        def centreline(points, color, width):
            d.line(points, fill=color, width=width, joint="curve")

        def circ(radius, fill, outline, width):
            d.ellipse(
                (cx - radius, cy - radius, cx + radius, cy + radius),
                fill=fill,
                outline=outline,
                width=width,
            )

        if st in COURTS | SHRINES | {"prismtower", "powerland", "vortexfield"}:
            # Clip inlaid floor art to contiguous, traversable surface; no halos across a wall or pond.
            old = image.copy()
            rad = min(60, max(30, min(self.w, self.h) * 3))
            if st == "dojo":
                d.rounded_rectangle(
                    (cx - rad, cy - rad * 0.67, cx + rad, cy + rad * 0.67),
                    4,
                    fill="#bca47e",
                    outline="#8b705b",
                    width=4,
                )
                for xx in range(-int(rad) + 8, int(rad) - 6, 12):
                    centreline(
                        [(cx + xx, cy - rad * 0.62), (cx + xx, cy + rad * 0.62)],
                        "#a88f70",
                        1,
                    )
                d.rectangle(
                    (cx - 24, cy - 16, cx + 24, cy + 16), outline="#d6c099", width=2
                )
            elif st == "royalcourt":
                points = [
                    (cx, cy - rad),
                    (cx + rad, cy),
                    (cx, cy + rad),
                    (cx - rad, cy),
                ]
                for i, c in enumerate(["#a97270", "#bba866", "#699b9a", "#7191aa"]):
                    d.polygon(
                        [(cx, cy), points[i], points[(i + 1) % 4]],
                        fill=c,
                        outline="#ddcca7",
                    )
                circ(13, None, "#eee2be", 3)
            elif st in {"earthcourt", "earthtemple"}:
                for radius, c in [
                    (rad, "#867569"),
                    (rad - 5, "#c6aa7c"),
                    (rad - 11, "#977c69"),
                ]:
                    pts = [
                        (
                            cx + radius * np.cos(i * np.pi / 3),
                            cy + radius * 0.75 * np.sin(i * np.pi / 3),
                        )
                        for i in range(6)
                    ]
                    centreline([*pts, pts[0]], c, 3)
            elif st == "skycourt":
                for dx in (-1, 1):
                    for band in (0, 9, 18):
                        points = [
                            (cx + dx * 6, cy + 26 - band),
                            (cx + dx * 23, cy + 8 - band),
                            (cx + dx * rad, cy - 22 - band),
                            (cx + dx * 29, cy + 9 - band),
                        ]
                        d.polygon(points, fill="#93b7b9", outline="#dcdfc4")
            elif st in {"moontemple", "mooncourt"}:
                circ(rad - 5, "#77748c", "#a9a4ba", 3)
                for r in (rad - 10, rad - 18):
                    d.arc(
                        (cx - r, cy - r * 0.82, cx + r, cy + r * 0.82),
                        36,
                        300,
                        fill="#d2c5b1",
                        width=3,
                    )
                for dx, dy in ((-15, -14), (5, 2), (23, -13), (22, 16)):
                    d.polygon(
                        [
                            (cx + dx, cy + dy - 4),
                            (cx + dx + 4, cy + dy),
                            (cx + dx, cy + dy + 4),
                            (cx + dx - 4, cy + dy),
                        ],
                        fill="#e1d3bb",
                    )
            else:
                tint = "#97c9c3" if st in SPACE else "#dec189"
                for radius in (rad, rad - 7, rad // 2):
                    circ(radius, None, tint, 2)
                for i in range(12 if st not in SPACE else 6):
                    a = i * np.pi / (6 if st not in SPACE else 3)
                    centreline(
                        [
                            (cx + (rad - 6) * np.cos(a), cy + (rad - 6) * np.sin(a)),
                            (cx + (rad + 3) * np.cos(a), cy + (rad + 3) * np.sin(a)),
                        ],
                        tint,
                        2,
                    )
            mask = Image.fromarray(
                ((~self.s & ~self.water & ~self.grass) * 255).astype("uint8")
            ).resize(image.size, Image.Resampling.NEAREST)
            image = Image.composite(image, old, mask)
        if st in {
            "market",
            "laboratory",
            "campus",
            "oldtown",
            "westerntown",
            "festival",
            "harbour",
            "manor",
            "castle",
            "cleanroom",
            "gallery",
            "study",
            "switchwing",
            "warpwing",
        }:
            d = ImageDraw.Draw(image)
            floor = self.route & ~(self.s | self.water)
            border = floor & ~ndimage.binary_erosion(floor)
            for y, x in np.argwhere(border):
                if y and floor[y - 1, x]:
                    continue
                color = (
                    "#ad9f8c" if st not in {"laboratory", "cleanroom"} else "#80a7a4"
                )
                d.line(
                    (x * P, y * P + 1, (x + 1) * P - 1, y * P + 1), fill=color, width=2
                )
        return image

    def front(self, key, x, y):
        # Anchor a real building at its usable door. A covered, inset doorway is used
        # when a retail event occupies the cell where a wide facade would have to stand.
        for name in (key, key + "_compact"):
            if name not in CATALOG and not name.endswith("_front"):
                continue
            asset, anchor, im = prop(name)
            left = (x * P + 8 - anchor[0] + 3) // P
            right = (x * P + 8 - anchor[0] + im.width - 4) // P
            top = y - max(1, im.height // P - 1)
            r = (slice(top, y), slice(left, right + 1))
            if (
                left < 0
                or right >= self.w
                or top < 0
                or self.water[r].any()
                or self.occupied[r].any()
            ):
                continue
            if any(
                (xx, yy) in self.reserved
                for yy in range(top, y)
                for xx in range(left, right + 1)
            ):
                continue
            old = self.s[r].copy()
            self.s[r] = True
            if not self.accessible():
                self.s[r] = old
                continue
            self.occupied[r] = True
            self.props.append([asset, x, y - 1, list(anchor)])
            return True
        return False

    def furnish(self):
        st = self.style
        fx, fy = self.story
        entered = set()
        if st not in INTERIORS:
            for warp in self.m["warps"]:
                x, y = warp["at"]
                dest = warp["to"]["map"]
                short = dest.removeprefix("alola_")
                key = "center" if short.startswith("center_") else FRONTS.get(short)
                key = key or {
                    "armor_dojo": "gym",
                    "blueberry_academy": "academy",
                    "blueberry_club": "home_blue",
                    "kitakami_hall": "home_green",
                    "aether_lobby": "lab",
                    "aether_lab": "lab",
                    "orange_stadium": "gym",
                    "aether_mansion": "home_city",
                    "league": "gym",
                    "konikoni_gems": "gem_front",
                    "malie_library": "library_front",
                    "paniola_salon": "salon_front",
                    "heahea_office": "visitor_front",
                }.get(dest.removeprefix("alola_"))
                if key and self.front(key, x, y):
                    entered.add((x, y))
        self.place(self.features[0], (fx, max(2, fy - 3)), max_shift=9)
        # Compose fixtures according to use: shops have two aisles, ruins flank the
        # procession, farms have separated paddocks, and gardens follow the pond.
        if st in {
            "market",
            "warehouse",
            "laboratory",
            "cleanroom",
            "derelict",
            "study",
            "nursery",
            "campus",
            "manor",
            "studio",
            "atelier",
        }:
            sites = [(0.20, 0.28), (0.76, 0.30), (0.25, 0.63), (0.72, 0.64)]
        elif st in COURTS | SHRINES | {"castle", "throne", "prismtower"}:
            sites = [(0.25, 0.26), (0.76, 0.26), (0.18, 0.62), (0.80, 0.62)]
        elif st in {"ranch", "westerntown", "orchard"}:
            sites = [(0.23, 0.27), (0.73, 0.28), (0.29, 0.69), (0.77, 0.75)]
        elif st in COAST | {"garden", "wetlands", "conservatory", "floatvillage"}:
            sites = [(0.27, 0.56), (0.62, 0.28), (0.77, 0.57), (0.43, 0.73)]
        else:
            sites = [(0.23, 0.35), (0.68, 0.28), (0.75, 0.66), (0.31, 0.71)]
        for i, (ux, uy) in enumerate(sites):
            # Centres are relative to the usable part of the source mesh, excluding void at the far edges.
            cells = np.argwhere(self.limits())
            if not len(cells):
                break
            lo = np.percentile(cells, 4, axis=0)
            hi = np.percentile(cells, 96, axis=0)
            target = (
                round(lo[1] + (hi[1] - lo[1]) * ux),
                round(lo[0] + (hi[0] - lo[0]) * uy),
            )
            self.place(
                self.features[1 + i % (len(self.features) - 1)], target, max_shift=7
            )
        if st in {
            "ranch",
            "orchard",
            "graves",
            "bamboo",
            "market",
            "warehouse",
            "campus",
        }:
            key = {
                "ranch": "fence",
                "orchard": "berry_tree",
                "graves": "memorial",
                "bamboo": "bamboo",
                "market": "rack",
                "warehouse": "crate",
                "campus": "desk",
            }[st]
            for row in [-4, 2]:
                for off in [-10, -6, 6, 10]:
                    self.place(key, (fx + off, fy + row), max_shift=2)
        if self.mid == "battle_tree":
            # Battle Tree is held on a large tree. Draw the crown in back of the wooden platform.
            for dx, dy in [(-6, -2), (-4, -4), (-1, -5), (2, -5), (5, -4), (6, -2)]:
                self.place("tree", (fx + dx, fy + dy), 3)
        # Preserve registered activity counters even if their source art was removed.
        for obj in self.m.get("objects", []):
            if obj.get("alola_club"):
                x, y = obj["at"]
                self.props.append(["console", x, y])
        scenery.town_edges(self)
        special.finish(self)
        self.scatter()
        return entered

    def render(self, source, mid):
        original = self.s.copy()
        if not self.native:
            self.carve_expansion()
        self.terrain_solid = self.s.copy()
        self.survey(source)
        self.trails()
        entered = self.furnish()
        self.grass &= ~self.s
        image = scenery.pattern(
            self,
            architecture.ring(
                self,
                self.walkway(architecture.walls(self, self.draw_relief(self.art()))),
            ),
        )
        special.conduits(self, image)
        # Every entry gets an identifiable threshold; outdoor passages use inset stones,
        # interiors a short contrasting mat. The centre point is always the step trigger.
        d = ImageDraw.Draw(image)
        for x, y in self.door:
            l = x * P
            t = y * P
            if (x, y) in entered:
                d.rectangle(
                    (l + 1, t + 1, l + 14, t + 10), fill="#ac9981", outline="#776f68"
                )
                d.line((l + 2, t + 3, l + 13, t + 3), fill="#e6d2ab")
                continue
            if self.style in INTERIORS:
                d.rectangle(
                    (l + 1, t + 4, l + 14, t + 12), fill="#96786d", outline="#72635d"
                )
                d.line((l + 3, t + 6, l + 12, t + 6), fill="#d6b799")
            else:
                d.line(
                    (l + 2, t + 10, l + 7, t + 7, l + 13, t + 10),
                    fill="#775f59",
                    width=3,
                )
                d.line(
                    (l + 2, t + 9, l + 7, t + 6, l + 13, t + 9), fill="#e5c997", width=2
                )
        if not self.accessible():
            raise ValueError((mid, "changed access"))
        self.m["island_field_revision"] = 1
        if self.native:
            self.m["physics"]["collision"] = self.s.astype("uint8").tolist()
            if "grass" in self.m["physics"]:
                self.m["physics"]["grass"] = self.grass.astype("uint8").tolist()
            path = ROOT / "assets/alola/maps" / (self.m["alola_image"] + ".png")
        else:
            path = OUTPUT / (mid + ".png")
            path.parent.mkdir(exist_ok=True)
            self.m["tiles"] = np.select(
                (self.s, self.water, self.grass), (1, 2, 11), default=0
            ).tolist()
            self.m["art_props"] = []
        self.m["hoenn_art"] = {
            "s": [self.w, self.h],
            "t": pack(np.zeros_like(self.s, dtype="<u2")),
            "p": self.props,
            "scene": ["res://" + path.relative_to(ROOT).as_posix(), 0, 0],
        }
        image.quantize(
            192, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE
        ).save(path, optimize=True)
        return int(np.sum(original != self.s)), len(self.props)


def build(source, only=None):
    native = parse(ALOLA)
    native["1"] = ("grassland", ["palm", "rock"])
    extra = parse(EXPEDITIONS)
    allmaps = {}
    for p in (source / MAPS).glob("*/maps/*.json"):
        allmaps[(p.parent.parent.name, p.stem)] = load(p)
    arrivals = {}
    for m in allmaps.values():
        for warp in m.get("warps", []):
            dest = warp.get("to", {})
            at = dest.get("at")
            if isinstance(at, list) and len(at) == 2:
                arrivals.setdefault((dest.get("region"), dest.get("map")), set()).add(
                    tuple(at)
                )
    from island_households import attach

    attach(allmaps, arrivals, source)
    for place, plan in {
        "konikoni_gems": "market crystals rack officecounter",
        "malie_library": "study archive bookshelf_home desk",
        "paniola_salon": "dining barrel desk rack",
        "heahea_office": "civic archive officecounter clock",
    }.items():
        parts = plan.split()
        native[place] = (parts[0], parts[1:])
    alola_ids = {
        mid.removeprefix("alola_")
        for (reg, mid), m in allmaps.items()
        if reg == "alola" and m.get("alola_native")
    }
    retained = {
        s
        for s in alola_ids
        if (s in UNTOUCHED and s not in native) or s.startswith(("pelago_", "center_"))
    }
    assert alola_ids == native.keys() | retained, (
        alola_ids - native.keys() - retained,
        native.keys() - alola_ids,
    )
    processed = 0
    for (reg, mid), m in sorted(allmaps.items()):
        short = mid.removeprefix("alola_")
        plan = (
            native.get(short)
            if reg == "alola" and m.get("alola_native")
            else extra.get(mid)
        )
        if not plan or only and mid not in only:
            continue
        if reg == "alola":
            special.expand(m, short)
        f = Field(
            m,
            short if m.get("alola_native") else mid,
            *plan,
            arrivals.get((reg, mid), set()),
        )
        if mid == "alola_1":
            alola_route1_coast.paint(f, source)
            processed += 1
            continue
        changed, props = f.render(source, mid)
        if mid in ("alola_aether_docks","alola_ultra_plant","ultra_plant"):
            from alola_remote_facilities import place
            place(m, mid)
        if mid == "alola_aether_docks":
            from alola_port_surfaces import cargo_stacks, docks
            cargo_stacks(m)
            docks(m)
        if mid == "alola_aether_entrance":
            from alola_aether_lift import floor
            floor(m)
        if reg == "alola":
            from regional_frontages import dress_map
            dress_map(m, reg)
        write(ROOT / MAPS / reg / "maps" / (mid + ".json"), m)
        print(mid, changed, props, flush=True)
        processed += 1
    if not only:
        assert processed == len(native) + len(extra), (
            processed,
            len(native),
            len(extra),
        )
    if not only or only.issuperset("alola_" + k for k in native):
        p = ROOT / MAPS / "alola/region.json"
        region = load(p)
        region["maps"] = sorted(k for r, k in allmaps if r == "alola")
        write(p, region)
        print("REDRAWN", processed, "retained Alola", len(retained))


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--source", type=Path, required=True)
    ap.add_argument("maps", nargs="*")
    args = ap.parse_args()
    build(args.source, set(args.maps))
